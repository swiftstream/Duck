import Cduckdb
import Foundation

final class NativeResult {
    // Keep the native connection alive for the complete result-copy lifetime.
    private let connection: NativeConnection
    private var result: duckdb_result

    init(connection: NativeConnection, result: duckdb_result) {
        self.connection = connection
        self.result = result
    }

    deinit {
        duckdb_destroy_result(&result)
    }

    var rowsChanged: UInt64 {
        UInt64(duckdb_rows_changed(&result))
    }

    func columnNames() throws -> [String] {
        let count = try integerCount(duckdb_column_count(&result), name: "column count")
        var columns: [String] = []
        columns.reserveCapacity(count)

        for index in 0..<count {
            guard let name = duckdb_column_name(&result, idx_t(index)) else {
                throw NativeDuckDBError(
                    operation: .invalidResult,
                    message: "DuckDB returned no name for result column \(index)."
                )
            }
            columns.append(String(cString: name))
        }

        return columns
    }

    func resultColumns() throws -> [ResultColumn] {
        let names = try columnNames()
        var columns: [ResultColumn] = []
        columns.reserveCapacity(names.count)

        for (index, name) in names.enumerated() {
            guard let logicalType = duckdb_column_logical_type(&result, idx_t(index)) else {
                throw NativeDuckDBError(
                    operation: .invalidResult,
                    message: "DuckDB returned no logical type for result column \(index)."
                )
            }
            var ownedLogicalType: duckdb_logical_type? = logicalType
            defer { duckdb_destroy_logical_type(&ownedLogicalType) }

            columns.append(
                ResultColumn(name: name, logicalType: try NativeLogicalTypeCopier.copyBorrowed(logicalType))
            )
        }

        return columns
    }

    func materializeNextChunk() throws -> [Row]? {
        var chunk = duckdb_fetch_chunk(result)
        guard let chunkHandle = chunk else {
            return nil
        }
        defer { duckdb_destroy_data_chunk(&chunk) }

        let resultColumnCount = try integerCount(duckdb_column_count(&result), name: "result column count")
        let chunkColumnCount = try integerCount(
            duckdb_data_chunk_get_column_count(chunkHandle),
            name: "chunk column count"
        )
        guard chunkColumnCount == resultColumnCount else {
            throw NativeDuckDBError(
                operation: .invalidResult,
                message: "DuckDB result column count does not match its data chunk."
            )
        }

        let rowCount = try integerCount(duckdb_data_chunk_get_size(chunkHandle), name: "chunk row count")
        let columns = try columnNames()
        var valuesByRow = Array(repeating: [Value](), count: rowCount)

        for columnIndex in 0..<chunkColumnCount {
            guard let vector = duckdb_data_chunk_get_vector(chunkHandle, idx_t(columnIndex)) else {
                throw NativeDuckDBError(
                    operation: .invalidResult,
                    message: "DuckDB returned no vector for result column \(columnIndex)."
                )
            }

            let type = duckdb_column_type(&result, idx_t(columnIndex))
            let validity = duckdb_vector_get_validity(vector)

            for rowIndex in 0..<rowCount {
                if let validity, !duckdb_validity_row_is_valid(validity, idx_t(rowIndex)) {
                    valuesByRow[rowIndex].append(.null)
                    continue
                }

                valuesByRow[rowIndex].append(
                    try materializeValue(type: type, vector: vector, rowIndex: rowIndex)
                )
            }
        }

        return valuesByRow.map { Row(columns: columns, values: $0) }
    }

