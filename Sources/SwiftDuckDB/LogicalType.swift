/// The open numeric identity of a DuckDB logical type.
public struct LogicalTypeID: RawRepresentable, Sendable, Hashable, Equatable {
    public let rawValue: UInt32

    public init(rawValue: UInt32) {
        self.rawValue = rawValue
    }

    public static let invalid = Self(rawValue: 0)
    public static let boolean = Self(rawValue: 1)
    public static let tinyint = Self(rawValue: 2)
    public static let smallint = Self(rawValue: 3)
    public static let integer = Self(rawValue: 4)
    public static let bigint = Self(rawValue: 5)
    public static let utinyint = Self(rawValue: 6)
    public static let usmallint = Self(rawValue: 7)
    public static let uinteger = Self(rawValue: 8)
    public static let ubigint = Self(rawValue: 9)
    public static let float = Self(rawValue: 10)
    public static let double = Self(rawValue: 11)
    public static let timestamp = Self(rawValue: 12)
    public static let date = Self(rawValue: 13)
    public static let time = Self(rawValue: 14)
    public static let interval = Self(rawValue: 15)
    public static let hugeint = Self(rawValue: 16)
    public static let varchar = Self(rawValue: 17)
    public static let blob = Self(rawValue: 18)
    public static let decimal = Self(rawValue: 19)
    public static let timestampS = Self(rawValue: 20)
    public static let timestampMS = Self(rawValue: 21)
    public static let timestampNS = Self(rawValue: 22)
    public static let enumeration = Self(rawValue: 23)
    public static let list = Self(rawValue: 24)
    public static let structType = Self(rawValue: 25)
    public static let map = Self(rawValue: 26)
    public static let uuid = Self(rawValue: 27)
    public static let union = Self(rawValue: 28)
    public static let bit = Self(rawValue: 29)
    public static let timeTZ = Self(rawValue: 30)
    public static let timestampTZ = Self(rawValue: 31)
    public static let uhugeint = Self(rawValue: 32)
    public static let array = Self(rawValue: 33)
    public static let any = Self(rawValue: 34)
    public static let bignum = Self(rawValue: 35)
    public static let sqlNull = Self(rawValue: 36)
    public static let stringLiteral = Self(rawValue: 37)
    public static let integerLiteral = Self(rawValue: 38)
    public static let timeNS = Self(rawValue: 39)
    public static let geometry = Self(rawValue: 40)
    public static let variant = Self(rawValue: 41)
}

struct LogicalTypeMember: Sendable, Equatable {
    let name: String
    let type: LogicalType
}

indirect enum LogicalTypeDetail: Sendable, Equatable {
    case none
    case decimal(width: UInt8, scale: UInt8)
    case enumeration(values: [String])
    case list(child: LogicalType)
    case array(child: LogicalType, length: Int)
    case map(key: LogicalType, value: LogicalType)
    case structure(members: [LogicalTypeMember])
    case union(members: [LogicalTypeMember])
}

public struct LogicalType: Sendable, Equatable {
    public let id: LogicalTypeID
    public let alias: String?

    let detail: LogicalTypeDetail

    public init(id: LogicalTypeID, alias: String? = nil) {
        self.init(id: id, alias: alias, detail: .none)
    }

    init(id: LogicalTypeID, alias: String?, detail: LogicalTypeDetail) {
        self.id = id
        self.alias = alias
        self.detail = detail
    }

    public var decimalWidth: UInt8? {
        guard case .decimal(let width, _) = detail else {
            return nil
        }
        return width
    }

    public var decimalScale: UInt8? {
        guard case .decimal(_, let scale) = detail else {
            return nil
        }
        return scale
    }
}
