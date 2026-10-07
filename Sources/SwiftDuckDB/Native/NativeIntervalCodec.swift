import Cduckdb
import SQL

struct NativeIntervalConversionError: Error, Sendable, Equatable {
    let message: String
}

enum NativeIntervalCodec {
    static func native(from value: Interval) throws -> duckdb_interval {
        guard value.isFinite else {
            throw NativeIntervalConversionError(
                message: "Interval infinity is not representable as a DuckDB INTERVAL."
            )
        }
        guard let months = value.months,
              let days = value.days,
              let microseconds = value.microseconds else {
            throw NativeIntervalConversionError(
                message: "Finite Interval did not expose all physical components."
            )
        }
        guard let months = Int32(exactly: months) else {
            throw NativeIntervalConversionError(
                message: "Interval months do not fit in DuckDB's Int32 INTERVAL field."
            )
        }
        guard let days = Int32(exactly: days) else {
            throw NativeIntervalConversionError(
                message: "Interval days do not fit in DuckDB's Int32 INTERVAL field."
            )
        }
        return duckdb_interval(months: months, days: days, micros: microseconds)
    }

    static func interval(from value: duckdb_interval) -> Interval {
        Interval(
            months: Int64(value.months),
            days: Int64(value.days),
            microseconds: value.micros
        )
    }
}
