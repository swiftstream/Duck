import Foundation
import SQL

// MARK: - Public API

/// Encodes a flat keyed `Encodable` model into exact Duck `Value` fields.
///
/// Top-level encoding requires a keyed model. Nested keyed/unkeyed/collection
/// structures are rejected in P0. Field order follows the model's encoding
/// invocation order. Duplicate encoded keys are rejected.
public struct ModelEncoder: Sendable {
    public init() {}

    public func encode<T: Encodable>(_ value: T) throws -> EncodedModel {
        let storage = ModelEncodingStorage()
        try value.encode(to: ModelValueEncoder(storage: storage, codingPath: []))
        return EncodedModel(fields: storage.fields)
    }
}

/// Ordered projection of a flat model into Duck values.
public struct EncodedModel: Sendable, Equatable {
    public struct Field: Sendable, Equatable {
        public let key: String
        public let value: Value

        init(key: String, value: Value) {
            self.key = key
            self.value = value
        }
    }

    public let fields: [Field]

    init(fields: [Field]) {
        self.fields = fields
    }
}

// MARK: - Storage

final class ModelEncodingStorage {
    private(set) var fields: [EncodedModel.Field] = []
    private var seenKeys: Set<String> = []

    func append(key: String, value: Value, codingPath: [CodingKey]) throws {
        guard seenKeys.insert(key).inserted else {
            throw EncodingError.invalidValue(
                key,
                EncodingError.Context(
                    codingPath: codingPath,
                    debugDescription: "Duplicate encoded key '\(key)'"
                )
            )
        }
        fields.append(EncodedModel.Field(key: key, value: value))
    }
}

// MARK: - Coding key

struct ModelCodingKey: CodingKey, Hashable, Sendable {
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

// MARK: - Optional reflection (no Mirror)

protocol ModelOptionalEncodable {
    var isNil: Bool { get }
    var wrappedEncodable: Encodable? { get }
}

extension Optional: ModelOptionalEncodable {
    var isNil: Bool {
        if case .none = self {
            return true
        }
        return false
    }

    var wrappedEncodable: Encodable? {
        switch self {
        case .some(let value as Encodable):
            return value
        default:
            return nil
        }
    }
}

// MARK: - Array property conversion

/// Marks the one collection shape a flat model may carry: a Swift `Array` used
/// as a single keyed property, whose elements are each exactly one scalar.
///
/// Deliberately adopted only by `Array`. `Dictionary`, `Set` and nested
/// collections stay on the rejecting Codable paths.
protocol ModelListEncodable {
    func encodeModelListElements(codingPath: [CodingKey]) throws -> [Value]
}

extension Array: ModelListEncodable where Element: Encodable {
    func encodeModelListElements(codingPath: [CodingKey]) throws -> [Value] {
        var children: [Value] = []
        children.reserveCapacity(count)
        for (index, element) in enumerated() {
            let path = codingPath + [ModelIndexCodingKey(index)]
            if let optional = element as? any ModelOptionalEncodable {
                if optional.isNil {
                    children.append(.null)
                    continue
                }
                guard let wrapped = optional.wrappedEncodable else {
                    throw EncodingError.invalidValue(
                        element,
                        EncodingError.Context(
                            codingPath: path,
                            debugDescription: "LIST element is not an Encodable scalar"
                        )
                    )
                }
                children.append(try ModelListElementConvert.scalar(wrapped, codingPath: path))
                continue
            }
            children.append(try ModelListElementConvert.scalar(element, codingPath: path))
        }
        return children
    }
}

enum ModelListElementConvert {
    /// One element -> exactly one scalar `Value`, never a nested container.
    static func scalar(_ element: any Encodable, codingPath: [CodingKey]) throws -> Value {
        if let native = try ModelNativeConvert.nativeValue(element, codingPath: codingPath) {
            return native
        }
        let capture = ModelScalarEncoder(codingPath: codingPath)
        try element.encode(to: capture)
        guard let captured = capture.capturedValue else {
            throw EncodingError.invalidValue(
                element,
                EncodingError.Context(
                    codingPath: codingPath,
                    debugDescription:
                        "LIST elements must encode as exactly one scalar Value, not \(type(of: element))"
                )
            )
        }
        return captured
    }
}

struct ModelIndexCodingKey: CodingKey, Hashable, Sendable {
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

// MARK: - Native conversion


enum ModelNativeConvert {
    static func checkedInt64(_ value: Int, codingPath: [CodingKey]) throws -> Value {
        guard let exact = Int64(exactly: value) else {
            throw EncodingError.invalidValue(
                value,
                EncodingError.Context(
                    codingPath: codingPath,
                    debugDescription: "Int value is not exactly representable as Int64"
                )
            )
        }
        return .int64(exact)
    }

