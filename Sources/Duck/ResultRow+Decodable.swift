import Foundation
import SQL

// MARK: - Public decoding API

extension ResultRow {
    /// Decodes this row into a flat `Decodable` model.
    ///
    /// Column matching uses visible names. When `prefix` is non-empty, only
    /// result columns whose names begin with that prefix are visible, and
    /// exactly one leading prefix occurrence is stripped before `CodingKeys`
    /// lookup. Ambiguous duplicate visible column names are rejected.
    ///
    /// - Parameters:
    ///   - type: The model type to decode.
    ///   - prefix: Optional column-name prefix scoping. Empty is treated as no prefix.
    /// - Returns: A decoded model value.
    /// - Throws: `DecodingError` for missing keys, SQL `NULL` in required
    ///   positions, incompatible kinds, ambiguous duplicates, or unsupported
    ///   nested/unkeyed structures.
    public func decode<T: Decodable>(
        _ type: T.Type,
        prefix: String? = nil
    ) throws -> T {
        let layout = RowDecodingLayout(columns: columns, prefix: prefix)
        return try T(from: RowModelDecoder(layout: layout, values: values))
    }
}

extension QueryResult {
    /// Decodes the first result row into a flat `Decodable` model.
    ///
    /// Returns `nil` when the result has zero rows. Decoding failures throw;
    /// they are never swallowed as `nil`.
    public func first<T: Decodable>(
        decoding type: T.Type,
        prefix: String? = nil
    ) throws -> T? {
        guard let row = rows.first else {
            return nil
        }
        let layout = RowDecodingLayout(columns: columns, prefix: prefix)
        return try T(from: RowModelDecoder(layout: layout, values: row.values))
    }

    /// Decodes every result row into flat `Decodable` models in original order.
    ///
    /// The first decoding failure throws. There is no partial-result return.
    public func all<T: Decodable>(
        decoding type: T.Type,
        prefix: String? = nil
    ) throws -> [T] {
        let layout = RowDecodingLayout(columns: columns, prefix: prefix)
        var models: [T] = []
        models.reserveCapacity(rows.count)
        for row in rows {
            models.append(try T(from: RowModelDecoder(layout: layout, values: row.values)))
        }
        return models
    }
}

// MARK: - Layout

struct RowDecodingLayout: Sendable {
    enum Lookup: Sendable {
        case missing
        case unique(index: Int, visibleName: String)
        case ambiguous(visibleName: String)
    }

    /// Visible name -> source column indices. Array-valued so duplicates remain detectable.
    let visibleIndices: [String: [Int]]
    /// First-visible-key order for `allKeys`.
    let visibleKeys: [String]
    let prefix: String?

    init(columns: [String], prefix: String?) {
        let normalizedPrefix = RowDecodingLayout.normalize(prefix)
        self.prefix = normalizedPrefix

        var built: [String: [Int]] = [:]
        var order: [String] = []
        built.reserveCapacity(columns.count)
        order.reserveCapacity(columns.count)

        for (index, rawName) in columns.enumerated() {
            let visible: String
            if let normalizedPrefix {
                guard rawName.hasPrefix(normalizedPrefix) else {
                    continue
                }
                visible = String(rawName.dropFirst(normalizedPrefix.count))
            } else {
                visible = rawName
            }
            if built[visible] == nil {
                order.append(visible)
            }
            built[visible, default: []].append(index)
        }

        self.visibleIndices = built
        self.visibleKeys = order
    }

    static func normalize(_ prefix: String?) -> String? {
        guard let prefix, !prefix.isEmpty else {
            return nil
        }
        return prefix
    }

    func lookup(_ key: String) -> Lookup {
        guard let indices = visibleIndices[key], !indices.isEmpty else {
            return .missing
        }
        if indices.count > 1 {
            return .ambiguous(visibleName: key)
        }
        return .unique(index: indices[0], visibleName: key)
    }
}

// MARK: - Coding key

struct RowCodingKey: CodingKey, Hashable, Sendable {
    var stringValue: String
    var intValue: Int? { nil }

