import Foundation

enum DecimalExactError: Error, Equatable {
    case invalidWidthScale
    case nonfinite
    case malformedFoundationSpelling
    case exponentOverflow
    case roundingRequired
    case widthOverflow
    case coefficientOverflow
    case reconstructionMismatch
    case invalidCoefficient
}

struct CanonicalDecimalParts: Equatable {
    let isNegative: Bool
    let digits: String
    let exponent10: Int
}

struct Signed128Words: Equatable {
    let upper: Int64
    let lower: UInt64
}

struct ExactDecimalCoefficient: Equatable {
    let words: Signed128Words
    let scale: Int
}

enum DecimalExactCodec {
    private static let posixLocale = Locale(identifier: "en_US_POSIX")

    static func parseCanonicalDecimalText(_ text: String) throws -> CanonicalDecimalParts {
        let bytes = Array(text.utf8)
        guard !bytes.isEmpty else {
            throw DecimalExactError.malformedFoundationSpelling
        }

        var index = 0
        var isNegative = false
        if bytes[index] == 43 || bytes[index] == 45 {
            isNegative = bytes[index] == 45
            index += 1
        }

        var integerDigits: [UInt8] = []
        while index < bytes.count, Self.isASCIIDigit(bytes[index]) {
            integerDigits.append(bytes[index])
            index += 1
        }
        guard !integerDigits.isEmpty else {
            throw DecimalExactError.malformedFoundationSpelling
        }

        var fractionalDigits: [UInt8] = []
        if index < bytes.count, bytes[index] == 46 {
            index += 1
            while index < bytes.count, Self.isASCIIDigit(bytes[index]) {
                fractionalDigits.append(bytes[index])
                index += 1
            }
            guard !fractionalDigits.isEmpty else {
                throw DecimalExactError.malformedFoundationSpelling
            }
        }

        var explicitExponent = 0
        if index < bytes.count, bytes[index] == 101 || bytes[index] == 69 {
            index += 1
            var exponentIsNegative = false
            if index < bytes.count, bytes[index] == 43 || bytes[index] == 45 {
                exponentIsNegative = bytes[index] == 45
                index += 1
            }

            guard index < bytes.count, Self.isASCIIDigit(bytes[index]) else {
                throw DecimalExactError.malformedFoundationSpelling
            }

            var negativeAccumulator = 0
            while index < bytes.count, Self.isASCIIDigit(bytes[index]) {
                let digit = Int(bytes[index] - 48)
                let multiplied = negativeAccumulator.multipliedReportingOverflow(by: 10)
                guard !multiplied.overflow else {
                    throw DecimalExactError.exponentOverflow
                }
                let subtracted = multiplied.partialValue.subtractingReportingOverflow(digit)
                guard !subtracted.overflow else {
                    throw DecimalExactError.exponentOverflow
                }
                negativeAccumulator = subtracted.partialValue
                index += 1
            }

            if exponentIsNegative {
                explicitExponent = negativeAccumulator
            } else {
                let positive = negativeAccumulator.multipliedReportingOverflow(by: -1)
                guard !positive.overflow else {
                    throw DecimalExactError.exponentOverflow
                }
                explicitExponent = positive.partialValue
            }
        }

        guard index == bytes.count else {
            throw DecimalExactError.malformedFoundationSpelling
        }

        let fractionCount = fractionalDigits.count
        let exponentResult = explicitExponent.subtractingReportingOverflow(fractionCount)
        guard !exponentResult.overflow else {
            throw DecimalExactError.exponentOverflow
        }
        var exponent10 = exponentResult.partialValue

        var allDigits = integerDigits
        allDigits.append(contentsOf: fractionalDigits)
        var firstNonzero = 0
        while firstNonzero < allDigits.count, allDigits[firstNonzero] == 48 {
            firstNonzero += 1
        }

        if firstNonzero == allDigits.count {
            return CanonicalDecimalParts(isNegative: false, digits: "0", exponent10: 0)
        }

        var canonicalDigits = Array(allDigits[firstNonzero...])
        while canonicalDigits.count > 1, canonicalDigits.last == 48 {
            canonicalDigits.removeLast()
            let incremented = exponent10.addingReportingOverflow(1)
            guard !incremented.overflow else {
                throw DecimalExactError.exponentOverflow
            }
            exponent10 = incremented.partialValue
        }

        return CanonicalDecimalParts(
            isNegative: isNegative,
            digits: String(decoding: canonicalDigits, as: UTF8.self),
            exponent10: exponent10
        )
    }

