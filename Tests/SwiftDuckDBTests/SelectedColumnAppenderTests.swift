@testable import SwiftDuckDB
import Foundation
import SQL
import Testing

private struct SelectedAppenderUnsupported: Sendable {}

private enum SelectedAppenderFailure: Error, Equatable, Sendable {
    case body
}

private func selectedNativeExecute(
    _ connection: NativeConnection,
    _ query: any SQLable
) throws -> NativeResult {
    let statement = try connection.prepare(query.prepare(.duck).plain)
    let pending = try statement.pending()
    while try pending.executeTask() == .notReady {}
    return try pending.execute()
}

private func selectedAppenderDefault(_ value: Any) -> any SQLable {
    SQL.default[
        any: SQLableParts(parts: SQLPartSafeValue(value))
    ]
}

private func selectedAppenderSequenceDefault(_ sequenceName: String) -> any SQLable {
    SQL.default[
        any: Fn.nextVal(
            SQLableParts(parts: SQLPartSafeValue(sequenceName))
        )
    ]
}

private func selectedAppenderCount(
    _ table: Path.Table,
    on connection: Connection
) async throws -> Int64 {
    let result = try await connection.query(
        SQL.select(Fn.count(table.column("id")) => "count").from(table)
    )
    let row = try #require(result.rows.first)
    let value = try #require(row["count"])
    return try #require(value.get(Int64.self))
}

private func selectedAppenderDrainedCount(
    _ database: Database,
    registration: ObservationRegistration
) async -> Int {
    await database.observationCoordinator.unregister(registration.id)
    var iterator = registration.invalidations.makeAsyncIterator()
    var count = 0
    while await iterator.next() != nil {
        count += 1
    }
    return count
}

@Suite("SelectedColumnAppenderTests")
struct SelectedColumnAppenderTests {
    @Test("Native selected columns refresh active order and copied types before rows")
    func selectedNativeOrderAndMetadata() throws {
        let database = try NativeDatabase()
        let connection = try database.connect()
        let table = Path.Table("selected_native_order")
        _ = try selectedNativeExecute(
            connection,
            SQL
                .create
                .table[any: table]
                .tableDefinitions(
                    NewColumn("first", .integer),
                    NewColumn("second", .varchar),
                    NewColumn("third", .boolean)
                )
        )

        let appender = try NativeAppender(
            connection: connection,
            table: "selected_native_order",
            selectedColumns: ["third", "first"]
        )
        #expect(appender.columnCount == 2)
        #expect(appender.targetDescriptors.map(\.id) == [.boolean, .integer])
        try appender.appendRow([.boolean(true), .int32(42)])
        try appender.close()

        let result = try selectedNativeExecute(
            connection,
            SQL
                .select(
                    table.column("first"),
                    table.column("second"),
                    table.column("third")
                )
                .from(table)
        )
        let rows = try #require(try result.materializeNextChunk())
        let row = try #require(rows.first)
        #expect(row["first"] == .int32(42))
        #expect(row["second"] == .null)
        #expect(row["third"] == .boolean(true))
    }

    @Test("Omitted selected columns use DEFAULT or NULL while selected nil is NULL")
    func selectedOmissionAndNullSemantics() async throws {
        let connection = try Database().connect()
        let table = Path.Table("selected_defaults")
        _ = try await connection.execute(
            SQL
                .create
                .table[any: table]
                .tableDefinitions(
                    NewColumn("id", .integer),
                    NewColumn("constant_value", .integer)
                        .default(expression: selectedAppenderDefault(Int32(17))),
                    NewColumn("absent_value", .integer)
                )
        )
        _ = try await connection.execute(
            SQL
                .create
                .sequence[any: Path.Identifier("selected_sequence")]
                .start(50)
        )
        let sequenceTable = Path.Table("selected_sequence_defaults")
        _ = try await connection.execute(
            SQL
                .create
                .table[any: sequenceTable]
                .tableDefinitions(
                    NewColumn("id", .integer),
                    NewColumn("sequence_value", .integer)
                        .default(expression: selectedAppenderSequenceDefault("selected_sequence"))
                )
        )
        try await connection.appender(to: table, columns: ["id"]) { appender in
            try await appender.append(Int32(1))
        }
        try await connection.appender(to: table, columns: ["constant_value"]) { appender in
            try await appender.append(Optional<Int32>.none)
        }
        try await connection.appender(to: sequenceTable, columns: ["id"]) { appender in
            try await appender.append(Int32(2))
        }

        let result = try await connection.query(
            SQL
                .select(
                    table.column("id"),
                    table.column("constant_value"),
                    table.column("absent_value")
                )
                .from(table)
                .orderBy(.asc(table.column("id")))
        )
        #expect(result.rows.count == 2)
        #expect(result.rows[0]["constant_value"] == .int32(17))
        #expect(result.rows[0]["absent_value"] == .null)
        #expect(result.rows[1]["constant_value"] == .null)

        let sequence = try await connection.query(
            SQL
                .select(sequenceTable.column("sequence_value"))
                .from(sequenceTable)
        )
        #expect(sequence.rows.first?["sequence_value"] == .int32(50))
    }

