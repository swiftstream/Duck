import Foundation
import SwifQL

public struct Row: Sendable, Equatable {
    public let columns: [String]
    public let values: [Value]

    init(columns: [String], values: [Value]) {
        self.columns = columns
        self.values = values
    }

    public subscript(_ index: Int) -> Value {
        values[index]
    }

    public subscript(_ column: String) -> Value? {
        guard let index = columns.firstIndex(of: column), values.indices.contains(index) else {
            return nil
        }

        return values[index]
    }

    /// Exact typed extraction by column name.
    ///
    /// Returns `nil` for a missing named column, SQL `NULL`, or a wrong
    /// requested type. There is no numeric coercion.
    public func value(_ column: String, as type: Bool.Type) -> Bool? {
        self[column]?.get(type)
    }

    public func value(_ column: String, as type: Int8.Type) -> Int8? {
        self[column]?.get(type)
    }

    public func value(_ column: String, as type: Int16.Type) -> Int16? {
        self[column]?.get(type)
    }

    public func value(_ column: String, as type: Int32.Type) -> Int32? {
        self[column]?.get(type)
    }

    public func value(_ column: String, as type: Int64.Type) -> Int64? {
        self[column]?.get(type)
    }

    public func value(_ column: String, as type: UInt8.Type) -> UInt8? {
        self[column]?.get(type)
    }

    public func value(_ column: String, as type: UInt16.Type) -> UInt16? {
        self[column]?.get(type)
    }

    public func value(_ column: String, as type: UInt32.Type) -> UInt32? {
        self[column]?.get(type)
    }

    public func value(_ column: String, as type: UInt64.Type) -> UInt64? {
        self[column]?.get(type)
    }

    public func value(_ column: String, as type: Float.Type) -> Float? {
        self[column]?.get(type)
    }

    public func value(_ column: String, as type: Double.Type) -> Double? {
        self[column]?.get(type)
    }

    public func value(_ column: String, as type: String.Type) -> String? {
        self[column]?.get(type)
    }

    public func value(_ column: String, as type: Data.Type) -> Data? {
        self[column]?.get(type)
    }

    public func value(_ column: String, as type: UUID.Type) -> UUID? {
        self[column]?.get(type)
    }

    public func value(_ column: String, as type: PureDate.Type) -> PureDate? {
        self[column]?.get(type)
    }

    public func value(_ column: String, as type: PureTime.Type) -> PureTime? {
        self[column]?.get(type)
    }

    public func value(_ column: String, as type: DateTime.Type) -> DateTime? {
        self[column]?.get(type)
    }

    public func value(_ column: String, as type: Date.Type) -> Date? {
        self[column]?.get(type)
    }

    public func value(_ column: String, as type: Interval.Type) -> Interval? {
        self[column]?.get(type)
    }

    public func value(_ column: String, as type: Decimal.Type) -> Decimal? {
        self[column]?.get(type)
    }

    @available(macOS 15.0, iOS 18.0, *)
    public func value(_ column: String, as type: Int128.Type) -> Int128? {
        self[column]?.get(type)
    }

    @available(macOS 15.0, iOS 18.0, *)
    public func value(_ column: String, as type: UInt128.Type) -> UInt128? {
        self[column]?.get(type)
    }

    /// Exact typed extraction by position.
    ///
    /// Returns `nil` for an out-of-range index, SQL `NULL`, or a wrong
    /// requested type. Positional convenience bounds-checks before touching
    /// the raw trapping positional subscript.
    public func value(_ index: Int, as type: Bool.Type) -> Bool? {
        guard values.indices.contains(index) else {
            return nil
        }
        return values[index].get(type)
    }

    public func value(_ index: Int, as type: Int8.Type) -> Int8? {
        guard values.indices.contains(index) else {
            return nil
        }
        return values[index].get(type)
    }

    public func value(_ index: Int, as type: Int16.Type) -> Int16? {
        guard values.indices.contains(index) else {
            return nil
        }
        return values[index].get(type)
    }

    public func value(_ index: Int, as type: Int32.Type) -> Int32? {
        guard values.indices.contains(index) else {
            return nil
        }
        return values[index].get(type)
    }

    public func value(_ index: Int, as type: Int64.Type) -> Int64? {
        guard values.indices.contains(index) else {
            return nil
        }
        return values[index].get(type)
    }

    public func value(_ index: Int, as type: UInt8.Type) -> UInt8? {
        guard values.indices.contains(index) else {
            return nil
        }
        return values[index].get(type)
    }

