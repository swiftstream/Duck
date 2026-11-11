import Foundation
import SQL

/// The public Swift value facade for DuckDB scalar results and bindings.
///
/// `Value` is a non-generic value type. Its stored representation is the
/// internal exhaustive `Storage` enum, which keeps 128-bit integers as hidden
/// exact word pairs so the package still compiles at the macOS 12 / iOS 15
/// deployment floors. Direct Swift `Int128` / `UInt128` construction and
/// extraction are availability-gated stdlib bridges; `UUID` is an
/// availability-free distinct semantic case.
public struct Value: Sendable, Equatable {
    /// A named member of a native DuckDB STRUCT value.
    public struct StructMember: Sendable, Equatable {
        /// The exact, case-sensitive STRUCT member name.
        public let name: String

        /// The member's exact Duck value, including SQL NULL when appropriate.
        public let value: Value

        /// Creates a named STRUCT member while preserving its supplied name and value.
        public init(name: String, value: Value) {
            self.name = name
            self.value = value
        }
    }

    internal enum Storage: Sendable, Equatable {
        case null
        case boolean(Bool)
        case int8(Int8)
        case int16(Int16)
        case int32(Int32)
        case int64(Int64)
        case uint8(UInt8)
        case uint16(UInt16)
        case uint32(UInt32)
        case uint64(UInt64)
        case float(Float)
        case double(Double)
        case string(String)
        case blob(Data)
        case signed128Words(upper: Int64, lower: UInt64)
        case unsigned128Words(upper: UInt64, lower: UInt64)
        case uuid(UUID)
        case date(PureDate)
        case time(PureTime)
        case dateTime(DateTime)
        case timestampTZ(Date)
        case interval(Interval)
        case decimal(Decimal)
        case list([Value])
        case structure([StructMember])
    }

    internal let storage: Storage

    internal init(storage: Storage) {
        self.storage = storage
    }

    internal init(signedUpper upper: Int64, lower: UInt64) {
        self.storage = .signed128Words(upper: upper, lower: lower)
    }

    internal init(unsignedUpper upper: UInt64, lower: UInt64) {
        self.storage = .unsigned128Words(upper: upper, lower: lower)
    }

    /// Open forward-compatible value-kind identity.
    ///
    /// Raw IDs are Duck-owned `Value`-kind IDs, not DuckDB
    /// `LogicalTypeID` numbers. Future kinds append new IDs; published IDs are
    /// never renumbered.
    public struct Kind: RawRepresentable, Sendable, Hashable, Equatable {
        public let rawValue: UInt32

        public init(rawValue: UInt32) {
            self.rawValue = rawValue
        }

        public static let null = Self(rawValue: 0)
        public static let boolean = Self(rawValue: 1)
        public static let int8 = Self(rawValue: 2)
        public static let int16 = Self(rawValue: 3)
        public static let int32 = Self(rawValue: 4)
        public static let int64 = Self(rawValue: 5)
        public static let uint8 = Self(rawValue: 6)
        public static let uint16 = Self(rawValue: 7)
        public static let uint32 = Self(rawValue: 8)
        public static let uint64 = Self(rawValue: 9)
        public static let float = Self(rawValue: 10)
        public static let double = Self(rawValue: 11)
        public static let string = Self(rawValue: 12)
        public static let blob = Self(rawValue: 13)
        public static let int128 = Self(rawValue: 14)
        public static let uint128 = Self(rawValue: 15)
        public static let uuid = Self(rawValue: 16)
        public static let date = Self(rawValue: 17)
        public static let time = Self(rawValue: 18)
        public static let dateTime = Self(rawValue: 19)
        public static let timestampTZ = Self(rawValue: 20)
        public static let interval = Self(rawValue: 21)
        public static let decimal = Self(rawValue: 22)
        public static let list = Self(rawValue: 23)
        /// A keyed DuckDB STRUCT value.
        public static let structure = Self(rawValue: 24)

        public static let allKnown: [Self] = [
            .null,
            .boolean,
            .int8,
            .int16,
            .int32,
            .int64,
            .uint8,
            .uint16,
            .uint32,
            .uint64,
            .float,
            .double,
            .string,
            .blob,
            .int128,
            .uint128,
            .uuid,
            .date,
            .time,
            .dateTime,
            .timestampTZ,
            .interval,
            .decimal,
            .list,
            .structure,
        ]
    }