    init(_ string: String) {
        self.stringValue = string
    }

    init?(stringValue: String) {
        self.stringValue = stringValue
    }

    init?(intValue: Int) {
        return nil
    }
}

struct RowIndexCodingKey: CodingKey, Hashable, Sendable {
    var stringValue: String
    var intValue: Int?

    init(_ index: Int) {
        self.stringValue = String(index)
        self.intValue = index
    }

    init?(stringValue: String) {
        guard let index = Int(stringValue) else {
            return nil
        }
        self.init(index)
    }

    init?(intValue: Int) {
        self.init(intValue)
    }
}

// MARK: - Checked model Int / UInt

enum RowIntegerPolicy {
    /// Model-layer convenience: exact signed integral kinds only, via `Int(exactly:)`.
    static func checkedInt(from value: Value) -> Int? {
        if let payload = value.get(Int8.self) {
            return Int(exactly: payload)
        }
        if let payload = value.get(Int16.self) {
            return Int(exactly: payload)
        }
        if let payload = value.get(Int32.self) {
            return Int(exactly: payload)
        }
        if let payload = value.get(Int64.self) {
            return Int(exactly: payload)
        }
        return nil
    }

    /// Model-layer convenience: exact unsigned integral kinds only, via `UInt(exactly:)`.
    static func checkedUInt(from value: Value) -> UInt? {
        if let payload = value.get(UInt8.self) {
            return UInt(exactly: payload)
        }
        if let payload = value.get(UInt16.self) {
            return UInt(exactly: payload)
        }
        if let payload = value.get(UInt32.self) {
            return UInt(exactly: payload)
        }
        if let payload = value.get(UInt64.self) {
            return UInt(exactly: payload)
        }
        return nil
    }
}

// MARK: - Native intercept

enum RowNativeIntercept {
    /// Returns true when `type` is a current native scalar family that must
    /// never be reconstructed through generic Codable representations.
    static func isNativeFamily(_ type: Any.Type) -> Bool {
        type == Bool.self
            || type == Int8.self
            || type == Int16.self
            || type == Int32.self
            || type == Int64.self
            || type == UInt8.self
            || type == UInt16.self
            || type == UInt32.self
            || type == UInt64.self
            || type == Float.self
            || type == Double.self
            || type == String.self
            || type == Data.self
            || type == UUID.self
            || type == PureDate.self
            || type == PureTime.self
            || type == DateTime.self
            || type == Date.self
            || type == Interval.self
            || type == Decimal.self
            || type == Int.self
            || type == UInt.self
            || {
                if #available(macOS 15.0, iOS 18.0, *) {
                    return type == Int128.self || type == UInt128.self
                }
                return false
            }()
    }

    /// Returns the native payload when `T` is a current Duck scalar family
    /// and the stored kind matches exactly (or satisfies the checked Int/UInt policy).
    /// Returns `nil` when native interception does not apply.
    static func decode<T: Decodable>(_ type: T.Type, from value: Value) -> T? {
        if T.self == Bool.self {
            return value.get(Bool.self) as? T
        }
        if T.self == Int8.self {
            return value.get(Int8.self) as? T
        }
        if T.self == Int16.self {
            return value.get(Int16.self) as? T
        }
        if T.self == Int32.self {
            return value.get(Int32.self) as? T
        }
        if T.self == Int64.self {
            return value.get(Int64.self) as? T
        }
        if T.self == UInt8.self {
            return value.get(UInt8.self) as? T
        }
        if T.self == UInt16.self {
            return value.get(UInt16.self) as? T
        }
        if T.self == UInt32.self {
            return value.get(UInt32.self) as? T
        }
        if T.self == UInt64.self {
            return value.get(UInt64.self) as? T
        }
        if T.self == Float.self {
            return value.get(Float.self) as? T
        }
        if T.self == Double.self {
            return value.get(Double.self) as? T
        }
        if T.self == String.self {
            return value.get(String.self) as? T
        }
        if T.self == Data.self {
            return value.get(Data.self) as? T
        }
        if T.self == UUID.self {
            return value.get(UUID.self) as? T
        }
        if T.self == PureDate.self {
            return value.get(PureDate.self) as? T
        }
        if T.self == PureTime.self {
            return value.get(PureTime.self) as? T
        }
        if T.self == DateTime.self {
            return value.get(DateTime.self) as? T
        }
        if T.self == Date.self {
            return value.get(Date.self) as? T
        }
        if T.self == Interval.self {
            return value.get(Interval.self) as? T
        }
        if T.self == Decimal.self {
            return value.get(Decimal.self) as? T
        }
        if T.self == Int.self {
            return RowIntegerPolicy.checkedInt(from: value) as? T
        }
        if T.self == UInt.self {
            return RowIntegerPolicy.checkedUInt(from: value) as? T
        }
        if #available(macOS 15.0, iOS 18.0, *) {
            if T.self == Int128.self {
                return value.get(Int128.self) as? T
            }
            if T.self == UInt128.self {
                return value.get(UInt128.self) as? T
            }
        }
        return nil
    }
}