    @Test("Invalid selected names fail creation before body and leave Connection usable")
    func selectedNameFailuresReleaseSetup() async throws {
        let connection = try Database().connect()
        let table = Path.Table("selected_name_failures")
        _ = try await connection.execute(
            SQL
                .create
                .table[any: table]
                .tableDefinitions(
                    NewColumn("id", .integer),
                    NewColumn("MixedCase", .integer),
                    NewColumn("literal\"quote", .integer),
                    GeneratedColumn(
                        "generated",
                        .integer,
                        generatedAlwaysAs: Path.Column("id") + SQLableParts(
                            parts: SQLPartSafeValue(Int32(1))
                        )
                    )
                )
        )
        let invalidSelections: [[String]] = [
            [], [""], ["\0"], ["id", "id"], ["unknown"], ["generated"], ["\"MixedCase\""]
        ]
        for columns in invalidSelections {
            var enteredBody = false
            do {
                try await connection.appender(to: table, columns: columns) { _ in
                    enteredBody = true
                }
                Issue.record("Expected selected column setup to fail for \(columns).")
            } catch let error as DatabaseError {
                guard case .appenderCreation(let message) = error else {
                    Issue.record("Expected appenderCreation, got \(error).")
                    continue
                }
                #expect(!message.isEmpty)
            }
            #expect(!enteredBody)
        }

        try await connection.appender(to: table, columns: ["literal\"quote", "MixedCase"]) { appender in
            try await appender.append(Int32(8), Int32(9))
        }
        let result = try await connection.query(
            SQL
                .select(
                    table.column("literal\"quote"),
                    table.column("MixedCase")
                )
                .from(table)
        )
        #expect(result.rows.first?["literal\"quote"] == .int32(8))
        #expect(result.rows.first?["MixedCase"] == .int32(9))
        let usable = try await connection.query(SQL.select(Int32(11) => "value"))
        #expect(usable.rows.first?["value"] == .int32(11))
    }

    @Test("Selected row preflight failures are recoverable before native mutation")
    func selectedRowPreflightIsRecoverable() async throws {
        let database = try Database()
        let connection = try database.connect()
        let table = Path.Table("selected_preflight")
        _ = try await connection.execute(
            SQL
                .create
                .table[any: table]
                .tableDefinitions(
                    NewColumn("id", .integer),
                    NewColumn("name", .varchar),
                    NewColumn("late", .integer)
                )
        )
        let abortedObservation = await database.observationCoordinator
            .register(initial: .database)
        do {
            try await connection.appender(to: table, columns: ["name", "late"]) { appender in
                try await appender.append("discarded", Int32(1))
                throw SelectedAppenderFailure.body
            }
            Issue.record("Expected the small selected Appender body to abort.")
        } catch let error as SelectedAppenderFailure {
            #expect(error == .body)
        }
        #expect(await selectedAppenderDrainedCount(database, registration: abortedObservation) == 0)
        #expect(try await selectedAppenderCount(table, on: connection) == 0)

        let preflightObservation = await database.observationCoordinator
            .register(initial: .database)
        var escaped: Appender?
        try await connection.appender(to: table, columns: ["name", "late"]) { appender in
            escaped = appender
            do {
                try await appender.append("short")
                Issue.record("Expected selected width mismatch.")
            } catch let error as DatabaseError {
                #expect(error == .appenderArgumentCount(expected: 2, actual: 1))
            }
            do {
                try await appender.append("unsupported", SelectedAppenderUnsupported())
                Issue.record("Expected unsupported selected value.")
            } catch let error as DatabaseError {
                guard case .unsupportedBindingType = error else {
                    Issue.record("Expected unsupportedBindingType, got \(error).")
                    return
                }
            }
            do {
                try await appender.append("must not partially append", "wrong late column")
                Issue.record("Expected exact mismatch in the late selected column.")
            } catch let error as DatabaseError {
                guard case .appenderAppend(let column, _) = error else {
                    Issue.record("Expected appenderAppend preflight, got \(error).")
                    return
                }
                #expect(column == 2)
            }
            try await appender.append("valid", Int32(7))
        }
        let result = try await connection.query(
            SQL.select(table.column("name"), table.column("late")).from(table)
        )
        #expect(result.rows.count == 1)
        #expect(result.rows.first?["name"] == .string("valid"))
        #expect(result.rows.first?["late"] == .int32(7))
        #expect(await selectedAppenderDrainedCount(database, registration: preflightObservation) == 1)
        do {
            try await escaped?.append("after", Int32(8))
            Issue.record("Expected escaped selected Appender to end with its scope.")
        } catch let error as DatabaseError {
            #expect(error == .appenderEnded)
        }
    }

