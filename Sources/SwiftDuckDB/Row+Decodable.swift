import Foundation
import SwifQL

// MARK: - Public decoding API

extension Row {
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

    /// Returns the native payload when `T` is a current SwiftDuckDB scalar family
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
                            "Row values count is inconsistent with column layout at index \(index) for key '\(key)'"
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
    var userInfo: [CodingUserInfoKey: Any] { [:] }

    func container<Key: CodingKey>(
        keyedBy type: Key.Type
    ) throws -> KeyedDecodingContainer<Key> {
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