// MARK: - Root row decoder

struct RowModelDecoder: Decoder {
    let layout: RowDecodingLayout
    let values: [Value]
    let codingPath: [CodingKey]
    var userInfo: [CodingUserInfoKey: Any] { [:] }

    init(
        layout: RowDecodingLayout,
        values: [Value],
        codingPath: [CodingKey] = []
    ) {
        self.layout = layout
        self.values = values
        self.codingPath = codingPath
    }

    func container<Key: CodingKey>(
        keyedBy type: Key.Type
    ) throws -> KeyedDecodingContainer<Key> {
        KeyedDecodingContainer(RowKeyedDecodingContainer(decoder: self))
    }

    func unkeyedContainer() throws -> UnkeyedDecodingContainer {
        throw DecodingError.typeMismatch(
            [Any].self,
            DecodingError.Context(
                codingPath: codingPath,
                debugDescription: "Flat row decoder does not support top-level unkeyed containers"
            )
        )
    }

    func singleValueContainer() throws -> SingleValueDecodingContainer {
        throw DecodingError.typeMismatch(
            Any.self,
            DecodingError.Context(
                codingPath: codingPath,
                debugDescription: "Top-level single-value decoding is not supported for flat row models"
            )
        )
    }

    func value(for key: String) throws -> Value {
        switch layout.lookup(key) {
        case .missing:
            var message = "Missing required column '\(key)'"
            if let prefix = layout.prefix {
                message += " (prefix '\(prefix)')"
            }
            throw DecodingError.keyNotFound(
                RowCodingKey(key),
                DecodingError.Context(
                    codingPath: codingPath + [RowCodingKey(key)],
                    debugDescription: message
                )
            )
        case .ambiguous(let visibleName):
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: codingPath + [RowCodingKey(key)],
                    debugDescription:
                        "ambiguous duplicate column '\(visibleName)' maps to multiple result columns"
                )
            )
        case .unique(let index, _):
            guard values.indices.contains(index) else {
                throw DecodingError.dataCorrupted(
                    DecodingError.Context(
                        codingPath: codingPath + [RowCodingKey(key)],
                        debugDescription:
                            "ResultRow values count is inconsistent with column layout at index \(index) for key '\(key)'"
                    )
                )
            }
            return values[index]
        }
    }
}

// MARK: - Keyed container

struct RowKeyedDecodingContainer<Key: CodingKey>: KeyedDecodingContainerProtocol {
    let decoder: RowModelDecoder

    var codingPath: [CodingKey] { decoder.codingPath }

    var allKeys: [Key] {
        decoder.layout.visibleKeys.compactMap { Key(stringValue: $0) }
    }

    func contains(_ key: Key) -> Bool {
        if case .missing = decoder.layout.lookup(key.stringValue) {
            return false
        }
        return true
    }