    static func checkedUInt64(_ value: UInt, codingPath: [CodingKey]) throws -> Value {
        guard let exact = UInt64(exactly: value) else {
            throw EncodingError.invalidValue(
                value,
                EncodingError.Context(
                    codingPath: codingPath,
                    debugDescription: "UInt value is not exactly representable as UInt64"
                )
            )
        }
        return .uint64(exact)
    }

    /// Returns the exact native `Value` when `value` is a current Duck
    /// scalar family. Never routes those families through generic Codable.
    static func nativeValue(
        _ value: any Encodable,
        codingPath: [CodingKey]
    ) throws -> Value? {
        if let payload = value as? Bool {
            return .boolean(payload)
        }
        if let payload = value as? Int8 {
            return .int8(payload)
        }
        if let payload = value as? Int16 {
            return .int16(payload)
        }
        if let payload = value as? Int32 {
            return .int32(payload)
        }
        if let payload = value as? Int64 {
            return .int64(payload)
        }
        if let payload = value as? UInt8 {
            return .uint8(payload)
        }
        if let payload = value as? UInt16 {
            return .uint16(payload)
        }
        if let payload = value as? UInt32 {
            return .uint32(payload)
        }
        if let payload = value as? UInt64 {
            return .uint64(payload)
        }
        if let payload = value as? Float {
            return .float(payload)
        }
        if let payload = value as? Double {
            return .double(payload)
        }
        if let payload = value as? String {
            return .string(payload)
        }
        if let payload = value as? Data {
            return .blob(payload)
        }
        if let payload = value as? UUID {
            return .uuid(payload)
        }
        if let payload = value as? PureDate {
            return .date(payload)
        }
        if let payload = value as? PureTime {
            return .time(payload)
        }
        if let payload = value as? DateTime {
            return .dateTime(payload)
        }
        if let payload = value as? Date {
            return .timestampTZ(payload)
        }
        if let payload = value as? Interval {
            return .interval(payload)
        }
        if let payload = value as? Decimal {
            return .decimal(payload)
        }
        if let payload = value as? Int {
            return try checkedInt64(payload, codingPath: codingPath)
        }
        if let payload = value as? UInt {
            return try checkedUInt64(payload, codingPath: codingPath)
        }
        if #available(macOS 15.0, iOS 18.0, *) {
            if let payload = value as? Int128 {
                return .int128(payload)
            }
            if let payload = value as? UInt128 {
                return .uint128(payload)
            }
        }
        return nil
    }
}

// MARK: - Root model encoder

struct ModelValueEncoder: Encoder {
    let storage: ModelEncodingStorage
    let codingPath: [CodingKey]
    var userInfo: [CodingUserInfoKey: Any] { [:] }

    func container<Key: CodingKey>(
        keyedBy type: Key.Type
    ) -> KeyedEncodingContainer<Key> {
        KeyedEncodingContainer(
            ModelKeyedEncodingContainer(storage: storage, codingPath: codingPath)
        )
    }

    func unkeyedContainer() -> UnkeyedEncodingContainer {
        RejectingUnkeyedEncodingContainer(
            codingPath: codingPath,
            reason: "Flat model encoder does not support top-level unkeyed containers"
        )
    }

    func singleValueContainer() -> SingleValueEncodingContainer {
        RejectingSingleValueEncodingContainer(
            codingPath: codingPath,
            reason: "Top-level single-value encoding is not supported for flat models"
        )
    }
}

// MARK: - Keyed container

struct ModelKeyedEncodingContainer<Key: CodingKey>: KeyedEncodingContainerProtocol {
    let storage: ModelEncodingStorage
    var codingPath: [CodingKey]

    mutating func encodeNil(forKey key: Key) throws {
        try storage.append(
            key: key.stringValue,
            value: .null,
            codingPath: codingPath + [key]
        )
    }

    mutating func encode(_ value: Bool, forKey key: Key) throws {
        try append(.boolean(value), forKey: key)
    }

    mutating func encode(_ value: String, forKey key: Key) throws {
        try append(.string(value), forKey: key)
    }

    mutating func encode(_ value: Double, forKey key: Key) throws {
        try append(.double(value), forKey: key)
    }

    mutating func encode(_ value: Float, forKey key: Key) throws {
        try append(.float(value), forKey: key)
    }

