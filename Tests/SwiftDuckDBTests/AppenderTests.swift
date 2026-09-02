@testable import SwiftDuckDB
import Foundation
import SwifQL
import Testing

private struct UnsupportedAppenderValue: Sendable {}

private enum AppenderBodyTestError: Error, Sendable {
    case stop
}

@Test("Scoped Appender writes complete rows through a table target")
func scopedAppenderWritesTableRows() async throws {
    let connection = try Database().connect()
    let table = Path.Table("appender_public_rows")

    try await connection.execute(
        SwifQL
            .create
            .table[any: table]
            .tableDefinitions(
                NewColumn("id", .integer),
                NewColumn("name", .text),
                NewColumn("payload", .blob),
                NewColumn("note", .text)
            )
    )

    try await connection.appender(to: table) { appender in
        try await appender.append(
            Int32(1),
            "Mike",
            Data(),
            Optional<String>.none
        )
        try await appender.append(
            Int32(2),
            "Olga",
            Data([0x01, 0x02]),
            Optional("present")
        )
    }

    let result = try await connection.query(
        SwifQL
            .select(
                table.column("id"),
                table.column("name"),
                table.column("payload"),
                table.column("note")
            )
            .from(table)
            .orderBy(.asc(table.column("id")))
    )

    #expect(result.rows.count == 2)
    let first = try #require(result.rows.first)
    let second = try #require(result.rows.last)
    #expect(first["id"] == .int32(1))
    #expect(first["name"] == .string("Mike"))
    #expect(first["payload"] == .blob(Data()))
    #expect(first["note"] == .null)
    #expect(second["id"] == .int32(2))
    #expect(second["name"] == .string("Olga"))
    #expect(second["payload"] == .blob(Data([0x01, 0x02])))
    #expect(second["note"] == .string("present"))
}

@Test("Scoped Appender accepts a schema-qualified target")
func scopedAppenderWritesSchemaTarget() async throws {
    let connection = try Database().connect()
    _ = try await connection.execute(SwifQL.raw("CREATE SCHEMA appender_public_schema"))
    _ = try await connection.execute(
        SwifQL.raw("CREATE TABLE appender_public_schema.events (id INTEGER)")
    )

    let table = Path.SchemaWithTable(
        schema: "appender_public_schema",
        table: "events"
    )
    try await connection.appender(to: table) { appender in
        try await appender.append(Int32(7))
    }

    let result = try await connection.query(
        SwifQL.raw("SELECT id FROM appender_public_schema.events")
    )
    #expect(result.rows.count == 1)
    #expect(result.rows.first?["id"] == .int32(7))
}

@Test("Scoped Appender accepts a catalog and schema-qualified target")
func scopedAppenderWritesCatalogTarget() async throws {
    let connection = try Database().connect()
    let catalogResult = try await connection.query(
        SwifQL.raw("SELECT current_database() AS catalog")
    )
    let catalogRow = try #require(catalogResult.rows.first)
    let catalogValue = try #require(catalogRow["catalog"])
    guard case .string(let catalog) = catalogValue else {
        Issue.record("Expected current_database() to return a String.")
        return
    }

    _ = try await connection.execute(SwifQL.raw("CREATE SCHEMA appender_catalog_schema"))
    _ = try await connection.execute(
        SwifQL.raw("CREATE TABLE appender_catalog_schema.events (id INTEGER)")
    )

    let table = Path.CatalogWithSchemaAndTable(
        catalog: catalog,
        schema: "appender_catalog_schema",
        table: "events"
    )
    try await connection.appender(to: table) { appender in
        try await appender.append(Int32(8))
    }

    let result = try await connection.query(
        SwifQL.raw("SELECT id FROM appender_catalog_schema.events")
    )
    #expect(result.rows.count == 1)
    #expect(result.rows.first?["id"] == .int32(8))
}

@Test("Appender create failure releases ordinary admission")
func appenderCreateFailureReleasesOrdinaryAdmission() async throws {
    let connection = try Database().connect()

    do {
        try await connection.appender(to: Path.Table("missing_public_appender_table")) { _ in }
        Issue.record("Expected missing-table Appender creation to fail.")
    } catch let error as DatabaseError {
        guard case .appenderCreation(let message) = error else {
            Issue.record("Expected appenderCreation, got \(error).")
            return
        }
        #expect(!message.isEmpty)
    }

    let result = try await connection.query(SwifQL.select(Int32(11) => "value"))
    #expect(result.rows.first?["value"] == .int32(11))
}