    public func value(_ index: Int, as type: UInt16.Type) -> UInt16? {
        guard values.indices.contains(index) else {
            return nil
        }
        return values[index].get(type)
    }

    public func value(_ index: Int, as type: UInt32.Type) -> UInt32? {
        guard values.indices.contains(index) else {
            return nil
        }
        return values[index].get(type)
    }

    public func value(_ index: Int, as type: UInt64.Type) -> UInt64? {
        guard values.indices.contains(index) else {
            return nil
        }
        return values[index].get(type)
    }

    public func value(_ index: Int, as type: Float.Type) -> Float? {
        guard values.indices.contains(index) else {
            return nil
        }
        return values[index].get(type)
    }

    public func value(_ index: Int, as type: Double.Type) -> Double? {
        guard values.indices.contains(index) else {
            return nil
        }
        return values[index].get(type)
    }

    public func value(_ index: Int, as type: String.Type) -> String? {
        guard values.indices.contains(index) else {
            return nil
        }
        return values[index].get(type)
    }

    public func value(_ index: Int, as type: Data.Type) -> Data? {
        guard values.indices.contains(index) else {
            return nil
        }
        return values[index].get(type)
    }

    public func value(_ index: Int, as type: UUID.Type) -> UUID? {
        guard values.indices.contains(index) else {
            return nil
        }
        return values[index].get(type)
    }

    public func value(_ index: Int, as type: PureDate.Type) -> PureDate? {
        guard values.indices.contains(index) else {
            return nil
        }
        return values[index].get(type)
    }

    public func value(_ index: Int, as type: PureTime.Type) -> PureTime? {
        guard values.indices.contains(index) else {
            return nil
        }
        return values[index].get(type)
    }

    public func value(_ index: Int, as type: DateTime.Type) -> DateTime? {
        guard values.indices.contains(index) else {
            return nil
        }
        return values[index].get(type)
    }

    public func value(_ index: Int, as type: Date.Type) -> Date? {
        guard values.indices.contains(index) else {
            return nil
        }
        return values[index].get(type)
    }

    public func value(_ index: Int, as type: Interval.Type) -> Interval? {
        guard values.indices.contains(index) else {
            return nil
        }
        return values[index].get(type)
    }

    public func value(_ index: Int, as type: Decimal.Type) -> Decimal? {
        guard values.indices.contains(index) else {
            return nil
        }
        return values[index].get(type)
    }

    @available(macOS 15.0, iOS 18.0, *)
    public func value(_ index: Int, as type: Int128.Type) -> Int128? {
        guard values.indices.contains(index) else {
            return nil
        }
        return values[index].get(type)
    }

    @available(macOS 15.0, iOS 18.0, *)
    public func value(_ index: Int, as type: UInt128.Type) -> UInt128? {
        guard values.indices.contains(index) else {
            return nil
        }
        return values[index].get(type)
    }

    public func string(_ column: String) -> String? {
        value(column, as: String.self)
    }

    public func int64(_ column: String) -> Int64? {
        value(column, as: Int64.self)
    }

    public func string(_ index: Int) -> String? {
        value(index, as: String.self)
    }

    public func int64(_ index: Int) -> Int64? {
        value(index, as: Int64.self)
    }

    public func pureDate(_ column: String) -> PureDate? {
        value(column, as: PureDate.self)
    }

    public func pureDate(_ index: Int) -> PureDate? {
        value(index, as: PureDate.self)
    }

    public func pureTime(_ column: String) -> PureTime? {
        value(column, as: PureTime.self)
    }

    public func pureTime(_ index: Int) -> PureTime? {
        value(index, as: PureTime.self)
    }

    public func dateTime(_ column: String) -> DateTime? {
        value(column, as: DateTime.self)
    }

    public func dateTime(_ index: Int) -> DateTime? {
        value(index, as: DateTime.self)
    }

    public func timestampTZ(_ column: String) -> Date? {
        value(column, as: Date.self)
    }

    public func timestampTZ(_ index: Int) -> Date? {
        value(index, as: Date.self)
    }

    public func interval(_ column: String) -> Interval? {
        value(column, as: Interval.self)
    }

    public func interval(_ index: Int) -> Interval? {
        value(index, as: Interval.self)
    }

    public func decimal(_ column: String) -> Decimal? {
        value(column, as: Decimal.self)
    }

    public func decimal(_ index: Int) -> Decimal? {
        value(index, as: Decimal.self)
    }
}