    @Test("Selected finalization failure reports constraint and conservatively publishes")
    func selectedConstraintFinalizationPublishes() async throws {
        let database = try Database()
        let connection = try database.connect()
        let table = Path.Table("selected_constraint")
        _ = try await connection.execute(
            SQL
                .create
                .table[any: table]
                .tableDefinitions(
                    NewColumn("id", .integer)
                        .check(
                            Path.Column("id") > SQLableParts(
                                parts: SQLPartSafeValue(Int32(0))
                            )
                        ),
                    NewColumn("ignored", .varchar)
                )
        )
        let registration = await database.observationCoordinator.register(initial: .database)
        do {
            try await connection.appender(to: table, columns: ["id"]) { appender in
                try await appender.append(Int32(-1))
            }
            Issue.record("Expected selected constraint failure on scope close.")
        } catch let error as DatabaseError {
            guard case .appenderFinalization(let message) = error else {
                Issue.record("Expected appenderFinalization, got \(error).")
                return
            }
            #expect(message.contains("CHECK"))
        }
        #expect(await selectedAppenderDrainedCount(database, registration: registration) >= 1)
        #expect(try await selectedAppenderCount(table, on: connection) == 0)
    }

    @Test("Selected 204800 row auto-flush preserves prefix and invalidates Observation")
    func selectedAutoFlushPrefixAndObservation() async throws {
        let database = try Database()
        let connection = try database.connect()
        let table = Path.Table("selected_autoflush")
        _ = try await connection.execute(
            SQL
                .create
                .table[any: table]
                .tableDefinitions(
                    NewColumn("id", .integer),
                    NewColumn("omitted", .varchar)
                        .default(expression: selectedAppenderDefault("default"))
                )
        )
        let registration = await database.observationCoordinator.register(initial: .database)
        do {
            try await connection.appender(to: table, columns: ["id"]) { appender in
                for value in 0..<204_800 {
                    try await appender.append(Int32(value))
                }
                throw SelectedAppenderFailure.body
            }
            Issue.record("Expected selected Appender body failure after native auto-flush.")
        } catch let error as SelectedAppenderFailure {
            #expect(error == .body)
        }
        #expect(await selectedAppenderDrainedCount(database, registration: registration) >= 1)
        #expect(try await selectedAppenderCount(table, on: connection) == 204_800)
    }