@Test("Post-admission Appender cancellation releases ordinary admission")
func postAdmissionAppenderCancellationReleasesOrdinaryAdmission() async throws {
    let connection = try Database().connect()
    let table = Path.Table("appender_cancelled_setup")
    try await connection.execute(
        SwifQL
            .create
            .table[any: table]
            .tableDefinitions(NewColumn("id", .integer))
    )

    let task = Task { () throws -> AppenderScopeStart in
        withUnsafeCurrentTask { currentTask in
            currentTask?.cancel()
        }
        return try await connection.acquireAndInstallAppenderScope(
            AppenderTarget(catalog: nil, schema: nil, table: table.name)
        )
    }

    do {
        let unexpectedStart = try await task.value
        _ = await connection.abortAppenderScope(unexpectedStart.id)
        Issue.record("Expected post-admission cancellation to reject Appender setup.")
    } catch is CancellationError {
        // Expected.
    }

    let result = try await connection.query(SwifQL.select(Int32(12) => "value"))
    #expect(result.rows.first?["value"] == .int32(12))
}

@Test("Escaped Appender rejects use after scope end")
func escapedAppenderRejectsAfterScopeEnd() async throws {
    let connection = try Database().connect()
    let table = Path.Table("appender_escaped_scope")
    try await connection.execute(
        SwifQL
            .create
            .table[any: table]
            .tableDefinitions(NewColumn("id", .integer))
    )

    var escaped: Appender?
    try await connection.appender(to: table) { appender in
        escaped = appender
        try await appender.append(Int32(1))
    }

    do {
        try await escaped?.append(Int32(2))
        Issue.record("Expected escaped Appender use to fail after scope end.")
    } catch let error as DatabaseError {
        #expect(error == .appenderEnded)
    }
}

@Test("Appender body rejects inherited same-Connection outer operations")
func appenderBodyRejectsSameConnectionOuterOperations() async throws {
    let connection = try Database().connect()
    let table = Path.Table("appender_scope_guards")
    try await connection.execute(
        SwifQL
            .create
            .table[any: table]
            .tableDefinitions(NewColumn("id", .integer))
    )
    let statement = try await connection.prepare(SwifQL.select(Int32(1) => "value"))

    try await connection.appender(to: table) { appender in
        await expectAppenderScopeViolation {
            _ = try await connection.query(SwifQL.select(Int32(1) => "value"))
        }
        await expectAppenderScopeViolation {
            _ = try await connection.execute(SwifQL.select(Int32(1) => "value"))
        }
        await expectAppenderScopeViolation {
            _ = try await connection.prepare(SwifQL.select(Int32(1) => "value"))
        }
        await expectAppenderScopeViolation {
            _ = try await connection.prepare { parameters in
                SwifQL.select(Fn.cast(parameters.parameter(), .integer) => "value")
            }
        }
        await expectAppenderScopeViolation {
            _ = try await statement.query()
        }
        await expectAppenderScopeViolation {
            _ = try await statement.execute()
        }
        await expectAppenderScopeViolation {
            _ = try await connection.transaction { _ in UInt64(0) }
        }
        await expectAppenderScopeViolation {
            try await connection.appender(to: table) { _ in }
        }

        try await appender.append(Int32(1))
    }

    let result = try await connection.query(
        SwifQL.select(table.column("id")).from(table)
    )
    #expect(result.rows.count == 1)
}

@Test("Appender is rejected from a live same-Connection transaction body")
func appenderRejectsLiveTransactionBody() async throws {
    let connection = try Database().connect()
    let table = Path.Table("appender_transaction_exclusion")
    try await connection.execute(
        SwifQL
            .create
            .table[any: table]
            .tableDefinitions(NewColumn("id", .integer))
    )

    try await connection.transaction { _ in
        do {
            try await connection.appender(to: table) { _ in }
            Issue.record("Expected Appender creation inside Transaction body to fail.")
        } catch let error as DatabaseError {
            #expect(error == .transactionScopeViolation)
        }
    }
}

@Test("Appender scope permits independent work on another Connection")
func appenderScopePermitsDifferentConnectionWork() async throws {
    let database = try Database()
    let appenderConnection = try database.connect()
    let independentConnection = try database.connect()
    let table = Path.Table("appender_other_connection")
    try await appenderConnection.execute(
        SwifQL
            .create
            .table[any: table]
            .tableDefinitions(NewColumn("id", .integer))
    )

    try await appenderConnection.appender(to: table) { appender in
        let independent = try await independentConnection.query(
            SwifQL.select(Int32(21) => "value")
        )
        #expect(independent.rows.first?["value"] == .int32(21))
        try await appender.append(Int32(1))
    }
}