    mutating func encode(_ value: Int, forKey key: Key) throws {
        try append(try ModelNativeConvert.checkedInt64(value, codingPath: codingPath + [key]), forKey: key)
    }

    mutating func encode(_ value: Int8, forKey key: Key) throws {
        try append(.int8(value), forKey: key)
    }

    mutating func encode(_ value: Int16, forKey key: Key) throws {
        try append(.int16(value), forKey: key)
    }

    mutating func encode(_ value: Int32, forKey key: Key) throws {
        try append(.int32(value), forKey: key)
    }

    mutating func encode(_ value: Int64, forKey key: Key) throws {
        try append(.int64(value), forKey: key)
    }

    mutating func encode(_ value: UInt, forKey key: Key) throws {
        try append(try ModelNativeConvert.checkedUInt64(value, codingPath: codingPath + [key]), forKey: key)
    }

    mutating func encode(_ value: UInt8, forKey key: Key) throws {
        try append(.uint8(value), forKey: key)
    }

    mutating func encode(_ value: UInt16, forKey key: Key) throws {
        try append(.uint16(value), forKey: key)
    }

    mutating func encode(_ value: UInt32, forKey key: Key) throws {
        try append(.uint32(value), forKey: key)
    }

    mutating func encode(_ value: UInt64, forKey key: Key) throws {
        try append(.uint64(value), forKey: key)
    }

    @available(macOS 15.0, iOS 18.0, *)
    mutating func encode(_ value: Int128, forKey key: Key) throws {
        try append(.int128(value), forKey: key)
    }

    @available(macOS 15.0, iOS 18.0, *)
    mutating func encode(_ value: UInt128, forKey key: Key) throws {
        try append(.uint128(value), forKey: key)
    }

    mutating func encode<T: Encodable>(_ value: T, forKey key: Key) throws {
        let path = codingPath + [key]

        if let optional = value as? any ModelOptionalEncodable {
            if optional.isNil {
                try storage.append(key: key.stringValue, value: .null, codingPath: path)
                return
            }
            if let wrapped = optional.wrappedEncodable {
                try encode(wrapped, forKey: key)
                return
            }
        }

        if let list = value as? any ModelListEncodable {
            let children = try list.encodeModelListElements(codingPath: path)
            try storage.append(key: key.stringValue, value: .list(children), codingPath: path)
            return
        }

        if let native = try ModelNativeConvert.nativeValue(value, codingPath: path) {
            try storage.append(key: key.stringValue, value: native, codingPath: path)
            return
        }

        let capture = ModelScalarEncoder(codingPath: path, allowsStructuredCapture: true)
        try value.encode(to: capture)
        guard let captured = capture.capturedValue else {
            throw EncodingError.invalidValue(
                value,
                EncodingError.Context(
                    codingPath: path,
                    debugDescription:
                        "Flat model encoder cannot represent \(T.self) as a native scalar Value"
                )
            )
        }
        try storage.append(key: key.stringValue, value: captured, codingPath: path)
    }

    func nestedContainer<NestedKey: CodingKey>(
        keyedBy type: NestedKey.Type,
        forKey key: Key
    ) -> KeyedEncodingContainer<NestedKey> {
        KeyedEncodingContainer(
            RejectingKeyedEncodingContainer<NestedKey>(
                codingPath: codingPath + [key],
                reason: "Flat model encoder does not support nested keyed containers"
            )
        )
    }

    mutating func nestedUnkeyedContainer(forKey key: Key) -> UnkeyedEncodingContainer {
        RejectingUnkeyedEncodingContainer(
            codingPath: codingPath + [key],
            reason: "Flat model encoder does not support nested unkeyed containers"
        )
    }

    mutating func superEncoder() -> Encoder {
        RejectingEncoder(
            codingPath: codingPath,
            reason: "Flat model encoder does not support superEncoder class-inheritance paths"
        )
    }

    mutating func superEncoder(forKey key: Key) -> Encoder {
        RejectingEncoder(
            codingPath: codingPath + [key],
            reason: "Flat model encoder does not support superEncoder(forKey:)"
        )
    }

    private func append(_ value: Value, forKey key: Key) throws {
        try storage.append(
            key: key.stringValue,
            value: value,
            codingPath: codingPath + [key]
        )
    }
}

/// Ordered storage for the one keyed STRUCT captured by a scalar fallback encoder.
final class ModelStructEncodingStorage {
    private(set) var members: [Value.StructMember] = []
    private var seenNames: Set<String> = []