    static func canonicalPartsFromCoefficient(
        isNegative: Bool,
        magnitudeDigits: String,
        scale: Int
    ) throws -> CanonicalDecimalParts {
        guard (0...38).contains(scale) else {
            throw DecimalExactError.invalidWidthScale
        }
        let bytes = try Self.validatedCoefficientDigits(magnitudeDigits)
        if bytes.allSatisfy({ $0 == 48 }) {
            return CanonicalDecimalParts(isNegative: false, digits: "0", exponent10: 0)
        }

        var canonicalDigits = bytes
        var exponent10 = 0.subtractingReportingOverflow(scale).partialValue
        while canonicalDigits.count > 1, canonicalDigits.last == 48 {
            canonicalDigits.removeLast()
            let incremented = exponent10.addingReportingOverflow(1)
            guard !incremented.overflow else {
                throw DecimalExactError.exponentOverflow
            }
            exponent10 = incremented.partialValue
        }

        return CanonicalDecimalParts(
            isNegative: isNegative,
            digits: String(decoding: canonicalDigits, as: UTF8.self),
            exponent10: exponent10
        )
    }

    static func renderCoefficientScaleText(
        isNegative: Bool,
        magnitudeDigits: String,
        scale: Int
    ) throws -> String {
        guard (0...38).contains(scale) else {
            throw DecimalExactError.invalidWidthScale
        }
        let bytes = try Self.validatedCoefficientDigits(magnitudeDigits)
        guard bytes.count <= 38 else {
            throw DecimalExactError.invalidCoefficient
        }
        let digits = String(decoding: bytes, as: UTF8.self)
        let prefix = isNegative && digits != "0" ? "-" : ""
        if scale == 0 {
            return prefix + digits
        }
        if bytes.count > scale {
            let split = bytes.count - scale
            let integerPart = String(decoding: bytes[..<split], as: UTF8.self)
            let fractionalPart = String(decoding: bytes[split...], as: UTF8.self)
            return prefix + integerPart + "." + fractionalPart
        }
        let leadingZeros = String(repeating: "0", count: scale - bytes.count)
        return prefix + "0." + leadingZeros + digits
    }

    static func foundationDecimalToCanonical(_ decimal: Decimal) throws -> CanonicalDecimalParts {
        guard !decimal.isNaN, decimal.isFinite else {
            throw DecimalExactError.nonfinite
        }
        var copy = decimal
        let text = NSDecimalString(&copy, Self.posixLocale)
        let parts = try Self.parseCanonicalDecimalText(text)
        guard let reparsed = Decimal(string: text, locale: Self.posixLocale),
              !reparsed.isNaN,
              reparsed.isFinite,
              reparsed == decimal else {
            throw DecimalExactError.malformedFoundationSpelling
        }
        return parts
    }

    static func exactCoefficient(
        from parts: CanonicalDecimalParts,
        width: Int,
        scale: Int
    ) throws -> ExactDecimalCoefficient {
        guard (1...38).contains(width), (0...width).contains(scale) else {
            throw DecimalExactError.invalidWidthScale
        }
        if parts.digits == "0" {
            return ExactDecimalCoefficient(words: Signed128Words(upper: 0, lower: 0), scale: scale)
        }

        let shiftResult = parts.exponent10.addingReportingOverflow(scale)
        guard !shiftResult.overflow else {
            throw DecimalExactError.exponentOverflow
        }
        let shift = shiftResult.partialValue
        guard shift >= 0 else {
            throw DecimalExactError.roundingRequired
        }

        let digitCount = parts.digits.utf8.count
        guard digitCount <= width else {
            throw DecimalExactError.widthOverflow
        }
        let remaining = width - digitCount
        guard shift <= remaining else {
            throw DecimalExactError.widthOverflow
        }

        let coefficientDigits = parts.digits + String(repeating: "0", count: shift)
        let words = try Self.signedWordsFromCoefficient(
            isNegative: parts.isNegative,
            magnitudeDigits: coefficientDigits
        )
        return ExactDecimalCoefficient(words: words, scale: scale)
    }

    static func magnitudeLimbs(for magnitudeDigits: String) throws -> [UInt32] {
        let bytes = try Self.validatedCoefficientDigits(magnitudeDigits)
        var limbs = [UInt32](repeating: 0, count: 4)
        for byte in bytes {
            var carry = UInt64(byte - 48)
            for index in stride(from: 3, through: 0, by: -1) {
                let product = UInt64(limbs[index]) * 10 + carry
                limbs[index] = UInt32(truncatingIfNeeded: product)
                carry = product >> 32
            }
            guard carry == 0 else {
                throw DecimalExactError.coefficientOverflow
            }
        }
        guard limbs[0] & 0x8000_0000 == 0 else {
            throw DecimalExactError.coefficientOverflow
        }
        return limbs
    }