@Test("Caller-local Appender row validation remains recoverable")
func appenderCallerValidationRemainsRecoverable() async throws {
    let connection = try Database().connect()
    let table = Path.Table("appender_caller_validation")
    try await connection.execute(
        SwifQL
            .create
            .table[any: table]
            .tableDefinitions(
                NewColumn("id", .integer),
                NewColumn("name", .text)
            )
    )

    try await connection.appender(to: table) { appender in
        do {
            try await appender.append(Int32(1))
            Issue.record("Expected Appender argument-count validation to fail.")
        } catch let error as DatabaseError {
            #expect(error == .appenderArgumentCount(expected: 2, actual: 1))
        }

        do {
            try await appender.append(Int32(1), UnsupportedAppenderValue())
            Issue.record("Expected unsupported Appender argument type to fail.")
        } catch let error as DatabaseError {
            guard case .unsupportedBindingType = error else {
                Issue.record("Expected unsupportedBindingType, got \(error).")
                return
            }
        }

        try await appender.append(Int32(1), "valid")
    }

    let result = try await connection.query(
        SwifQL.select(table.column("id"), table.column("name")).from(table)
    )
    #expect(result.rows.count == 1)
    #expect(result.rows.first?["id"] == .int32(1))
    #expect(result.rows.first?["name"] == .string("valid"))
}

@Test("Caught terminal native Appender error cannot make the scope succeed")
func caughtTerminalAppenderErrorCannotFalseSucceed() async throws {
    let connection = try Database().connect()
    let table = Path.Table("appender_terminal_error")
    try await connection.execute(
        SwifQL
            .create
            .table[any: table]
            .tableDefinitions(NewColumn("id", .integer))
    )

    var caughtInsideBody: DatabaseError?
    do {
        try await connection.appender(to: table) { appender in
            do {
                try await appender.append("not-an-integer")
                Issue.record("Expected native Appender type failure.")
            } catch let error as DatabaseError {
                caughtInsideBody = error
            }
        }
        Issue.record("Expected terminal Appender failure to fail scope finalization.")
    } catch let error as DatabaseError {
        guard case .appenderAppend(let column, let message) = error else {
            Issue.record("Expected appenderAppend, got \(error).")
            return
        }
        #expect(column == 1)
        #expect(!message.isEmpty)
        #expect(caughtInsideBody == error)
    }

    let result = try await connection.query(
        SwifQL.select(table.column("id")).from(table)
    )
    #expect(result.rows.isEmpty)
}

@Test("Appender finalization failure remains local to the scope")
func appenderFinalizationFailureLeavesConnectionUsable() async throws {
    let connection = try Database().connect()
    let table = Path.Table("appender_finalization_error")
    try await connection.execute(
        SwifQL
            .create
            .table[any: table]
            .tableDefinitions(NewColumn("id", .integer).primaryKey())
    )
    _ = try await connection.execute(
        SwifQL.insertInto(table, fields: "id").values.values(Int32(1))
    )

    do {
        try await connection.appender(to: table) { appender in
            try await appender.append(Int32(1))
        }
        Issue.record("Expected duplicate-key Appender finalization to fail.")
    } catch let error as DatabaseError {
        guard case .appenderFinalization(let message) = error else {
            Issue.record("Expected appenderFinalization, got \(error).")
            return
        }
        #expect(!message.isEmpty)
    }

    let result = try await connection.query(
        SwifQL.select(table.column("id")).from(table)
    )
    #expect(result.rows.count == 1)
}

@Test("Appender body error discards buffered rows and releases its scope")
func appenderBodyErrorDiscardsBufferedRows() async throws {
    let connection = try Database().connect()
    let table = Path.Table("appender_body_error")
    try await connection.execute(
        SwifQL
            .create
            .table[any: table]
            .tableDefinitions(NewColumn("id", .integer))
    )

    do {
        try await connection.appender(to: table) { appender in
            try await appender.append(Int32(1))
            throw AppenderBodyTestError.stop
        }
        Issue.record("Expected Appender body error to escape the scope.")
    } catch is AppenderBodyTestError {
        // Expected.
    }

    let result = try await connection.query(
        SwifQL.select(table.column("id")).from(table)
    )
    #expect(result.rows.isEmpty)
}

private func expectAppenderScopeViolation(
    _ operation: () async throws -> Void
) async {
    do {
        try await operation()
        Issue.record("Expected appenderScopeViolation.")
    } catch let error as DatabaseError {
        #expect(error == .appenderScopeViolation)
    } catch {
        Issue.record("Expected DatabaseError.appenderScopeViolation, got \(error).")
    }
}
