import Cduckdb
import SwifQL

struct NativeTemporalConversionError: Error, Sendable, Equatable {
    let message: String
}

enum NativeTemporalCodec {
    static let finiteDateRawRange: ClosedRange<Int64> = -2_147_483_646...2_147_483_646
    static let dateNegativeInfinityRaw = -2_147_483_647
    static let datePositiveInfinityRaw = 2_147_483_647
    static let finiteDateMinimum = (year: Int64(-5_877_641), month: 6, day: 25)
    static let finiteDateMaximum = (year: Int64(5_881_580), month: 7, day: 10)

    private static let nanosecondsPerSecond: Int64 = 1_000_000_000
    private static let nanosecondsPerDay: Int64 = 86_400_000_000_000

    private struct TimestampDescriptor {
        let nanosecondsPerUnit: Int64
        let unitsPerDay: Int64
        let finiteRawRange: ClosedRange<Int64>
    }

    static func date(from pureDate: PureDate) throws -> duckdb_date {
        if pureDate == .positiveInfinity {
            return duckdb_date(days: Int32(datePositiveInfinityRaw))
        }
        if pureDate == .negativeInfinity {
            return duckdb_date(days: Int32(dateNegativeInfinityRaw))
        }

        guard let year = pureDate.year, let month = pureDate.month, let day = pureDate.day else {
            throw failure("Finite PureDate did not expose all civil components.")
        }

        guard isWithinFiniteCivilDomain(year: year, month: month, day: day) else {
            throw failure("PureDate is outside DuckDB's finite DATE civil domain.")
        }

        guard let year32 = Int32(exactly: year) else {
            throw failure("PureDate year does not fit in DuckDB's DATE year representation.")
        }

        let components = duckdb_date_struct(
            year: year32,
            month: Int8(month),
            day: Int8(day)
        )
        let raw = duckdb_to_date(components)
        guard finiteDateRawRange.contains(Int64(raw.days)) else {
            throw failure("DuckDB DATE conversion produced a non-finite raw value.")
        }
        guard raw.days != Int32(dateNegativeInfinityRaw), raw.days != Int32(datePositiveInfinityRaw) else {
            throw failure("DuckDB DATE conversion collided with an infinity sentinel.")
        }
        return raw
    }

    static func pureDate(from value: duckdb_date) throws -> PureDate {
        if value.days == Int32(datePositiveInfinityRaw) {
            return .positiveInfinity
        }
        if value.days == Int32(dateNegativeInfinityRaw) {
            return .negativeInfinity
        }

        guard finiteDateRawRange.contains(Int64(value.days)) else {
            throw failure("DuckDB DATE raw value is outside the finite domain.")
        }

        let components = duckdb_from_date(value)
        guard let result = PureDate(
            year: Int64(components.year),
            month: Int(components.month),
            day: Int(components.day)
        ) else {
            throw failure("DuckDB DATE raw value did not materialize as a valid PureDate.")
        }
        return result
    }

    static func time(from value: PureTime) throws -> duckdb_time {
        let nanos = value.nanosecondsSinceMidnight
        guard (0...nanosecondsPerDay).contains(nanos) else {
            throw failure("PureTime is outside the shared finite time-of-day domain.")
        }
        let microsecondParts = nanos.quotientAndRemainder(dividingBy: 1_000)
        guard microsecondParts.remainder == 0 else {
            throw failure("PureTime cannot be represented exactly by DuckDB TIME microseconds.")
        }
        let micros = microsecondParts.quotient
        guard micros >= 0, micros <= 86_400_000_000 else {
            throw failure("PureTime microseconds are outside DuckDB TIME's finite domain.")
        }
        return duckdb_time(micros: micros)
    }

    static func pureTime(from value: duckdb_time) throws -> PureTime {
        guard value.micros >= 0, value.micros <= 86_400_000_000 else {
            throw failure("DuckDB TIME raw value is outside the shared finite domain.")
        }
        let (nanos, overflow) = value.micros.multipliedReportingOverflow(by: 1_000)
        guard !overflow, let result = PureTime(nanosecondsSinceMidnight: nanos) else {
            throw failure("DuckDB TIME raw value could not be materialized exactly.")
        }
        return result
    }

    static func timeNS(from value: PureTime) throws -> duckdb_time_ns {
        let nanos = value.nanosecondsSinceMidnight
        guard (0...nanosecondsPerDay).contains(nanos) else {
            throw failure("PureTime is outside DuckDB TIME_NS's finite domain.")
        }
        return duckdb_time_ns(nanos: nanos)
    }

    static func pureTime(from value: duckdb_time_ns) throws -> PureTime {
        guard (0...nanosecondsPerDay).contains(value.nanos),
              let result = PureTime(nanosecondsSinceMidnight: value.nanos) else {
            throw failure("DuckDB TIME_NS raw value is outside the shared finite domain.")
        }
        return result
    }