    private func materializeValue(type: duckdb_type, vector: duckdb_vector, rowIndex: Int) throws -> Value {
        guard let data = duckdb_vector_get_data(vector) else {
            throw NativeDuckDBError(
                operation: .invalidResult,
                message: "DuckDB returned no vector data for a non-null value."
            )
        }

        switch type {
        case DUCKDB_TYPE_BOOLEAN:
            return .boolean(data.assumingMemoryBound(to: Bool.self)[rowIndex])
        case DUCKDB_TYPE_TINYINT:
            return .int8(data.assumingMemoryBound(to: Int8.self)[rowIndex])
        case DUCKDB_TYPE_SMALLINT:
            return .int16(data.assumingMemoryBound(to: Int16.self)[rowIndex])
        case DUCKDB_TYPE_INTEGER:
            return .int32(data.assumingMemoryBound(to: Int32.self)[rowIndex])
        case DUCKDB_TYPE_BIGINT:
            return .int64(data.assumingMemoryBound(to: Int64.self)[rowIndex])
        case DUCKDB_TYPE_UTINYINT:
            return .uint8(data.assumingMemoryBound(to: UInt8.self)[rowIndex])
        case DUCKDB_TYPE_USMALLINT:
            return .uint16(data.assumingMemoryBound(to: UInt16.self)[rowIndex])
        case DUCKDB_TYPE_UINTEGER:
            return .uint32(data.assumingMemoryBound(to: UInt32.self)[rowIndex])
        case DUCKDB_TYPE_UBIGINT:
            return .uint64(data.assumingMemoryBound(to: UInt64.self)[rowIndex])
        case DUCKDB_TYPE_FLOAT:
            return .float(data.assumingMemoryBound(to: Float.self)[rowIndex])
        case DUCKDB_TYPE_DOUBLE:
            return .double(data.assumingMemoryBound(to: Double.self)[rowIndex])
        case DUCKDB_TYPE_VARCHAR:
            return try materializeString(data: data, rowIndex: rowIndex)
        case DUCKDB_TYPE_BLOB:
            return try materializeBlob(data: data, rowIndex: rowIndex)
        case DUCKDB_TYPE_HUGEINT:
            let words = NativeScalarCodec.signedWords(
                of: data.assumingMemoryBound(to: duckdb_hugeint.self)[rowIndex]
            )
            return Value(signedUpper: words.upper, lower: words.lower)
        case DUCKDB_TYPE_UHUGEINT:
            let words = NativeScalarCodec.unsignedWords(
                of: data.assumingMemoryBound(to: duckdb_uhugeint.self)[rowIndex]
            )
            return Value(unsignedUpper: words.upper, lower: words.lower)
        case DUCKDB_TYPE_UUID:
            let physical = data.assumingMemoryBound(to: duckdb_hugeint.self)[rowIndex]
            let canonical = NativeScalarCodec.canonicalUUIDWords(fromPhysicalWords: physical)
            return .uuid(NativeScalarCodec.uuid(fromCanonicalWords: canonical))
        case DUCKDB_TYPE_DATE:
            return try temporalValue {
                .date(try NativeTemporalCodec.pureDate(
                    from: data.assumingMemoryBound(to: duckdb_date.self)[rowIndex]
                ))
            }
        case DUCKDB_TYPE_TIME:
            return try temporalValue {
                .time(try NativeTemporalCodec.pureTime(
                    from: data.assumingMemoryBound(to: duckdb_time.self)[rowIndex]
                ))
            }
        case DUCKDB_TYPE_TIME_NS:
            return try temporalValue {
                .time(try NativeTemporalCodec.pureTime(
                    from: data.assumingMemoryBound(to: duckdb_time_ns.self)[rowIndex]
                ))
            }
        case DUCKDB_TYPE_TIMESTAMP_S:
            return try temporalValue {
                .dateTime(try NativeTemporalCodec.dateTime(
                    fromRaw: data.assumingMemoryBound(to: duckdb_timestamp_s.self)[rowIndex].seconds,
                    source: .timestampS
                ))
            }
        case DUCKDB_TYPE_TIMESTAMP_MS:
            return try temporalValue {
                .dateTime(try NativeTemporalCodec.dateTime(
                    fromRaw: data.assumingMemoryBound(to: duckdb_timestamp_ms.self)[rowIndex].millis,
                    source: .timestampMS
                ))
            }
        case DUCKDB_TYPE_TIMESTAMP:
            return try temporalValue {
                .dateTime(try NativeTemporalCodec.dateTime(
                    fromRaw: data.assumingMemoryBound(to: duckdb_timestamp.self)[rowIndex].micros,
                    source: .timestamp
                ))
            }
        case DUCKDB_TYPE_TIMESTAMP_NS:
            return try temporalValue {
                .dateTime(try NativeTemporalCodec.dateTime(
                    fromRaw: data.assumingMemoryBound(to: duckdb_timestamp_ns.self)[rowIndex].nanos,
                    source: .timestampNS
                ))
            }
        case DUCKDB_TYPE_TIMESTAMP_TZ:
            return try temporalValue {
                .timestampTZ(try NativeFoundationDateCodec.date(
                    fromRawMicroseconds: data.assumingMemoryBound(to: duckdb_timestamp.self)[rowIndex].micros
                ))
            }
        case DUCKDB_TYPE_INTERVAL:
            return .interval(
                NativeIntervalCodec.interval(
                    from: data.assumingMemoryBound(to: duckdb_interval.self)[rowIndex]
                )
            )
        default:
            throw NativeDuckDBError(
                operation: .unsupportedResultType,
                message: "Unsupported DuckDB result type: \(type)."
            )
        }
    }

    private func temporalValue(_ body: () throws -> Value) throws -> Value {
        do {
            return try body()
        } catch let error as NativeTemporalConversionError {
            throw NativeDuckDBError(operation: .invalidResult, message: error.message)
        }
    }

    private func materializeString(data: UnsafeMutableRawPointer, rowIndex: Int) throws -> Value {
        var string = data.assumingMemoryBound(to: duckdb_string_t.self)[rowIndex]
        let length = Int(duckdb_string_t_length(string))
        guard length > 0 else {
            return .string("")
        }
        guard let bytes = duckdb_string_t_data(&string) else {
            throw NativeDuckDBError(
                operation: .invalidResult,
                message: "DuckDB returned no bytes for a non-empty VARCHAR value."
            )
        }

        let value = Data(bytes: bytes, count: length)
        guard let stringValue = String(data: value, encoding: .utf8) else {
            throw NativeDuckDBError(
                operation: .invalidResult,
                message: "DuckDB returned invalid UTF-8 for a VARCHAR value."
            )
        }

        return .string(stringValue)
    }

    private func materializeBlob(data: UnsafeMutableRawPointer, rowIndex: Int) throws -> Value {
        var string = data.assumingMemoryBound(to: duckdb_string_t.self)[rowIndex]
        let length = Int(duckdb_string_t_length(string))
        guard length > 0 else {
            return .blob(Data())
        }
        guard let bytes = duckdb_string_t_data(&string) else {
            throw NativeDuckDBError(
                operation: .invalidResult,
                message: "DuckDB returned no bytes for a non-empty BLOB value."
            )
        }

        return .blob(Data(bytes: bytes, count: length))
    }

    private func integerCount(_ value: idx_t, name: String) throws -> Int {
        guard let count = Int(exactly: value) else {
            throw NativeDuckDBError(
                operation: .invalidResult,
                message: "DuckDB \(name) does not fit in Swift Int."
            )
        }
        return count
    }
}