    func decodeNil(forKey key: Key) throws -> Bool {
        try decoder.value(for: key.stringValue).isNull
    }

    func decode(_ type: Bool.Type, forKey key: Key) throws -> Bool {
        try decodeValue(type, forKey: key)
    }

    func decode(_ type: String.Type, forKey key: Key) throws -> String {
        try decodeValue(type, forKey: key)
    }

    func decode(_ type: Double.Type, forKey key: Key) throws -> Double {
        try decodeValue(type, forKey: key)
    }

    func decode(_ type: Float.Type, forKey key: Key) throws -> Float {
        try decodeValue(type, forKey: key)
    }

    func decode(_ type: Int.Type, forKey key: Key) throws -> Int {
        try decodeValue(type, forKey: key)
    }

    func decode(_ type: Int8.Type, forKey key: Key) throws -> Int8 {
        try decodeValue(type, forKey: key)
    }

    func decode(_ type: Int16.Type, forKey key: Key) throws -> Int16 {
        try decodeValue(type, forKey: key)
    }

    func decode(_ type: Int32.Type, forKey key: Key) throws -> Int32 {
        try decodeValue(type, forKey: key)
    }

    func decode(_ type: Int64.Type, forKey key: Key) throws -> Int64 {
        try decodeValue(type, forKey: key)
    }

    func decode(_ type: UInt.Type, forKey key: Key) throws -> UInt {
        try decodeValue(type, forKey: key)
    }

    func decode(_ type: UInt8.Type, forKey key: Key) throws -> UInt8 {
        try decodeValue(type, forKey: key)
    }

    func decode(_ type: UInt16.Type, forKey key: Key) throws -> UInt16 {
        try decodeValue(type, forKey: key)
    }

    func decode(_ type: UInt32.Type, forKey key: Key) throws -> UInt32 {
        try decodeValue(type, forKey: key)
    }

    func decode(_ type: UInt64.Type, forKey key: Key) throws -> UInt64 {
        try decodeValue(type, forKey: key)
    }

    @available(macOS 15.0, iOS 18.0, *)
    func decode(_ type: Int128.Type, forKey key: Key) throws -> Int128 {
        try decodeValue(type, forKey: key)
    }

    @available(macOS 15.0, iOS 18.0, *)
    func decode(_ type: UInt128.Type, forKey key: Key) throws -> UInt128 {
        try decodeValue(type, forKey: key)
    }

    func decode<T: Decodable>(_ type: T.Type, forKey key: Key) throws -> T {
        try decodeValue(type, forKey: key)
    }

    func nestedContainer<NestedKey: CodingKey>(
        keyedBy type: NestedKey.Type,
        forKey key: Key
    ) throws -> KeyedDecodingContainer<NestedKey> {
        throw DecodingError.typeMismatch(
            [String: Any].self,
            DecodingError.Context(
                codingPath: codingPath + [key],
                debugDescription:
                    "Flat row decoder does not support nested keyed containers for key '\(key.stringValue)'"
            )
        )
    }

    func nestedUnkeyedContainer(forKey key: Key) throws -> UnkeyedDecodingContainer {
        throw DecodingError.typeMismatch(
            [Any].self,
            DecodingError.Context(
                codingPath: codingPath + [key],
                debugDescription:
                    "Flat row decoder does not support nested unkeyed containers for key '\(key.stringValue)'"
            )
        )
    }

    func superDecoder() throws -> Decoder {
        throw DecodingError.typeMismatch(
            Any.self,
            DecodingError.Context(
                codingPath: codingPath,
                debugDescription: "Flat row decoder does not support superDecoder class-inheritance paths"
            )
        )
    }

    func superDecoder(forKey key: Key) throws -> Decoder {
        throw DecodingError.typeMismatch(
            Any.self,
            DecodingError.Context(
                codingPath: codingPath + [key],
                debugDescription:
                    "Flat row decoder does not support superDecoder(forKey:) for key '\(key.stringValue)'"
            )
        )
    }