    static func timestampRaw(from value: DateTime, target: LogicalTypeID) throws -> Int64 {
        let descriptor = try timestampDescriptor(for: target)
        if value == .positiveInfinity {
            return Int64.max
        }
        if value == .negativeInfinity {
            return -Int64.max
        }

        guard let date = value.date, let time = value.time, date.isFinite else {
            throw failure("Finite DateTime did not expose finite date and time components.")
        }
        guard time.nanosecondsSinceMidnight < nanosecondsPerDay else {
            throw failure("Finite DateTime cannot contain standalone PureTime.endOfDay.")
        }

        let dateRaw = try Self.date(from: date)
        guard finiteDateRawRange.contains(Int64(dateRaw.days)) else {
            throw failure("DateTime date is outside DuckDB's finite DATE domain.")
        }
        let nanos = time.nanosecondsSinceMidnight
        let timestampParts = nanos.quotientAndRemainder(dividingBy: descriptor.nanosecondsPerUnit)
        guard timestampParts.remainder == 0 else {
            throw failure("DateTime cannot be represented exactly at the requested timestamp precision.")
        }
        let unitsWithinDay = timestampParts.quotient
        let (dayUnits, dayOverflow) = Int64(dateRaw.days).multipliedReportingOverflow(by: descriptor.unitsPerDay)
        guard !dayOverflow else {
            throw failure("DateTime timestamp conversion overflowed its day coordinate.")
        }
        let (raw, additionOverflow) = dayUnits.addingReportingOverflow(unitsWithinDay)
        guard !additionOverflow, descriptor.finiteRawRange.contains(raw), raw != Int64.max, raw != -Int64.max else {
            throw failure("DateTime is outside the requested DuckDB timestamp domain.")
        }
        return raw
    }

    static func dateTime(fromRaw raw: Int64, source: LogicalTypeID) throws -> DateTime {
        let descriptor = try timestampDescriptor(for: source)
        if raw == Int64.max {
            return .positiveInfinity
        }
        if raw == -Int64.max {
            return .negativeInfinity
        }
        guard descriptor.finiteRawRange.contains(raw) else {
            throw failure("DuckDB timestamp raw value is outside its finite domain.")
        }

        let rawParts = raw.quotientAndRemainder(dividingBy: descriptor.unitsPerDay)
        let q0 = rawParts.quotient
        let r0 = rawParts.remainder
        let day: Int64
        let remainder: Int64
        if r0 < 0 {
            day = q0 - 1
            remainder = r0 + descriptor.unitsPerDay
        } else {
            day = q0
            remainder = r0
        }

        guard let day32 = Int32(exactly: day) else {
            throw failure("DuckDB timestamp day coordinate does not fit in DATE.")
        }
        let date = try pureDate(from: duckdb_date(days: day32))
        guard date.isFinite else {
            throw failure("Finite DuckDB timestamp decoded to a DATE infinity.")
        }
        let (nanos, overflow) = remainder.multipliedReportingOverflow(by: descriptor.nanosecondsPerUnit)
        guard !overflow, (0..<nanosecondsPerDay).contains(nanos),
              let time = PureTime(nanosecondsSinceMidnight: nanos),
              let result = DateTime(date: date, time: time) else {
            throw failure("DuckDB timestamp raw value did not materialize as a valid finite DateTime.")
        }
        return result
    }

    private static func timestampDescriptor(for target: LogicalTypeID) throws -> TimestampDescriptor {
        switch target {
        case .timestampS:
            return TimestampDescriptor(
                nanosecondsPerUnit: nanosecondsPerSecond,
                unitsPerDay: 86_400,
                finiteRawRange: -9_223_372_022_400...9_223_372_036_854
            )
        case .timestampMS:
            return TimestampDescriptor(
                nanosecondsPerUnit: 1_000_000,
                unitsPerDay: 86_400_000,
                finiteRawRange: -9_223_372_022_400_000...9_223_372_036_854_775
            )
        case .timestamp:
            return TimestampDescriptor(
                nanosecondsPerUnit: 1_000,
                unitsPerDay: 86_400_000_000,
                finiteRawRange: -9_223_372_022_400_000_000...9_223_372_036_854_775_806
            )
        case .timestampNS:
            return TimestampDescriptor(
                nanosecondsPerUnit: 1,
                unitsPerDay: 86_400_000_000_000,
                finiteRawRange: -9_223_286_400_000_000_000...9_223_372_036_854_775_806
            )
        default:
            throw failure("Logical type (target.rawValue) is not a B2 timestamp precision.")
        }
    }

    private static func isWithinFiniteCivilDomain(year: Int64, month: Int, day: Int) -> Bool {
        if year < finiteDateMinimum.year {
            return false
        }
        if year == finiteDateMinimum.year {
            if month < finiteDateMinimum.month {
                return false
            }
            if month == finiteDateMinimum.month, day < finiteDateMinimum.day {
                return false
            }
        }
        if year > finiteDateMaximum.year {
            return false
        }
        if year == finiteDateMaximum.year {
            if month > finiteDateMaximum.month {
                return false
            }
            if month == finiteDateMaximum.month, day > finiteDateMaximum.day {
                return false
            }
        }
        return true
    }

    private static func failure(_ message: String) -> NativeTemporalConversionError {
        NativeTemporalConversionError(message: message)
    }
}
