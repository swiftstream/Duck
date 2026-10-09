import Cduckdb
import Foundation

/// Exact word-level transport between Swift 128-bit/UUID values and DuckDB.
///
/// Only the helpers that mention stdlib `Int128` / `UInt128` carry Darwin
/// availability. Every word/native/UUID helper is availability-free so hidden
/// 128-bit words and UUIDs round-trip on the macOS 12 / iOS 15 floors without
/// reconstructing stdlib numerics. There is no Double/Decimal/String
/// intermediary.
enum NativeScalarCodec {
    // MARK: - Availability-free signed word transport

    static func hugeint(upper: Int64, lower: UInt64) -> duckdb_hugeint {
        duckdb_hugeint(lower: lower, upper: upper)
    }

    static func signedWords(of value: duckdb_hugeint) -> (upper: Int64, lower: UInt64) {
        (upper: value.upper, lower: value.lower)
    }

    // MARK: - Availability-free unsigned word transport

    static func uhugeint(upper: UInt64, lower: UInt64) -> duckdb_uhugeint {
        duckdb_uhugeint(lower: lower, upper: upper)
    }

    static func unsignedWords(of value: duckdb_uhugeint) -> (upper: UInt64, lower: UInt64) {
        (upper: value.upper, lower: value.lower)
    }

    // MARK: - Availability-gated stdlib bridges

    /// Splits an `Int128` into its low 64 bits and arithmetic high 64 bits.
    @available(macOS 15.0, iOS 18.0, *)
    static func signedWords(from value: Int128) -> (upper: Int64, lower: UInt64) {
        (
            upper: Int64(truncatingIfNeeded: value >> 64),
            lower: UInt64(truncatingIfNeeded: value)
        )
    }

    /// Reconstructs an `Int128` from an exact signed high word plus low word.
    @available(macOS 15.0, iOS 18.0, *)
    static func int128(upper: Int64, lower: UInt64) -> Int128 {
        (Int128(upper) << 64) | Int128(truncatingIfNeeded: lower)
    }

    /// Splits a `UInt128` into low and high 64-bit words.
    @available(macOS 15.0, iOS 18.0, *)
    static func unsignedWords(from value: UInt128) -> (upper: UInt64, lower: UInt64) {
        (
            upper: UInt64(truncatingIfNeeded: value >> 64),
            lower: UInt64(truncatingIfNeeded: value)
        )
    }

    /// Reconstructs a `UInt128` as `(upper << 64) | lower`.
    @available(macOS 15.0, iOS 18.0, *)
    static func uint128(upper: UInt64, lower: UInt64) -> UInt128 {
        (UInt128(upper) << 64) | UInt128(lower)
    }

    @available(macOS 15.0, iOS 18.0, *)
    static func hugeint(from value: Int128) -> duckdb_hugeint {
        let words = signedWords(from: value)
        return hugeint(upper: words.upper, lower: words.lower)
    }

    @available(macOS 15.0, iOS 18.0, *)
    static func int128(from value: duckdb_hugeint) -> Int128 {
        let words = signedWords(of: value)
        return int128(upper: words.upper, lower: words.lower)
    }

    @available(macOS 15.0, iOS 18.0, *)
    static func uhugeint(from value: UInt128) -> duckdb_uhugeint {
        let words = unsignedWords(from: value)
        return uhugeint(upper: words.upper, lower: words.lower)
    }

    @available(macOS 15.0, iOS 18.0, *)
    static func uint128(from value: duckdb_uhugeint) -> UInt128 {
        let words = unsignedWords(of: value)
        return uint128(upper: words.upper, lower: words.lower)
    }

    // MARK: - Availability-free UUID transport

    /// Canonical Foundation UUID bytes as big-endian word pairs:
    /// bytes 0...7 -> upper, bytes 8...15 -> lower.
    static func canonicalUUIDWords(from uuid: UUID) -> duckdb_uhugeint {
        withUnsafeBytes(of: uuid.uuid) { bytes in
            var upper: UInt64 = 0
            var lower: UInt64 = 0
            for index in 0..<8 {
                upper = (upper << 8) | UInt64(bytes[index])
                lower = (lower << 8) | UInt64(bytes[index + 8])
            }
            return duckdb_uhugeint(lower: lower, upper: upper)
        }
    }

    static func uuid(fromCanonicalWords words: duckdb_uhugeint) -> UUID {
        var bytes: uuid_t = (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
        withUnsafeMutableBytes(of: &bytes) { buffer in
            for index in 0..<8 {
                buffer[index] = UInt8(truncatingIfNeeded: words.upper >> UInt64(56 - index * 8))
                buffer[index + 8] = UInt8(truncatingIfNeeded: words.lower >> UInt64(56 - index * 8))
            }
        }
        return UUID(uuid: bytes)
    }

    /// DuckDB physical UUID ordering: lower passes through, the upper word
    /// toggles bit 63 relative to the canonical word.
    static func physicalUUIDWords(fromCanonicalWords words: duckdb_uhugeint) -> duckdb_hugeint {
        duckdb_hugeint(
            lower: words.lower,
            upper: Int64(bitPattern: words.upper ^ (UInt64(1) << 63))
        )
    }

    static func canonicalUUIDWords(fromPhysicalWords words: duckdb_hugeint) -> duckdb_uhugeint {
        duckdb_uhugeint(
            lower: words.lower,
            upper: UInt64(bitPattern: words.upper) ^ (UInt64(1) << 63)
        )
    }
}