    private func decodeValue<T: Decodable>(_ type: T.Type, forKey key: Key) throws -> T {
        let value = try decoder.value(for: key.stringValue)
        let path = codingPath + [key]

        if value.isNull {
            throw DecodingError.valueNotFound(
                type,
                DecodingError.Context(
                    codingPath: path,
                    debugDescription:
                        "SQL NULL for required key '\(key.stringValue)' (kind=\(value.kind.rawValue))"
                )
            )
        }

        if let native = RowNativeIntercept.decode(type, from: value) {
            return native
        }

        // Known native families must never fall through to generic Codable
        // representations (UUID text, Date reference interval, Data base64, etc.).
        if RowNativeIntercept.isNativeFamily(T.self) {
            throw DecodingError.typeMismatch(
                type,
                DecodingError.Context(
                    codingPath: path,
                    debugDescription:
                        "Incompatible database value for \(type) at key '\(key.stringValue)': actual Value.Kind \(value.kind.rawValue)"
                )
            )
        }

        return try T(
            from: RowValueDecoder(
                value: value,
                codingPath: path,
                requestedType: type
            )
        )
    }
}

// MARK: - Scalar fallback decoder

struct RowValueDecoder: Decoder {
    let value: Value
    let codingPath: [CodingKey]
    let requestedType: Any.Type
    /// P0 decodes only one-dimensional LISTs, so only a column-level LIST may open an
    /// unkeyed container; LIST element decoders keep nested collections rejected.
    let permitsListContainer: Bool
    /// P0 decodes one keyed STRUCT level; STRUCT member decoders disable this permission.
    let permitsStructContainer: Bool
    var userInfo: [CodingUserInfoKey: Any] { [:] }

    init(
        value: Value,
        codingPath: [CodingKey],
        requestedType: Any.Type,
        permitsListContainer: Bool = true,
        permitsStructContainer: Bool = true
    ) {
        self.value = value
        self.codingPath = codingPath
        self.requestedType = requestedType
        self.permitsListContainer = permitsListContainer
        self.permitsStructContainer = permitsStructContainer
    }

    func container<Key: CodingKey>(
        keyedBy type: Key.Type
    ) throws -> KeyedDecodingContainer<Key> {
        if permitsStructContainer, case .structure(let members) = value.storage {
            var seenNames: Set<String> = []
            for member in members {
                guard seenNames.insert(member.name).inserted else {
                    throw DecodingError.dataCorrupted(
                        DecodingError.Context(
                            codingPath: codingPath + [RowCodingKey(member.name)],
                            debugDescription:
                                "Value.structure contains duplicate member name '\(member.name)'"
                        )
                    )
                }
            }
            return KeyedDecodingContainer(
                RowStructDecodingContainer<Key>(
                    members: members,
                    codingPath: codingPath,
                    requestedType: requestedType
                )
            )
        }

        throw DecodingError.typeMismatch(
            [String: Any].self,
            DecodingError.Context(
                codingPath: codingPath,
                debugDescription:
                    "Expected single scalar value for \(requestedType), found keyed container request (kind=\(value.kind.rawValue))"
            )
        )
    }

    func unkeyedContainer() throws -> UnkeyedDecodingContainer {
        if permitsListContainer, case .list(let children) = value.storage {
            return RowListDecodingContainer(
                children: children,
                codingPath: codingPath,
                requestedType: requestedType
            )
        }

        throw DecodingError.typeMismatch(
            [Any].self,
            DecodingError.Context(
                codingPath: codingPath,
                debugDescription:
                    "Expected single scalar value for \(requestedType), found unkeyed container request (kind=\(value.kind.rawValue))"
            )
        )
    }

    func singleValueContainer() throws -> SingleValueDecodingContainer {
        RowSingleValueDecodingContainer(
            value: value,
            codingPath: codingPath,
            requestedType: requestedType
        )
    }
}

struct RowSingleValueDecodingContainer: SingleValueDecodingContainer {
    let value: Value
    let codingPath: [CodingKey]
    let requestedType: Any.Type