    static func signedWordsFromCoefficient(
        isNegative: Bool,
        magnitudeDigits: String
    ) throws -> Signed128Words {
        let magnitude = try Self.magnitudeLimbs(for: magnitudeDigits)
        let isZero = magnitude.allSatisfy({ $0 == 0 })
        if isZero {
            guard !isNegative else {
                throw DecimalExactError.invalidCoefficient
            }
            return Signed128Words(upper: 0, lower: 0)
        }

        var limbs = magnitude
        if isNegative {
            for index in limbs.indices {
                limbs[index] = ~limbs[index]
            }
            var carry = UInt64(1)
            for index in stride(from: 3, through: 0, by: -1) {
                let sum = UInt64(limbs[index]) + carry
                limbs[index] = UInt32(truncatingIfNeeded: sum)
                carry = sum >> 32
            }
            guard carry == 0 else {
                throw DecimalExactError.coefficientOverflow
            }
        }

        let words = Self.words(from: limbs)
        if isNegative {
            guard words.upper < 0 else {
                throw DecimalExactError.coefficientOverflow
            }
        } else {
            guard words.upper >= 0 else {
                throw DecimalExactError.coefficientOverflow
            }
        }
        return words
    }

    static func limbs(from words: Signed128Words) -> [UInt32] {
        let upperBits = UInt64(bitPattern: words.upper)
        return [
            UInt32(truncatingIfNeeded: upperBits >> 32),
            UInt32(truncatingIfNeeded: upperBits),
            UInt32(truncatingIfNeeded: words.lower >> 32),
            UInt32(truncatingIfNeeded: words.lower)
        ]
    }

    static func signAndDigits(from words: Signed128Words) throws -> (isNegative: Bool, digits: String) {
        let isNegative = words.upper < 0
        var limbs = Self.limbs(from: words)
        if isNegative {
            for index in limbs.indices {
                limbs[index] = ~limbs[index]
            }
            var carry = UInt64(1)
            for index in stride(from: 3, through: 0, by: -1) {
                let sum = UInt64(limbs[index]) + carry
                limbs[index] = UInt32(truncatingIfNeeded: sum)
                carry = sum >> 32
            }
            guard carry == 0 else {
                throw DecimalExactError.invalidCoefficient
            }
        }
        guard limbs[0] & 0x8000_0000 == 0 else {
            throw DecimalExactError.invalidCoefficient
        }

        if limbs.allSatisfy({ $0 == 0 }) {
            guard !isNegative else {
                throw DecimalExactError.invalidCoefficient
            }
            return (false, "0")
        }

        var reversedDigits: [UInt8] = []
        while !limbs.allSatisfy({ $0 == 0 }) {
            var remainder = UInt64(0)
            for index in 0..<4 {
                let current = (remainder << 32) | UInt64(limbs[index])
                limbs[index] = UInt32(truncatingIfNeeded: current / 10)
                remainder = current % 10
            }
            reversedDigits.append(UInt8(48 + remainder))
        }

        return (
            isNegative,
            String(decoding: reversedDigits.reversed(), as: UTF8.self)
        )
    }

    static func foundationDecimalFromCoefficientScale(
        signedWords: Signed128Words,
        scale: Int
    ) throws -> Decimal {
        let decoded = try Self.signAndDigits(from: signedWords)
        let expected = try Self.canonicalPartsFromCoefficient(
            isNegative: decoded.isNegative,
            magnitudeDigits: decoded.digits,
            scale: scale
        )
        let text = try Self.renderCoefficientScaleText(
            isNegative: decoded.isNegative,
            magnitudeDigits: decoded.digits,
            scale: scale
        )
        guard let parsed = Decimal(string: text, locale: Self.posixLocale),
              !parsed.isNaN,
              parsed.isFinite else {
            throw DecimalExactError.reconstructionMismatch
        }
        var copy = parsed
        let formatted = NSDecimalString(&copy, Self.posixLocale)
        let actual = try Self.parseCanonicalDecimalText(formatted)
        guard actual == expected else {
            throw DecimalExactError.reconstructionMismatch
        }
        return parsed
    }

    private static func isASCIIDigit(_ byte: UInt8) -> Bool {
        (48...57).contains(byte)
    }

    private static func validatedCoefficientDigits(_ digits: String) throws -> [UInt8] {
        let bytes = Array(digits.utf8)
        guard !bytes.isEmpty else {
            throw DecimalExactError.invalidCoefficient
        }
        guard bytes.allSatisfy(Self.isASCIIDigit) else {
            throw DecimalExactError.invalidCoefficient
        }
        if bytes.count > 1, bytes.first == 48 {
            throw DecimalExactError.invalidCoefficient
        }
        return bytes
    }

    private static func words(from limbs: [UInt32]) -> Signed128Words {
        let upperBits = (UInt64(limbs[0]) << 32) | UInt64(limbs[1])
        let lower = (UInt64(limbs[2]) << 32) | UInt64(limbs[3])
        return Signed128Words(upper: Int64(bitPattern: upperBits), lower: lower)
    }
}