    func append(name: String, value: Value, codingPath: [CodingKey]) throws {
        guard seenNames.insert(name).inserted else {
            throw EncodingError.invalidValue(
                name,
                EncodingError.Context(
                    codingPath: codingPath,
                    debugDescription: "Duplicate encoded STRUCT member '\(name)'"
                )
            )
        }
        members.append(Value.StructMember(name: name, value: value))
    }
}

/// Captures exactly one keyed STRUCT level and rejects nested composite values.
struct ModelStructEncodingContainer<Key: CodingKey>: KeyedEncodingContainerProtocol {
    let storage: ModelStructEncodingStorage
    let encoder: ModelScalarEncoder
    var codingPath: [CodingKey]

    mutating func encodeNil(forKey key: Key) throws {
        try append(.null, forKey: key)
    }

    mutating func encode(_ value: Bool, forKey key: Key) throws {
        try append(.boolean(value), forKey: key)
    }

    mutating func encode(_ value: String, forKey key: Key) throws {
        try append(.string(value), forKey: key)
    }

    mutating func encode(_ value: Double, forKey key: Key) throws {
        try append(.double(value), forKey: key)
    }

    mutating func encode(_ value: Float, forKey key: Key) throws {
        try append(.float(value), forKey: key)
    }

    mutating func encode(_ value: Int, forKey key: Key) throws {
        try append(try ModelNativeConvert.checkedInt64(value, codingPath: codingPath + [key]), forKey: key)
    }

    mutating func encode(_ value: Int8, forKey key: Key) throws {
        try append(.int8(value), forKey: key)
    }

    mutating func encode(_ value: Int16, forKey key: Key) throws {
        try append(.int16(value), forKey: key)
    }

    mutating func encode(_ value: Int32, forKey key: Key) throws {
        try append(.int32(value), forKey: key)
    }

    mutating func encode(_ value: Int64, forKey key: Key) throws {
        try append(.int64(value), forKey: key)
    }

    @available(macOS 15.0, iOS 18.0, *)
    mutating func encode(_ value: Int128, forKey key: Key) throws {
        try append(.int128(value), forKey: key)
    }

    mutating func encode(_ value: UInt, forKey key: Key) throws {
        try append(try ModelNativeConvert.checkedUInt64(value, codingPath: codingPath + [key]), forKey: key)
    }

    mutating func encode(_ value: UInt8, forKey key: Key) throws {
        try append(.uint8(value), forKey: key)
    }

    mutating func encode(_ value: UInt16, forKey key: Key) throws {
        try append(.uint16(value), forKey: key)
    }

    mutating func encode(_ value: UInt32, forKey key: Key) throws {
        try append(.uint32(value), forKey: key)
    }

    mutating func encode(_ value: UInt64, forKey key: Key) throws {
        try append(.uint64(value), forKey: key)
    }

    @available(macOS 15.0, iOS 18.0, *)
    mutating func encode(_ value: UInt128, forKey key: Key) throws {
        try append(.uint128(value), forKey: key)
    }

    mutating func encode<T: Encodable>(_ value: T, forKey key: Key) throws {
        let path = codingPath + [key]

        if let optional = value as? any ModelOptionalEncodable {
            if optional.isNil {
                try append(.null, forKey: key)
                return
            }
            if let wrapped = optional.wrappedEncodable {
                try encode(wrapped, forKey: key)
                return
            }
        }

        if value is any ModelListEncodable {
            throw unsupported(
                value,
                path: path,
                reason: "STRUCT members do not support Array or unkeyed values"
            )
        }

        if let native = try ModelNativeConvert.nativeValue(value, codingPath: path) {
            try append(native, forKey: key)
            return
        }

        let capture = ModelScalarEncoder(codingPath: path)
        try value.encode(to: capture)
        guard let captured = capture.capturedValue else {
            throw unsupported(
                value,
                path: path,
                reason: "STRUCT members must encode as one native scalar Value"
            )
        }
        try append(captured, forKey: key)
    }

    // These witnesses override Codable's default omission behavior only inside STRUCT capture.
    mutating func encodeIfPresent(_ value: Bool?, forKey key: Key) throws {
        try encodeOptional(value, forKey: key)
    }

    mutating func encodeIfPresent(_ value: String?, forKey key: Key) throws {
        try encodeOptional(value, forKey: key)
    }

    mutating func encodeIfPresent(_ value: Double?, forKey key: Key) throws {
        try encodeOptional(value, forKey: key)
    }

    mutating func encodeIfPresent(_ value: Float?, forKey key: Key) throws {
        try encodeOptional(value, forKey: key)
    }

