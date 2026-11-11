import Cduckdb

/// Raised when a STRUCT member cannot be converted exactly to its named target child type.
struct NativeStructValueConversionError: Error, Sendable {
    let message: String
}

/// Builds one native DuckDB STRUCT value from ordered, name-keyed members.
///
/// The parent target is borrowed. Reacquired member types and temporary child values are owned
/// and destroyed by this codec; a returned parent value transfers to the caller.
enum NativeStructValueCodec {
    /// Creates an owned native STRUCT value after validating and reordering every member by name.
    ///
    /// - Parameters:
    ///   - value: The ordered STRUCT members to transport.
    ///   - parentTarget: A live native STRUCT logical type borrowed for this call.
    /// - Returns: A caller-owned native STRUCT value.
    static func createStructValue(
        from value: Value,
        borrowingParentTarget parentTarget: duckdb_logical_type
    ) throws -> duckdb_value {
        guard case .structure(let sourceMembers) = value.storage else {
            throw failure("Only Value.structure can be transported as a native STRUCT.")
        }
        guard duckdb_get_type_id(parentTarget) == DUCKDB_TYPE_STRUCT else {
            throw failure("Value.structure requires a STRUCT target logical type.")
        }

        let parentDescriptor: LogicalType
        do {
            parentDescriptor = try NativeLogicalTypeCopier.copyBorrowed(parentTarget)
        } catch {
            throw failure("DuckDB STRUCT target metadata could not be copied: \(error)")
        }
        guard case .structure(let targetMembers) = parentDescriptor.detail else {
            throw failure("DuckDB returned a STRUCT target without member descriptors.")
        }

        let targetNames = targetMembers.map(\.name)
        guard Set(targetNames).count == targetNames.count else {
            throw failure("DuckDB STRUCT target contains duplicate member names.")
        }

        var sourceByName: [String: Value] = [:]
        sourceByName.reserveCapacity(sourceMembers.count)
        for member in sourceMembers {
            guard sourceByName.updateValue(member.value, forKey: member.name) == nil else {
                throw failure("Duplicate STRUCT source member name \(String(reflecting: member.name)).")
            }
        }

        let targetNameSet = Set(targetNames)
        let sourceNameSet = Set(sourceByName.keys)
        let missingNames = targetNameSet.subtracting(sourceNameSet).sorted()
        guard missingNames.isEmpty else {
            throw failure("Missing STRUCT target member \(String(reflecting: missingNames[0])).")
        }

        let unknownNames = sourceNameSet.subtracting(targetNameSet).sorted()
        guard unknownNames.isEmpty else {
            throw failure("Unknown STRUCT source member \(String(reflecting: unknownNames[0])).")
        }

        // Name-set validation is complete before constructing any native child values.
        let slotCount = Swift.max(targetMembers.count, 1)
        let values = UnsafeMutablePointer<duckdb_value?>.allocate(capacity: slotCount)
        var createdCount = 0
        defer {
            for index in 0..<createdCount {
                duckdb_destroy_value(&values[index])
            }
            values.deallocate()
        }

        for (index, member) in targetMembers.enumerated() {
            guard let sourceValue = sourceByName[member.name] else {
                throw failure("Validated STRUCT member \(String(reflecting: member.name)) was unavailable.")
            }
            guard let rawChildTarget = duckdb_struct_type_child_type(parentTarget, idx_t(index)) else {
                throw failure("DuckDB returned no target type for STRUCT member \(String(reflecting: member.name)).")
            }
            var ownedChildTarget: duckdb_logical_type? = rawChildTarget
            defer { duckdb_destroy_logical_type(&ownedChildTarget) }

            let childDescriptor: LogicalType
            do {
                childDescriptor = try NativeLogicalTypeCopier.copyBorrowed(rawChildTarget)
            } catch {
                throw failure(
                    "DuckDB target metadata could not be copied for STRUCT member \(String(reflecting: member.name)): \(error)"
                )
            }
            guard childDescriptor == member.type else {
                throw failure("STRUCT member target descriptor changed during construction.")
            }
            try requireScalarTarget(childDescriptor, memberName: member.name)

            do {
                values[index] = try NativeTargetScalarValueFactory.createScalarValue(
                    sourceValue,
                    descriptor: childDescriptor,
                    rawTarget: rawChildTarget,
                    context: "STRUCT member \(String(reflecting: member.name))"
                )
            } catch let error as NativeTargetValueConversionError {
                throw failure(error.message)
            }
            createdCount = index + 1
        }

        guard let structValue = duckdb_create_struct_value(parentTarget, values) else {
            throw failure("DuckDB failed to create the native STRUCT value.")
        }
        return structValue
    }

    private static func requireScalarTarget(
        _ descriptor: LogicalType,
        memberName: String
    ) throws {
        switch descriptor.id {
        case .list, .structType, .map, .union, .array:
            throw failure(
                "STRUCT member \(String(reflecting: memberName)) has unsupported composite target type \(descriptor.id.rawValue)."
            )
        default:
            return
        }
    }

    private static func failure(_ message: String) -> NativeStructValueConversionError {
        NativeStructValueConversionError(message: message)
    }
}
