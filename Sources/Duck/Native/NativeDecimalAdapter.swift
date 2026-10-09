import Cduckdb
import Foundation

struct NativeDecimalTarget: Sendable, Equatable {
    let width: Int
    let scale: Int

    init(width: Int, scale: Int) throws {
        guard (1...38).contains(width), (0...width).contains(scale) else {
            throw DecimalExactError.invalidWidthScale
        }
        self.width = width
        self.scale = scale
    }
}

enum NativeDecimalAdapter {
    static func naturalTarget(for value: Decimal) throws -> NativeDecimalTarget {
        let parts = try DecimalExactCodec.foundationDecimalToCanonical(value)
        guard parts.digits != "0" else {
            return try NativeDecimalTarget(width: 1, scale: 0)
        }

        let scale: Int
        let coefficientDigitCount: Int
        if parts.exponent10 >= 0 {
            scale = 0
            let count = parts.digits.count.addingReportingOverflow(parts.exponent10)
            guard !count.overflow else {
                throw DecimalExactError.exponentOverflow
            }
            coefficientDigitCount = count.partialValue
        } else {
            let scaleResult = 0.subtractingReportingOverflow(parts.exponent10)
            guard !scaleResult.overflow else {
                throw DecimalExactError.exponentOverflow
            }
            scale = scaleResult.partialValue
            coefficientDigitCount = parts.digits.count
        }

        let target = try NativeDecimalTarget(
            width: max(scale, coefficientDigitCount),
            scale: scale
        )
        _ = try DecimalExactCodec.exactCoefficient(
            from: parts,
            width: target.width,
            scale: target.scale
        )
        return target
    }

    static func target(for descriptor: LogicalType) throws -> NativeDecimalTarget {
        guard descriptor.id == .decimal,
              let width = descriptor.decimalWidth,
              let scale = descriptor.decimalScale else {
            throw DecimalExactError.invalidWidthScale
        }
        return try NativeDecimalTarget(width: Int(width), scale: Int(scale))
    }

    static func nativeDecimal(
        _ value: Decimal,
        target: NativeDecimalTarget
    ) throws -> duckdb_decimal {
        let parts = try DecimalExactCodec.foundationDecimalToCanonical(value)
        let coefficient = try DecimalExactCodec.exactCoefficient(
            from: parts,
            width: target.width,
            scale: target.scale
        )
        let nativeValue = NativeScalarCodec.hugeint(
            upper: coefficient.words.upper,
            lower: coefficient.words.lower
        )
        return duckdb_decimal(
            width: UInt8(target.width),
            scale: UInt8(target.scale),
            value: nativeValue
        )
    }

    static func signedWords(of value: Int64) -> Signed128Words {
        Signed128Words(
            upper: value < 0 ? -1 : 0,
            lower: UInt64(bitPattern: value)
        )
    }

    static func foundationDecimal(
        from words: Signed128Words,
        target: NativeDecimalTarget
    ) throws -> Decimal {
        let value = try DecimalExactCodec.foundationDecimalFromCoefficientScale(
            signedWords: words,
            scale: target.scale
        )
        let parts = try DecimalExactCodec.foundationDecimalToCanonical(value)
        let coefficient = try DecimalExactCodec.exactCoefficient(
            from: parts,
            width: target.width,
            scale: target.scale
        )
        guard coefficient.words == words else {
            throw DecimalExactError.reconstructionMismatch
        }
        return value
    }

    static func message(for error: DecimalExactError) -> String {
        switch error {
        case .invalidWidthScale:
            return "Decimal target width or scale is invalid."
        case .nonfinite:
            return "Decimal value is nonfinite and cannot bind as SQL DECIMAL."
        case .malformedFoundationSpelling:
            return "Decimal value has no stable exact Foundation spelling."
        case .exponentOverflow:
            return "Decimal exponent exceeds the supported exact range."
        case .roundingRequired:
            return "Decimal binding would require rounding."
        case .widthOverflow:
            return "Decimal value does not fit the target width and scale."
        case .coefficientOverflow:
            return "Decimal coefficient exceeds the supported exact range."
        case .reconstructionMismatch:
            return "Decimal native coefficient reconstruction did not match."
        case .invalidCoefficient:
            return "Decimal native coefficient is invalid."
        }
    }

    static func bindingError(_ error: DecimalExactError, at index: Int) -> NativeDuckDBError {
        NativeDuckDBError(
            operation: .binding,
            message: message(for: error),
            parameterIndex: index
        )
    }

    static func invalidResultError(_ error: DecimalExactError) -> NativeDuckDBError {
        NativeDuckDBError(operation: .invalidResult, message: message(for: error))
    }
}