    public var kind: Kind {
        switch storage {
        case .null:
            return .null
        case .boolean:
            return .boolean
        case .int8:
            return .int8
        case .int16:
            return .int16
        case .int32:
            return .int32
        case .int64:
            return .int64
        case .uint8:
            return .uint8
        case .uint16:
            return .uint16
        case .uint32:
            return .uint32
        case .uint64:
            return .uint64
        case .float:
            return .float
        case .double:
            return .double
        case .string:
            return .string
        case .blob:
            return .blob
        case .signed128Words:
            return .int128
        case .unsigned128Words:
            return .uint128
        case .uuid:
            return .uuid
        case .date:
            return .date
        case .time:
            return .time
        case .dateTime:
            return .dateTime
        case .timestampTZ:
            return .timestampTZ
        case .interval:
            return .interval
        case .decimal:
            return .decimal
        case .list:
            return .list
        case .structure:
            return .structure
        }
    }

    public static let null = Value(storage: .null)

    public static func boolean(_ value: Bool) -> Value {
        Value(storage: .boolean(value))
    }

    public static func int8(_ value: Int8) -> Value {
        Value(storage: .int8(value))
    }

    public static func int16(_ value: Int16) -> Value {
        Value(storage: .int16(value))
    }

    public static func int32(_ value: Int32) -> Value {
        Value(storage: .int32(value))
    }

    public static func int64(_ value: Int64) -> Value {
        Value(storage: .int64(value))
    }

    public static func uint8(_ value: UInt8) -> Value {
        Value(storage: .uint8(value))
    }

    public static func uint16(_ value: UInt16) -> Value {
        Value(storage: .uint16(value))
    }

    public static func uint32(_ value: UInt32) -> Value {
        Value(storage: .uint32(value))
    }

    public static func uint64(_ value: UInt64) -> Value {
        Value(storage: .uint64(value))
    }

    public static func float(_ value: Float) -> Value {
        Value(storage: .float(value))
    }

    public static func double(_ value: Double) -> Value {
        Value(storage: .double(value))
    }

    public static func string(_ value: String) -> Value {
        Value(storage: .string(value))
    }

    public static func blob(_ value: Data) -> Value {
        Value(storage: .blob(value))
    }

    public static func uuid(_ value: UUID) -> Value {
        Value(storage: .uuid(value))
    }

    public static func date(_ value: PureDate) -> Value {
        Value(storage: .date(value))
    }

    public static func time(_ value: PureTime) -> Value {
        Value(storage: .time(value))
    }

    public static func dateTime(_ value: DateTime) -> Value {
        Value(storage: .dateTime(value))
    }

    public static func timestampTZ(_ value: Date) -> Value {
        Value(storage: .timestampTZ(value))
    }

    public static func interval(_ value: Interval) -> Value {
        Value(storage: .interval(value))
    }

    public static func decimal(_ value: Decimal) -> Value {
        Value(storage: .decimal(value))
    }

    /// A one-dimensional native DuckDB LIST.
    ///
    /// Child order is preserved and equality is exact. A SQL `NULL` child is
    /// `Value.null` inside the list; a SQL `NULL` list is `Value.null`.
    public static func list(_ values: [Value]) -> Value {
        Value(storage: .list(values))
    }

    /// Creates one keyed DuckDB STRUCT value with the supplied member order.
    ///
    /// Names and member values are preserved exactly; duplicate names remain representable here
    /// and are rejected when the value is converted to a native target.
    public static func structure(_ members: [StructMember]) -> Value {
        Value(storage: .structure(members))
    }

    @available(macOS 15.0, iOS 18.0, *)
    public static func int128(_ value: Int128) -> Value {
        let words = NativeScalarCodec.signedWords(from: value)
        return Value(storage: .signed128Words(upper: words.upper, lower: words.lower))
    }

    @available(macOS 15.0, iOS 18.0, *)
    public static func uint128(_ value: UInt128) -> Value {
        let words = NativeScalarCodec.unsignedWords(from: value)
        return Value(storage: .unsigned128Words(upper: words.upper, lower: words.lower))
    }

    /// Exact stored-type extraction.
    ///
    /// Returns the stored payload only when the requested metatype matches the
    /// stored family exactly. SQL `NULL`, a wrong requested type, and any
    /// cross-family conversion all produce `nil`. There is no widening,
    /// narrowing, signed/unsigned conversion, parsing, stringification, or
    /// lossy conversion.
    public func get(_ type: Bool.Type) -> Bool? {
        guard case .boolean(let value) = storage else {
            return nil
        }
        return value
    }

    public func get(_ type: Int8.Type) -> Int8? {
        guard case .int8(let value) = storage else {
            return nil
        }
        return value
    }

    public func get(_ type: Int16.Type) -> Int16? {
        guard case .int16(let value) = storage else {
            return nil
        }
        return value
    }