    mutating func encodeIfPresent(_ value: Int?, forKey key: Key) throws {
        try encodeOptional(value, forKey: key)
    }

    mutating func encodeIfPresent(_ value: Int8?, forKey key: Key) throws {
        try encodeOptional(value, forKey: key)
    }

    mutating func encodeIfPresent(_ value: Int16?, forKey key: Key) throws {
        try encodeOptional(value, forKey: key)
    }

    mutating func encodeIfPresent(_ value: Int32?, forKey key: Key) throws {
        try encodeOptional(value, forKey: key)
    }

    mutating func encodeIfPresent(_ value: Int64?, forKey key: Key) throws {
        try encodeOptional(value, forKey: key)
    }

    @available(macOS 15.0, iOS 18.0, *)
    mutating func encodeIfPresent(_ value: Int128?, forKey key: Key) throws {
        try encodeOptional(value, forKey: key)
    }

    mutating func encodeIfPresent(_ value: UInt?, forKey key: Key) throws {
        try encodeOptional(value, forKey: key)
    }

    mutating func encodeIfPresent(_ value: UInt8?, forKey key: Key) throws {
        try encodeOptional(value, forKey: key)
    }

    mutating func encodeIfPresent(_ value: UInt16?, forKey key: Key) throws {
        try encodeOptional(value, forKey: key)
    }

    mutating func encodeIfPresent(_ value: UInt32?, forKey key: Key) throws {
        try encodeOptional(value, forKey: key)
    }

    mutating func encodeIfPresent(_ value: UInt64?, forKey key: Key) throws {
        try encodeOptional(value, forKey: key)
    }

    @available(macOS 15.0, iOS 18.0, *)
    mutating func encodeIfPresent(_ value: UInt128?, forKey key: Key) throws {
        try encodeOptional(value, forKey: key)
    }

    mutating func encodeIfPresent<T: Encodable>(_ value: T?, forKey key: Key) throws {
        try encodeOptional(value, forKey: key)
    }

    mutating func encodeConditional<T: AnyObject & Encodable>(_ object: T, forKey key: Key) throws {
        throw unsupported(
            object,
            path: codingPath + [key],
            reason: "STRUCT members do not support conditional reference encoding"
        )
    }

    func nestedContainer<NestedKey: CodingKey>(
        keyedBy type: NestedKey.Type,
        forKey key: Key
    ) -> KeyedEncodingContainer<NestedKey> {
        KeyedEncodingContainer(
            RejectingKeyedEncodingContainer<NestedKey>(
                codingPath: codingPath + [key],
                reason: "STRUCT members do not support nested keyed containers"
            )
        )
    }

    mutating func nestedUnkeyedContainer(forKey key: Key) -> UnkeyedEncodingContainer {
        RejectingUnkeyedEncodingContainer(
            codingPath: codingPath + [key],
            reason: "STRUCT members do not support nested unkeyed containers"
        )
    }

    mutating func superEncoder() -> Encoder {
        RejectingEncoder(
            codingPath: codingPath,
            reason: "STRUCT encoding does not support superEncoder class-inheritance paths"
        )
    }

    mutating func superEncoder(forKey key: Key) -> Encoder {
        RejectingEncoder(
            codingPath: codingPath + [key],
            reason: "STRUCT encoding does not support superEncoder(forKey:)"
        )
    }

    private mutating func encodeOptional<T: Encodable>(_ value: T?, forKey key: Key) throws {
        guard let value else {
            try append(.null, forKey: key)
            return
        }
        try encode(value, forKey: key)
    }

    private func append(_ value: Value, forKey key: Key) throws {
        try storage.append(
            name: key.stringValue,
            value: value,
            codingPath: codingPath + [key]
        )
        encoder.updateStructureCapture(storage.members)
    }

    private func unsupported(
        _ value: Any,
        path: [CodingKey],
        reason: String
    ) -> EncodingError {
        EncodingError.invalidValue(
            value,
            EncodingError.Context(codingPath: path, debugDescription: reason)
        )
    }
}

// MARK: - Scalar fallback encoder

/// Captures a scalar-backed `Encodable` payload (raw-value enums, etc.) as an
/// exact native `Value` using the same conversion rules as keyed encoding.
///
/// Reference type so the single-value container mutates shared capture state.
final class ModelScalarEncoder: Encoder {
    let codingPath: [CodingKey]
    private(set) var capturedValue: Value?
    private let allowsStructuredCapture: Bool
    private var structureStorage: ModelStructEncodingStorage?
    var userInfo: [CodingUserInfoKey: Any] { [:] }