    func decodeNil() -> Bool {
        value.isNull
    }

    func decode<T: Decodable>(_ type: T.Type) throws -> T {
        if value.isNull {
            throw DecodingError.valueNotFound(
                type,
                DecodingError.Context(
                    codingPath: codingPath,
                    debugDescription: "SQL NULL (kind=\(value.kind.rawValue))"
                )
            )
        }

        if let native = RowNativeIntercept.decode(type, from: value) {
            return native
        }

        throw DecodingError.typeMismatch(
            type,
            DecodingError.Context(
                codingPath: codingPath,
                debugDescription:
                    "Incompatible database value for \(type): actual Value.Kind \(value.kind.rawValue)"
            )
        )
    }
}

/// Decodes the named members of one `Value.structure` and rejects nested composites.
struct RowStructDecodingContainer<Key: CodingKey>: KeyedDecodingContainerProtocol {
    private let members: [Value.StructMember]
    private let indicesByName: [String: Int]
    let codingPath: [CodingKey]
    private let requestedType: Any.Type

    var allKeys: [Key] {
        members.compactMap { Key(stringValue: $0.name) }
    }

    init(
        members: [Value.StructMember],
        codingPath: [CodingKey],
        requestedType: Any.Type
    ) {
        self.members = members
        self.codingPath = codingPath
        self.requestedType = requestedType
        var indices: [String: Int] = [:]
        indices.reserveCapacity(members.count)
        for (index, member) in members.enumerated() {
            indices[member.name] = index
        }
        indicesByName = indices
    }

    func contains(_ key: Key) -> Bool {
        indicesByName[key.stringValue] != nil
    }

    func decodeNil(forKey key: Key) throws -> Bool {
        try value(for: key.stringValue).isNull
    }

    func decode(_ type: Bool.Type, forKey key: Key) throws -> Bool { try decodeValue(type, forKey: key) }
    func decode(_ type: String.Type, forKey key: Key) throws -> String { try decodeValue(type, forKey: key) }
    func decode(_ type: Double.Type, forKey key: Key) throws -> Double { try decodeValue(type, forKey: key) }
    func decode(_ type: Float.Type, forKey key: Key) throws -> Float { try decodeValue(type, forKey: key) }
    func decode(_ type: Int.Type, forKey key: Key) throws -> Int { try decodeValue(type, forKey: key) }
    func decode(_ type: Int8.Type, forKey key: Key) throws -> Int8 { try decodeValue(type, forKey: key) }
    func decode(_ type: Int16.Type, forKey key: Key) throws -> Int16 { try decodeValue(type, forKey: key) }
    func decode(_ type: Int32.Type, forKey key: Key) throws -> Int32 { try decodeValue(type, forKey: key) }
    func decode(_ type: Int64.Type, forKey key: Key) throws -> Int64 { try decodeValue(type, forKey: key) }
    func decode(_ type: UInt.Type, forKey key: Key) throws -> UInt { try decodeValue(type, forKey: key) }
    func decode(_ type: UInt8.Type, forKey key: Key) throws -> UInt8 { try decodeValue(type, forKey: key) }
    func decode(_ type: UInt16.Type, forKey key: Key) throws -> UInt16 { try decodeValue(type, forKey: key) }
    func decode(_ type: UInt32.Type, forKey key: Key) throws -> UInt32 { try decodeValue(type, forKey: key) }
    func decode(_ type: UInt64.Type, forKey key: Key) throws -> UInt64 { try decodeValue(type, forKey: key) }

    @available(macOS 15.0, iOS 18.0, *)
    func decode(_ type: Int128.Type, forKey key: Key) throws -> Int128 { try decodeValue(type, forKey: key) }

    @available(macOS 15.0, iOS 18.0, *)
    func decode(_ type: UInt128.Type, forKey key: Key) throws -> UInt128 { try decodeValue(type, forKey: key) }

    func decode<T: Decodable>(_ type: T.Type, forKey key: Key) throws -> T {
        try decodeValue(type, forKey: key)
    }

