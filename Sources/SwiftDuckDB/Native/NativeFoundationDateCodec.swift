import Foundation

enum NativeFoundationDateCodec {
    private static let microsecondsPerSecond: Int64 = 1_000_000
    private static let unixSecondsAtFoundationReference: Int64 = 978_307_200
    private static let positiveInfinityRaw = Int64.max
    private static let negativeInfinityRaw = -Int64.max

    static func rawMicroseconds(from dateValue: Date) throws -> Int64 {
        let raw = try rawMicrosecondsCore(from: dateValue)
        guard try date(fromRawMicrosecondsCore: raw) == dateValue else {
            throw failure("Foundation.Date is not an exact TIMESTAMPTZ microsecond instant.")
        }
        return raw
    }

    static func date(fromRawMicroseconds raw: Int64) throws -> Date {
        let date = try date(fromRawMicrosecondsCore: raw)
        guard try rawMicrosecondsCore(from: date) == raw else {
            throw failure("DuckDB TIMESTAMPTZ raw value is not exactly representable as Foundation.Date.")
        }
        return date
    }

    private static func date(fromRawMicrosecondsCore raw: Int64) throws -> Date {
        guard raw != positiveInfinityRaw, raw != negativeInfinityRaw else {
            throw failure("DuckDB TIMESTAMPTZ infinity is not representable as Foundation.Date.")
        }

        let parts = raw.quotientAndRemainder(dividingBy: microsecondsPerSecond)
        let shifted = parts.quotient.addingReportingOverflow(-unixSecondsAtFoundationReference)
        guard !shifted.overflow else {
            throw failure("DuckDB TIMESTAMPTZ raw value overflowed the Foundation reference-second shift.")
        }

        return Date(
            timeIntervalSinceReferenceDate:
                Double(shifted.partialValue) +
                Double(parts.remainder) / Double(microsecondsPerSecond)
        )
    }

    private static func rawMicrosecondsCore(from dateValue: Date) throws -> Int64 {
        let interval = dateValue.timeIntervalSinceReferenceDate
        guard interval.isFinite else {
            throw failure("Foundation.Date has a non-finite time interval.")
        }

        let secondsDouble = interval.rounded(.towardZero)
        guard var referenceSeconds = Int64(exactly: secondsDouble) else {
            throw failure("Foundation.Date seconds do not fit in the exact TIMESTAMPTZ domain.")
        }

        var remainderDouble = ((interval - secondsDouble) * Double(microsecondsPerSecond))
            .rounded(.toNearestOrAwayFromZero)

        if remainderDouble >= Double(microsecondsPerSecond) {
            let adjusted = referenceSeconds.addingReportingOverflow(1)
            guard !adjusted.overflow else {
                throw failure("Foundation.Date second adjustment overflowed.")
            }
            referenceSeconds = adjusted.partialValue
            remainderDouble -= Double(microsecondsPerSecond)
        } else if remainderDouble <= -Double(microsecondsPerSecond) {
            let adjusted = referenceSeconds.addingReportingOverflow(-1)
            guard !adjusted.overflow else {
                throw failure("Foundation.Date second adjustment underflowed.")
            }
            referenceSeconds = adjusted.partialValue
            remainderDouble += Double(microsecondsPerSecond)
        }

        guard let remainder = Int64(exactly: remainderDouble) else {
            throw failure("Foundation.Date is not an exact TIMESTAMPTZ microsecond instant.")
        }

        let unixSeconds = referenceSeconds.addingReportingOverflow(unixSecondsAtFoundationReference)
        guard !unixSeconds.overflow else {
            throw failure("Foundation.Date seconds overflowed the TIMESTAMPTZ domain.")
        }
        let multiplied = unixSeconds.partialValue.multipliedReportingOverflow(by: microsecondsPerSecond)
        guard !multiplied.overflow else {
            throw failure("Foundation.Date seconds overflowed TIMESTAMPTZ microseconds.")
        }
        let result = multiplied.partialValue.addingReportingOverflow(remainder)
        guard !result.overflow else {
            throw failure("Foundation.Date microseconds overflowed the TIMESTAMPTZ domain.")
        }

        let raw = result.partialValue
        guard raw != positiveInfinityRaw, raw != negativeInfinityRaw else {
            throw failure("Foundation.Date maps to a DuckDB TIMESTAMPTZ infinity.")
        }
        guard try date(fromRawMicrosecondsCore: raw) == dateValue else {
            throw failure("Foundation.Date is not an exact TIMESTAMPTZ microsecond instant.")
        }
        return raw
    }

    private static func failure(_ message: String) -> NativeTemporalConversionError {
        NativeTemporalConversionError(message: message)
    }
}