    init(codingPath: [CodingKey], allowsStructuredCapture: Bool = false) {
        self.codingPath = codingPath
        self.allowsStructuredCapture = allowsStructuredCapture
    }

    func container<Key: CodingKey>(
        keyedBy type: Key.Type
    ) -> KeyedEncodingContainer<Key> {
        guard allowsStructuredCapture else {
            return KeyedEncodingContainer(
                RejectingKeyedEncodingContainer<Key>(
                    codingPath: codingPath,
                    reason: "Scalar model encoding does not support keyed containers"
                )
            )
        }

        if capturedValue != nil, structureStorage == nil {
            return KeyedEncodingContainer(
                RejectingKeyedEncodingContainer<Key>(
                    codingPath: codingPath,
                    reason: "Scalar model encoding cannot capture both a scalar and a keyed STRUCT"
                )
            )
        }

        let storage: ModelStructEncodingStorage
        if let existing = structureStorage {
            storage = existing
        } else {
            let created = ModelStructEncodingStorage()
            structureStorage = created
            capturedValue = .structure([])
            storage = created
        }
        return KeyedEncodingContainer(
            ModelStructEncodingContainer(storage: storage, encoder: self, codingPath: codingPath)
        )
    }

    func unkeyedContainer() -> UnkeyedEncodingContainer {
        RejectingUnkeyedEncodingContainer(
            codingPath: codingPath,
            reason: "Scalar model encoding does not support unkeyed containers"
        )
    }

    func singleValueContainer() -> SingleValueEncodingContainer {
        ModelSingleValueEncodingContainer(encoder: self, codingPath: codingPath)
    }

    func capture(_ value: Value) throws {
        guard capturedValue == nil else {
            throw EncodingError.invalidValue(
                value,
                EncodingError.Context(
                    codingPath: codingPath,
                    debugDescription: "Scalar model encoding captured more than one value"
                )
            )
        }
        capturedValue = value
    }

    fileprivate func updateStructureCapture(_ members: [Value.StructMember]) {
        capturedValue = .structure(members)
    }
}

struct ModelSingleValueEncodingContainer: SingleValueEncodingContainer {
    var encoder: ModelScalarEncoder
    var codingPath: [CodingKey]

    mutating func encodeNil() throws {
        try encoder.capture(.null)
    }

    mutating func encode(_ value: Bool) throws {
        try encoder.capture(.boolean(value))
    }

    mutating func encode(_ value: String) throws {
        try encoder.capture(.string(value))
    }

    mutating func encode(_ value: Double) throws {
        try encoder.capture(.double(value))
    }

    mutating func encode(_ value: Float) throws {
        try encoder.capture(.float(value))
    }

    mutating func encode(_ value: Int) throws {
        try encoder.capture(try ModelNativeConvert.checkedInt64(value, codingPath: codingPath))
    }

    mutating func encode(_ value: Int8) throws {
        try encoder.capture(.int8(value))
    }

    mutating func encode(_ value: Int16) throws {
        try encoder.capture(.int16(value))
    }

    mutating func encode(_ value: Int32) throws {
        try encoder.capture(.int32(value))
    }

    mutating func encode(_ value: Int64) throws {
        try encoder.capture(.int64(value))
    }

    mutating func encode(_ value: UInt) throws {
        try encoder.capture(try ModelNativeConvert.checkedUInt64(value, codingPath: codingPath))
    }

    mutating func encode(_ value: UInt8) throws {
        try encoder.capture(.uint8(value))
    }

    mutating func encode(_ value: UInt16) throws {
        try encoder.capture(.uint16(value))
    }

    mutating func encode(_ value: UInt32) throws {
        try encoder.capture(.uint32(value))
    }

    mutating func encode(_ value: UInt64) throws {
        try encoder.capture(.uint64(value))
    }

    @available(macOS 15.0, iOS 18.0, *)
    mutating func encode(_ value: Int128) throws {
        try encoder.capture(.int128(value))
    }

    @available(macOS 15.0, iOS 18.0, *)
    mutating func encode(_ value: UInt128) throws {
        try encoder.capture(.uint128(value))
    }