    @Test("Selected Transaction appends publish at commit and caught errors remain rollback-only")
    func selectedTransactionCommitAndRollbackOnly() async throws {
        let database = try Database()
        let connection = try database.connect()
        let observer = try database.connect()
        let table = Path.Table("selected_transaction")
        _ = try await connection.execute(
            SQL
                .create
                .table[any: table]
                .tableDefinitions(
                    NewColumn("id", .integer),
                    NewColumn("omitted", .varchar)
                        .default(expression: selectedAppenderDefault("x"))
                )
        )
        let committed = await database.observationCoordinator.register(initial: .database)
        try await connection.transaction { transaction in
            try await transaction.appender(to: table, columns: ["id"]) { appender in
                try await appender.append(Int32(1))
            }
            #expect(try await selectedAppenderCount(table, on: observer) == 0)
        }
        #expect(await selectedAppenderDrainedCount(database, registration: committed) == 1)

        let precommit = await database.observationCoordinator.register(initial: .database)
        try await connection.transaction { transaction in
            try await transaction.appender(to: table, columns: ["id"]) { appender in
                try await appender.append(Int32(9))
            }
            _ = await database.observationCoordinator.unregister(precommit.id)
        }
        #expect(await selectedAppenderDrainedCount(database, registration: precommit) == 0)

        let rolledBackObservation = await database.observationCoordinator.register(initial: .database)
        let expected = DatabaseError.appenderArgumentCount(expected: 1, actual: 0)
        do {
            try await connection.transaction { transaction in
                do {
                    try await transaction.appender(to: table, columns: ["id"]) { appender in
                        try await appender.append(Int32(2))
                        try await appender.append()
                    }
                    Issue.record("Expected selected Transaction Appender argument error.")
                } catch let error as DatabaseError {
                    #expect(error == expected)
                }
                _ = await database.observationCoordinator.unregister(rolledBackObservation.id)
            }
            Issue.record("Expected caught Appender failure to prevent COMMIT.")
        } catch let error as DatabaseError {
            #expect(error == expected)
        }
        #expect(await selectedAppenderDrainedCount(database, registration: rolledBackObservation) == 0)
        #expect(try await selectedAppenderCount(table, on: observer) == 2)
    }

    @Test("Selected Appender guards same Connection, releases cancellation, and permits another Connection")
    func selectedScopeGuardsAndCancellation() async throws {
        let database = try Database()
        let connection = try database.connect()
        let other = try database.connect()
        let table = Path.Table("selected_guards")
        _ = try await connection.execute(
            SQL
                .create
                .table[any: table]
                .tableDefinitions(
                    NewColumn("id", .integer),
                    NewColumn("ignored", .integer)
                )
        )
        try await connection.appender(to: table, columns: ["id"]) { appender in
            do {
                _ = try await connection.query(SQL.select(Int32(1) => "value"))
                Issue.record("Expected same-Connection scope guard.")
            } catch let error as DatabaseError {
                #expect(error == .appenderScopeViolation)
            }
            try await appender.append(Int32(3))
            let independent = try await other.query(SQL.select(Int32(4) => "value"))
            #expect(independent.rows.first?["value"] == .int32(4))
        }

        let tableName = table.name
        let cancellation = Task {
            try await connection.appender(to: Path.Table(tableName), columns: ["id"]) { appender in
                withUnsafeCurrentTask { $0?.cancel() }
                try await appender.append(Int32(5))
            }
        }
        do {
            try await cancellation.value
            Issue.record("Expected cancellation before selected native row mutation.")
        } catch is CancellationError {
            // Expected.
        }
        let usable = try await connection.query(SQL.select(Int32(6) => "value"))
        #expect(usable.rows.first?["value"] == .int32(6))
        #expect(try await selectedAppenderCount(table, on: connection) == 1)
    }

    @Test("Selected pooled ordinary and Transaction scopes return a usable checkout")
    func selectedPooledScopesReturnCheckout() async throws {
        let database = try Database()
        let pool = try database.pool(maximumConnections: 1)
        let table = Path.Table("selected_pool")
        let firstId = try await pool.connection { connection in
            _ = try await connection.execute(
                SQL
                    .create
                    .table[any: table]
                    .tableDefinitions(
                        NewColumn("id", .integer),
                        NewColumn("omitted", .integer)
                            .default(expression: selectedAppenderDefault(Int32(12)))
                    )
            )
            try await connection.appender(to: table, columns: ["id"]) { appender in
                try await appender.append(Int32(1))
            }
            return connection.id
        }
        try await pool.transaction { transaction in
            try await transaction.appender(to: table, columns: ["id"]) { appender in
                try await appender.append(Int32(2))
            }
        }
        let checkout = try await pool.connection { connection in
            #expect(connection.id == firstId)
            return try await selectedAppenderCount(table, on: connection)
        }
        #expect(checkout == 2)
        try await pool.shutdown()
    }
}