    public func get(_ type: Int32.Type) -> Int32? {
        guard case .int32(let value) = storage else {
            return nil
        }
        return value
    }

    public func get(_ type: Int64.Type) -> Int64? {
        guard case .int64(let value) = storage else {
            return nil
        }
        return value
    }

    public func get(_ type: UInt8.Type) -> UInt8? {
        guard case .uint8(let value) = storage else {
            return nil
        }
        return value
    }

    public func get(_ type: UInt16.Type) -> UInt16? {
        guard case .uint16(let value) = storage else {
            return nil
        }
        return value
    }

    public func get(_ type: UInt32.Type) -> UInt32? {
        guard case .uint32(let value) = storage else {
            return nil
        }
        return value
    }

    public func get(_ type: UInt64.Type) -> UInt64? {
        guard case .uint64(let value) = storage else {
            return nil
        }
        return value
    }

    public func get(_ type: Float.Type) -> Float? {
        guard case .float(let value) = storage else {
            return nil
        }
        return value
    }

    public func get(_ type: Double.Type) -> Double? {
        guard case .double(let value) = storage else {
            return nil
        }
        return value
    }

    public func get(_ type: String.Type) -> String? {
        guard case .string(let value) = storage else {
            return nil
        }
        return value
    }

    public func get(_ type: Data.Type) -> Data? {
        guard case .blob(let value) = storage else {
            return nil
        }
        return value
    }

    public func get(_ type: UUID.Type) -> UUID? {
        guard case .uuid(let value) = storage else {
            return nil
        }
        return value
    }

    public func get(_ type: PureDate.Type) -> PureDate? {
        guard case .date(let value) = storage else {
            return nil
        }
        return value
    }

    public func get(_ type: PureTime.Type) -> PureTime? {
        guard case .time(let value) = storage else {
            return nil
        }
        return value
    }

    public func get(_ type: DateTime.Type) -> DateTime? {
        guard case .dateTime(let value) = storage else {
            return nil
        }
        return value
    }

    public func get(_ type: Date.Type) -> Date? {
        guard case .timestampTZ(let value) = storage else {
            return nil
        }
        return value
    }

    public func get(_ type: Interval.Type) -> Interval? {
        guard case .interval(let value) = storage else {
            return nil
        }
        return value
    }

    public func get(_ type: Decimal.Type) -> Decimal? {
        guard case .decimal(let value) = storage else {
            return nil
        }
        return value
    }

    public func get(_ type: [Value].Type) -> [Value]? {
        guard case .list(let values) = storage else {
            return nil
        }
        return values
    }

    /// Returns the exact ordered members when this value is a STRUCT.
    public func get(_ type: [StructMember].Type) -> [StructMember]? {
        guard case .structure(let members) = storage else {
            return nil
        }
        return members
    }

    @available(macOS 15.0, iOS 18.0, *)
    public func get(_ type: Int128.Type) -> Int128? {
        guard case .signed128Words(let upper, let lower) = storage else {
            return nil
        }
        return NativeScalarCodec.int128(upper: upper, lower: lower)
    }

    @available(macOS 15.0, iOS 18.0, *)
    public func get(_ type: UInt128.Type) -> UInt128? {
        guard case .unsigned128Words(let upper, let lower) = storage else {
            return nil
        }
        return NativeScalarCodec.uint128(upper: upper, lower: lower)
    }

    public var isNull: Bool {
        storage == .null
    }

    public var stringValue: String? {
        self.get(String.self)
    }

    public var int64Value: Int64? {
        self.get(Int64.self)
    }

    public var uuidValue: UUID? {
        self.get(UUID.self)
    }

    public var pureDateValue: PureDate? {
        self.get(PureDate.self)
    }

    public var pureTimeValue: PureTime? {
        self.get(PureTime.self)
    }

    public var dateTimeValue: DateTime? {
        self.get(DateTime.self)
    }

    public var timestampTZValue: Date? {
        self.get(Date.self)
    }

    public var intervalValue: Interval? {
        self.get(Interval.self)
    }

    public var decimalValue: Decimal? {
        self.get(Decimal.self)
    }

    public var listValue: [Value]? {
        self.get([Value].self)
    }

    /// The exact ordered members when this value is a STRUCT.
    public var structureValue: [StructMember]? {
        self.get([StructMember].self)
    }

    @available(macOS 15.0, iOS 18.0, *)
    public var int128Value: Int128? {
        self.get(Int128.self)
    }

    @available(macOS 15.0, iOS 18.0, *)
    public var uint128Value: UInt128? {
        self.get(UInt128.self)
    }
}