    mutating func encode<T: Encodable>(_ value: T) throws {
        let path = codingPath
        if let optional = value as? any ModelOptionalEncodable {
            if optional.isNil {
                try encoder.capture(.null)
                return
            }
            if let wrapped = optional.wrappedEncodable {
                try encode(wrapped)
                return
            }
        }
        // Table persistence encodes each @Column through a single-value container, so an
        // Array-valued column arrives here rather than through the keyed path.
        if let list = value as? any ModelListEncodable {
            let children = try list.encodeModelListElements(codingPath: path)
            try encoder.capture(.list(children))
            return
        }

        if let native = try ModelNativeConvert.nativeValue(value, codingPath: path) {
            try encoder.capture(native)
            return
        }

        let nested = ModelScalarEncoder(codingPath: path, allowsStructuredCapture: true)
        try value.encode(to: nested)

        guard let captured = nested.capturedValue else {
            throw EncodingError.invalidValue(
                value,
                EncodingError.Context(
                    codingPath: path,
                    debugDescription:
                        "Flat model scalar encoding cannot represent \(T.self) as a native Value"
                )
            )
        }

        try encoder.capture(captured)
    }
}

// MARK: - Rejecting containers

struct RejectingKeyedEncodingContainer<Key: CodingKey>: KeyedEncodingContainerProtocol {
    var codingPath: [CodingKey]
    let reason: String

    private func fail<T>(_ value: T, extraPath: [CodingKey] = []) throws {
        throw EncodingError.invalidValue(
            value,
            EncodingError.Context(
                codingPath: codingPath + extraPath,
                debugDescription: reason
            )
        )
    }

    mutating func encodeNil(forKey key: Key) throws {
        try fail(Optional<Any>.none as Any, extraPath: [key])
    }

    mutating func encode(_ value: Bool, forKey key: Key) throws {
        try fail(value, extraPath: [key])
    }

    mutating func encode(_ value: String, forKey key: Key) throws {
        try fail(value, extraPath: [key])
    }

    mutating func encode(_ value: Double, forKey key: Key) throws {
        try fail(value, extraPath: [key])
    }

    mutating func encode(_ value: Float, forKey key: Key) throws {
        try fail(value, extraPath: [key])
    }

    mutating func encode(_ value: Int, forKey key: Key) throws {
        try fail(value, extraPath: [key])
    }

    mutating func encode(_ value: Int8, forKey key: Key) throws {
        try fail(value, extraPath: [key])
    }

    mutating func encode(_ value: Int16, forKey key: Key) throws {
        try fail(value, extraPath: [key])
    }

    mutating func encode(_ value: Int32, forKey key: Key) throws {
        try fail(value, extraPath: [key])
    }

    mutating func encode(_ value: Int64, forKey key: Key) throws {
        try fail(value, extraPath: [key])
    }

    mutating func encode(_ value: UInt, forKey key: Key) throws {
        try fail(value, extraPath: [key])
    }

    mutating func encode(_ value: UInt8, forKey key: Key) throws {
        try fail(value, extraPath: [key])
    }

    mutating func encode(_ value: UInt16, forKey key: Key) throws {
        try fail(value, extraPath: [key])
    }

    mutating func encode(_ value: UInt32, forKey key: Key) throws {
        try fail(value, extraPath: [key])
    }

    mutating func encode(_ value: UInt64, forKey key: Key) throws {
        try fail(value, extraPath: [key])
    }

    @available(macOS 15.0, iOS 18.0, *)
    mutating func encode(_ value: Int128, forKey key: Key) throws {
        try fail(value, extraPath: [key])
    }

    @available(macOS 15.0, iOS 18.0, *)
    mutating func encode(_ value: UInt128, forKey key: Key) throws {
        try fail(value, extraPath: [key])
    }

    mutating func encode<T: Encodable>(_ value: T, forKey key: Key) throws {
        try fail(value, extraPath: [key])
    }

    func nestedContainer<NestedKey: CodingKey>(
        keyedBy type: NestedKey.Type,
        forKey key: Key
    ) -> KeyedEncodingContainer<NestedKey> {
        KeyedEncodingContainer(
            RejectingKeyedEncodingContainer<NestedKey>(
                codingPath: codingPath + [key],
                reason: reason
            )
        )
    }

    mutating func nestedUnkeyedContainer(forKey key: Key) -> UnkeyedEncodingContainer {
        RejectingUnkeyedEncodingContainer(
            codingPath: codingPath + [key],
            reason: reason
        )
    }

    mutating func superEncoder() -> Encoder {
        RejectingEncoder(codingPath: codingPath, reason: reason)
    }

    mutating func superEncoder(forKey key: Key) -> Encoder {
        RejectingEncoder(codingPath: codingPath + [key], reason: reason)
    }
}

struct RejectingUnkeyedEncodingContainer: UnkeyedEncodingContainer {
    var codingPath: [CodingKey]
    var count: Int { 0 }
    let reason: String