    func nestedContainer<NestedKey: CodingKey>(
        keyedBy type: NestedKey.Type,
        forKey key: Key
    ) throws -> KeyedDecodingContainer<NestedKey> {
        throw rejected(type: [String: Any].self, path: codingPath + [key], shape: "nested keyed containers")
    }

    func nestedUnkeyedContainer(forKey key: Key) throws -> UnkeyedDecodingContainer {
        throw rejected(type: [Any].self, path: codingPath + [key], shape: "nested unkeyed containers")
    }

    func superDecoder() throws -> Decoder {
        throw rejected(type: Any.self, path: codingPath, shape: "superDecoder")
    }

    func superDecoder(forKey key: Key) throws -> Decoder {
        _ = try value(for: key.stringValue)
        throw rejected(type: Any.self, path: codingPath + [key], shape: "superDecoder(forKey:)")
    }

    private func value(for name: String) throws -> Value {
        guard let index = indicesByName[name], members.indices.contains(index) else {
            throw DecodingError.keyNotFound(
                RowCodingKey(name),
                DecodingError.Context(
                    codingPath: codingPath + [RowCodingKey(name)],
                    debugDescription: "Missing required STRUCT member '\(name)'"
                )
            )
        }
        return members[index].value
    }

    private func decodeValue<T: Decodable>(_ type: T.Type, forKey key: Key) throws -> T {
        let memberValue = try value(for: key.stringValue)
        let path = codingPath + [key]
        guard !memberValue.isNull else {
            throw DecodingError.valueNotFound(
                type,
                DecodingError.Context(
                    codingPath: path,
                    debugDescription:
                        "SQL NULL for required STRUCT member '\(key.stringValue)' (kind=\(memberValue.kind.rawValue))"
                )
            )
        }

        if let native = RowNativeIntercept.decode(type, from: memberValue) {
            return native
        }
        if RowNativeIntercept.isNativeFamily(T.self) {
            throw DecodingError.typeMismatch(
                type,
                DecodingError.Context(
                    codingPath: path,
                    debugDescription:
                        "Incompatible STRUCT member for \(type): actual Value.Kind \(memberValue.kind.rawValue)"
                )
            )
        }

        return try T(
            from: RowValueDecoder(
                value: memberValue,
                codingPath: path,
                requestedType: type,
                permitsListContainer: false,
                permitsStructContainer: false
            )
        )
    }

    private func rejected(type: Any.Type, path: [CodingKey], shape: String) -> DecodingError {
        DecodingError.typeMismatch(
            type,
            DecodingError.Context(
                codingPath: path,
                debugDescription: "STRUCT decoding does not support \(shape) while decoding \(requestedType)"
            )
        )
    }
}

// MARK: - LIST unkeyed container

/// Decodes the children of one `Value.list`.
///
/// A reference type because `UnkeyedDecodingContainer.currentIndex` requires a
/// `nonmutating set`. Element decoding reuses the exact scalar/native rules of
/// keyed column decoding; nested keyed and nested unkeyed children stay rejected in P0.
final class RowListDecodingContainer: UnkeyedDecodingContainer {
    let codingPath: [CodingKey]
    let requestedType: Any.Type
    private let children: [Value]

    var currentIndex: Int = 0

    var count: Int? { children.count }

    var isAtEnd: Bool { currentIndex >= children.count }

    init(children: [Value], codingPath: [CodingKey], requestedType: Any.Type) {
        self.children = children
        self.codingPath = codingPath
        self.requestedType = requestedType
    }

    /// Consumes the current child only when it is SQL NULL.
    func decodeNil() -> Bool {
        guard !isAtEnd, children[currentIndex].isNull else {
            return false
        }
        currentIndex += 1
        return true
    }

    func decode<T: Decodable>(_ type: T.Type) throws -> T {
        try decodeElement(type)
    }