    private func fail<T>(_ value: T) throws {
        throw EncodingError.invalidValue(
            value,
            EncodingError.Context(codingPath: codingPath, debugDescription: reason)
        )
    }

    mutating func encodeNil() throws {
        try fail(Optional<Any>.none as Any)
    }

    mutating func encode(_ value: Bool) throws { try fail(value) }
    mutating func encode(_ value: String) throws { try fail(value) }
    mutating func encode(_ value: Double) throws { try fail(value) }
    mutating func encode(_ value: Float) throws { try fail(value) }
    mutating func encode(_ value: Int) throws { try fail(value) }
    mutating func encode(_ value: Int8) throws { try fail(value) }
    mutating func encode(_ value: Int16) throws { try fail(value) }
    mutating func encode(_ value: Int32) throws { try fail(value) }
    mutating func encode(_ value: Int64) throws { try fail(value) }
    mutating func encode(_ value: UInt) throws { try fail(value) }
    mutating func encode(_ value: UInt8) throws { try fail(value) }
    mutating func encode(_ value: UInt16) throws { try fail(value) }
    mutating func encode(_ value: UInt32) throws { try fail(value) }
    mutating func encode(_ value: UInt64) throws { try fail(value) }

    @available(macOS 15.0, iOS 18.0, *)
    mutating func encode(_ value: Int128) throws { try fail(value) }

    @available(macOS 15.0, iOS 18.0, *)
    mutating func encode(_ value: UInt128) throws { try fail(value) }

    mutating func encode<T: Encodable>(_ value: T) throws {
        try fail(value)
    }

    mutating func nestedContainer<NestedKey: CodingKey>(
        keyedBy type: NestedKey.Type
    ) -> KeyedEncodingContainer<NestedKey> {
        KeyedEncodingContainer(
            RejectingKeyedEncodingContainer<NestedKey>(codingPath: codingPath, reason: reason)
        )
    }

    mutating func nestedUnkeyedContainer() -> UnkeyedEncodingContainer {
        self
    }

    mutating func superEncoder() -> Encoder {
        RejectingEncoder(codingPath: codingPath, reason: reason)
    }
}

struct RejectingSingleValueEncodingContainer: SingleValueEncodingContainer {
    var codingPath: [CodingKey]
    let reason: String

    private func fail<T>(_ value: T) throws {
        throw EncodingError.invalidValue(
            value,
            EncodingError.Context(codingPath: codingPath, debugDescription: reason)
        )
    }

    mutating func encodeNil() throws {
        try fail(Optional<Any>.none as Any)
    }

    mutating func encode(_ value: Bool) throws { try fail(value) }
    mutating func encode(_ value: String) throws { try fail(value) }
    mutating func encode(_ value: Double) throws { try fail(value) }
    mutating func encode(_ value: Float) throws { try fail(value) }
    mutating func encode(_ value: Int) throws { try fail(value) }
    mutating func encode(_ value: Int8) throws { try fail(value) }
    mutating func encode(_ value: Int16) throws { try fail(value) }
    mutating func encode(_ value: Int32) throws { try fail(value) }
    mutating func encode(_ value: Int64) throws { try fail(value) }
    mutating func encode(_ value: UInt) throws { try fail(value) }
    mutating func encode(_ value: UInt8) throws { try fail(value) }
    mutating func encode(_ value: UInt16) throws { try fail(value) }
    mutating func encode(_ value: UInt32) throws { try fail(value) }
    mutating func encode(_ value: UInt64) throws { try fail(value) }

    @available(macOS 15.0, iOS 18.0, *)
    mutating func encode(_ value: Int128) throws { try fail(value) }

    @available(macOS 15.0, iOS 18.0, *)
    mutating func encode(_ value: UInt128) throws { try fail(value) }

    mutating func encode<T: Encodable>(_ value: T) throws {
        try fail(value)
    }
}

struct RejectingEncoder: Encoder {
    let codingPath: [CodingKey]
    let reason: String
    var userInfo: [CodingUserInfoKey: Any] { [:] }

    func container<Key: CodingKey>(
        keyedBy type: Key.Type
    ) -> KeyedEncodingContainer<Key> {
        KeyedEncodingContainer(
            RejectingKeyedEncodingContainer<Key>(codingPath: codingPath, reason: reason)
        )
    }

    func unkeyedContainer() -> UnkeyedEncodingContainer {
        RejectingUnkeyedEncodingContainer(codingPath: codingPath, reason: reason)
    }

    func singleValueContainer() -> SingleValueEncodingContainer {
        RejectingSingleValueEncodingContainer(codingPath: codingPath, reason: reason)
    }
}