    func decode(_ type: Bool.Type) throws -> Bool { try decodeElement(Bool.self) }
    func decode(_ type: String.Type) throws -> String { try decodeElement(String.self) }
    func decode(_ type: Double.Type) throws -> Double { try decodeElement(Double.self) }
    func decode(_ type: Float.Type) throws -> Float { try decodeElement(Float.self) }
    func decode(_ type: Int.Type) throws -> Int { try decodeElement(Int.self) }
    func decode(_ type: Int8.Type) throws -> Int8 { try decodeElement(Int8.self) }
    func decode(_ type: Int16.Type) throws -> Int16 { try decodeElement(Int16.self) }
    func decode(_ type: Int32.Type) throws -> Int32 { try decodeElement(Int32.self) }
    func decode(_ type: Int64.Type) throws -> Int64 { try decodeElement(Int64.self) }
    func decode(_ type: UInt.Type) throws -> UInt { try decodeElement(UInt.self) }
    func decode(_ type: UInt8.Type) throws -> UInt8 { try decodeElement(UInt8.self) }
    func decode(_ type: UInt16.Type) throws -> UInt16 { try decodeElement(UInt16.self) }
    func decode(_ type: UInt32.Type) throws -> UInt32 { try decodeElement(UInt32.self) }
    func decode(_ type: UInt64.Type) throws -> UInt64 { try decodeElement(UInt64.self) }

    @available(macOS 15.0, iOS 18.0, *)
    func decode(_ type: Int128.Type) throws -> Int128 { try decodeElement(Int128.self) }

    @available(macOS 15.0, iOS 18.0, *)
    func decode(_ type: UInt128.Type) throws -> UInt128 { try decodeElement(UInt128.self) }

    func nestedContainer<NestedKey: CodingKey>(
        keyedBy type: NestedKey.Type
    ) throws -> KeyedDecodingContainer<NestedKey> {
        throw rejected(type: [String: Any].self, description: "nested keyed containers")
    }

    func nestedUnkeyedContainer() throws -> UnkeyedDecodingContainer {
        throw rejected(type: [Any].self, description: "nested unkeyed containers")
    }

    func superDecoder() throws -> Decoder {
        throw rejected(type: Any.self, description: "superDecoder")
    }

    private func decodeElement<T: Decodable>(_ type: T.Type) throws -> T {
        let child = try next(type)
        let index = currentIndex - 1
        let path = codingPath + [RowIndexCodingKey(index)]

        // A SQL NULL child is resolved by the element type itself: an Optional element
        // becomes `.none` through its single-value `decodeNil()`, while a required element
        // still fails as `valueNotFound`, exactly like keyed column decoding.
        if child.isNull {
            return try T(
                from: RowValueDecoder(
                    value: child,
                    codingPath: path,
                    requestedType: type,
                    permitsListContainer: false,
                    permitsStructContainer: false
                )
            )
        }

        if let native = RowNativeIntercept.decode(type, from: child) {
            return native
        }

        if RowNativeIntercept.isNativeFamily(type) {
            throw DecodingError.typeMismatch(
                type,
                DecodingError.Context(
                    codingPath: path,
                    debugDescription:
                        "Incompatible database value for \(type) at LIST element \(index): actual Value.Kind \(child.kind.rawValue)"
                )
            )
        }

        return try T(
            from: RowValueDecoder(
                value: child,
                codingPath: path,
                requestedType: type,
                permitsListContainer: false,
                permitsStructContainer: false
            )
        )
    }

    private func next(_ type: Any.Type) throws -> Value {
        guard !isAtEnd else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: codingPath + [RowIndexCodingKey(currentIndex)],
                    debugDescription: "LIST container is at end while decoding \(type)"
                )
            )
        }
        let child = children[currentIndex]
        currentIndex += 1
        return child
    }

    private func rejected(type: Any.Type, description: String) -> DecodingError {
        DecodingError.typeMismatch(
            type,
            DecodingError.Context(
                codingPath: codingPath + [RowIndexCodingKey(currentIndex)],
                debugDescription:
                    "LIST decoding does not support \(description) in this wave while decoding \(requestedType)"
            )
        )
    }
}
