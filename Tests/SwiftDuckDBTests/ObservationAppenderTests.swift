@testable import SwiftDuckDB
import Foundation
import SQL
import Testing

private let ordinaryThreshold = 204_800
private let ordinaryThresholdPlusRemainder = 204_801
private let transactionVisibilityRowCount = 205_000

private enum ObservationAppenderBodyError: Error, Equatable, Sendable {
    case stop
}

private struct ObservationAppenderContext {
    let database: Database
    let connection: Connection
    let table: Path.Table
}

private func uniqueTableName(_ prefix: String) -> String {
    prefix + "_" + UUID().uuidString.replacingOccurrences(of: "-", with: "")
}

private func makeAppenderContext(
    prefix: String,
    columns: [NewColumn] = [NewColumn("id", .integer)]
) async throws -> ObservationAppenderContext {
    let database = try Database()
    let connection = try database.connect()
    let table = Path.Table(uniqueTableName(prefix))
    try await connection.execute(
        SQL
            .create
            .table[any: table]
            .tableDefinitions(columns)
    )
    return ObservationAppenderContext(
        database: database,
        connection: connection,
        table: table
    )
}

private func rowCount(
    from table: Path.Table,
    on connection: Connection
) async throws -> Int64 {
    let result = try await connection.query(
        SQL.select(Fn.count(table.column("id")) => "count").from(table)
    )
    let row = try #require(result.rows.first)
    let value = try #require(row["count"])
    return try #require(value.get(Int64.self))
}

private func safeTableName(
    _ components: [String],
    sourceLocation: SourceLocation = #_sourceLocation
) throws -> ObservationTableName {
    try #require(
        ObservationTableName(components: components),
        "Expected safe ObservationTableName components \(components).",
        sourceLocation: sourceLocation
    )
}

private func appendRows(
    _ appender: Appender,
    count: Int,
    start: Int = 0
) async throws {
    for index in start..<(start + count) {
        try await appender.append(Int32(index))
    }
}

private func drainSignals(
    _ database: Database,
    operation: () async throws -> Void
) async throws -> Int {
    let registration = await database.observationCoordinator.register(initial: .database)
    var iterator = registration.invalidations.makeAsyncIterator()
    let outcome: Result<Void, Error>
    do {
        try await operation()
        outcome = .success(())
    } catch {
        outcome = .failure(error)
    }
    await database.observationCoordinator.unregister(registration.id)

    var count = 0
    while await iterator.next() != nil {
        count += 1
    }
    try outcome.get()
    return count
}

/// Unregisters first so a zero-signal assertion never blocks on a live stream.
private func drainAfterUnregister(
    _ database: Database,
    registrationID: ObservationSubscriptionID,
    iterator: inout AsyncStream<Void>.Iterator
) async -> Int {
    await database.observationCoordinator.unregister(registrationID)
    var count = 0
    while await iterator.next() != nil {
        count += 1
    }
    return count
}

private func currentCatalog(
    on connection: Connection,
    sourceLocation: SourceLocation = #_sourceLocation
) async throws -> String {
    let result = try await connection.query(
        SQL.select(Fn.build(.custom("current_database"), body: []) => "catalog")
    )
    let row = try #require(result.rows.first, sourceLocation: sourceLocation)
    let value = try #require(row["catalog"], sourceLocation: sourceLocation)
    return try #require(value.get(String.self), sourceLocation: sourceLocation)
}

private func fullyQualifiedTarget(
    catalog: String,
    schema: String = "main",
    table: String
) -> Path.CatalogWithSchemaAndTable {
    Path.CatalogWithSchemaAndTable(catalog: catalog, schema: schema, table: table)
}

/// Flips ASCII letter case so a safe identifier spelling is guaranteed to differ from the source.
private func flippedASCIICase(_ value: String) -> String {
    String(decoding: value.utf8.map { byte in
        if byte >= 65 && byte <= 90 {
            return byte + 32
        }
        if byte >= 97 && byte <= 122 {
            return byte - 32
        }
        return byte
    }, as: UTF8.self)
}

private func qualificationClosureDependency(
    catalog: String,
    schema: String = "main",
    table: String,
    sourceLocation: SourceLocation = #_sourceLocation
) throws -> ObservationDependency {
    .tables([
        try safeTableName([catalog, schema, table], sourceLocation: sourceLocation),
        try safeTableName([schema, table], sourceLocation: sourceLocation),
        try safeTableName([table], sourceLocation: sourceLocation),
    ])
}

@Suite(.serialized)
struct ObservationAppenderTests {
    @Test("OA01 small ordinary live body is invisible and publishes nothing")
    func oa01SmallOrdinaryLiveBodyPublishesNothing() async throws {
        let context = try await makeAppenderContext(prefix: "oa01")
        let independent = try context.database.connect()
        let dependency = ObservationDependency.tables(
            [try safeTableName([context.table.name])]
        )
        let registration = await context.database.observationCoordinator.register(
            initial: dependency
        )
        var iterator = registration.invalidations.makeAsyncIterator()

        try await context.connection.appender(to: context.table) { appender in
            try await appender.append(Int32(1))
            #expect(
                try await rowCount(from: context.table, on: independent) == 0
            )
            await context.database.observationCoordinator.unregister(
                registration.id
            )
        }

        var count = 0
        while await iterator.next() != nil {
            count += 1
        }
        #expect(count == 0)
        #expect(try await rowCount(from: context.table, on: context.connection) == 1)
    }

    @Test("OA02 partial Path.Table and Path.SchemaWithTable close fall back Database-wide")
    func oa02PartialTargetsClosePublishDatabaseFallback() async throws {
        let context = try await makeAppenderContext(prefix: "oa02")
        let pathTableRegistration = await context.database.observationCoordinator.register(
            initial: .tables([])
        )

        try await context.connection.appender(to: context.table) { appender in
            try await appendRows(appender, count: 8)
        }

        var pathTableIterator = pathTableRegistration.invalidations.makeAsyncIterator()
        let pathTableCount = await drainAfterUnregister(
            context.database,
            registrationID: pathTableRegistration.id,
            iterator: &pathTableIterator
        )
        #expect(pathTableCount == 1)
        #expect(try await rowCount(from: context.table, on: context.connection) == 8)

        let schema = "main"
        let schemaTable = Path.SchemaWithTable(schema: schema, table: uniqueTableName("oa02_schema"))
        try await context.connection.execute(
            SQL
                .create
                .table[any: schemaTable]
                .tableDefinitions(NewColumn("id", .integer))
        )
        let schemaRegistration = await context.database.observationCoordinator.register(
            initial: .tables([])
        )
        try await context.connection.appender(to: schemaTable) { appender in
            try await appender.append(Int32(1))
        }
        var schemaIterator = schemaRegistration.invalidations.makeAsyncIterator()
        let schemaCount = await drainAfterUnregister(
            context.database,
            registrationID: schemaRegistration.id,
            iterator: &schemaIterator
        )
        #expect(schemaCount == 1)
    }

    @Test("OA03 small ordinary body error discards with zero publication")
    func oa03SmallOrdinaryBodyErrorPublishesNothing() async throws {
        let context = try await makeAppenderContext(prefix: "oa03")
        let independent = try context.database.connect()
        let dependency = ObservationDependency.tables(
            [try safeTableName([context.table.name])]
        )
        let registration = await context.database.observationCoordinator.register(
            initial: dependency
        )

        do {
            try await context.connection.appender(to: context.table) { appender in
                try await appendRows(appender, count: 5)
                throw ObservationAppenderBodyError.stop
            }
            Issue.record("Expected the ordinary Appender body error.")
        } catch is ObservationAppenderBodyError {
            // Expected.
        }

        var iterator = registration.invalidations.makeAsyncIterator()
        let count = await drainAfterUnregister(
            context.database,
            registrationID: registration.id,
            iterator: &iterator
        )
        #expect(count == 0)
        #expect(try await rowCount(from: context.table, on: independent) == 0)
    }

    @Test("OA04 exact 204800 threshold publishes before the body returns")
    func oa04ExactThresholdPublishesBeforeBodyReturns() async throws {
        let context = try await makeAppenderContext(prefix: "oa04")
        let independent = try context.database.connect()
        let dependency = ObservationDependency.tables(
            [try safeTableName([context.table.name])]
        )
        let registration = await context.database.observationCoordinator.register(
            initial: dependency
        )
        var iterator = registration.invalidations.makeAsyncIterator()

        try await context.connection.appender(to: context.table) { appender in
            try await appendRows(appender, count: ordinaryThreshold)
            #expect(await iterator.next() != nil)
            #expect(
                try await rowCount(from: context.table, on: independent)
                    == Int64(ordinaryThreshold)
            )
        }

        await context.database.observationCoordinator.unregister(registration.id)
        var after = 0
        while await iterator.next() != nil {
            after += 1
        }
        #expect(after == 0)
        #expect(
            try await rowCount(from: context.table, on: context.connection)
                == Int64(ordinaryThreshold)
        )
    }

    @Test("OA05 exact 204800 then body error preserves the durable prefix")
    func oa05ExactThresholdBodyErrorPreservesDurablePrefix() async throws {
        let context = try await makeAppenderContext(prefix: "oa05")
        let independent = try context.database.connect()
        let dependency = ObservationDependency.tables(
            [try safeTableName([context.table.name])]
        )
        let registration = await context.database.observationCoordinator.register(
            initial: dependency
        )
        var iterator = registration.invalidations.makeAsyncIterator()

        do {
            try await context.connection.appender(to: context.table) { appender in
                try await appendRows(appender, count: ordinaryThreshold)
                #expect(await iterator.next() != nil)
                throw ObservationAppenderBodyError.stop
            }
            Issue.record("Expected the exact-threshold Appender body error.")
        } catch is ObservationAppenderBodyError {
            // Expected.
        }

        await context.database.observationCoordinator.unregister(registration.id)
        var after = 0
        while await iterator.next() != nil {
            after += 1
        }
        #expect(after == 0)
        #expect(
            try await rowCount(from: context.table, on: independent)
                == Int64(ordinaryThreshold)
        )
    }

    @Test("OA06 204800 plus discarded suffix exposes only the durable prefix")
    func oa06ThresholdSuffixDiscardExposesDurablePrefixOnly() async throws {
        let context = try await makeAppenderContext(prefix: "oa06")
        let independent = try context.database.connect()
        let dependency = ObservationDependency.tables(
            [try safeTableName([context.table.name])]
        )
        let registration = await context.database.observationCoordinator.register(
            initial: dependency
        )
        var iterator = registration.invalidations.makeAsyncIterator()

        do {
            try await context.connection.appender(to: context.table) { appender in
                try await appendRows(appender, count: ordinaryThreshold)
                #expect(await iterator.next() != nil)
                try await appendRows(appender, count: 7, start: ordinaryThreshold)
                throw ObservationAppenderBodyError.stop
            }
            Issue.record("Expected the threshold-plus-suffix Appender body error.")
        } catch is ObservationAppenderBodyError {
            // Expected.
        }

        await context.database.observationCoordinator.unregister(registration.id)
        var after = 0
        while await iterator.next() != nil {
            after += 1
        }
        #expect(after == 0)
        #expect(
            try await rowCount(from: context.table, on: independent)
                == Int64(ordinaryThreshold)
        )
    }

    @Test("OA07 204801 successful close publishes threshold plus remainder")
    func oa07ExactThresholdPlusRemainderClosePublishesOnceMore() async throws {
        let context = try await makeAppenderContext(prefix: "oa07")
        let independent = try context.database.connect()
        let dependency = ObservationDependency.tables(
            [try safeTableName([context.table.name])]
        )
        let registration = await context.database.observationCoordinator.register(
            initial: dependency
        )
        var iterator = registration.invalidations.makeAsyncIterator()

        try await context.connection.appender(to: context.table) { appender in
            try await appendRows(appender, count: ordinaryThreshold)
            #expect(await iterator.next() != nil)
            try await appender.append(Int32(ordinaryThreshold))
        }

        await context.database.observationCoordinator.unregister(registration.id)
        #expect(await iterator.next() != nil)
        #expect(await iterator.next() == nil)
        #expect(
            try await rowCount(from: context.table, on: independent)
                == Int64(ordinaryThresholdPlusRemainder)
        )
    }

    @Test("OA08 fully-qualified target selectivity across two tables")
    func oa08ExactTargetSelectivityAcrossTwoTables() async throws {
        let database = try Database()
        let connection = try database.connect()
        let catalog = try await currentCatalog(on: connection)
        let nameA = uniqueTableName("oa08_a")
        let nameB = uniqueTableName("oa08_b")
        let tableA = Path.Table(nameA)
        let tableB = Path.Table(nameB)
        for table in [tableA, tableB] {
            try await connection.execute(
                SQL
                    .create
                    .table[any: table]
                    .tableDefinitions(NewColumn("id", .integer))
            )
        }
        let targetA = fullyQualifiedTarget(catalog: catalog, table: nameA)

        let registrationA = await database.observationCoordinator.register(
            initial: try qualificationClosureDependency(catalog: catalog, table: nameA)
        )
        let registrationB = await database.observationCoordinator.register(
            initial: try qualificationClosureDependency(catalog: catalog, table: nameB)
        )
        let registrationEmpty = await database.observationCoordinator.register(
            initial: .tables([])
        )

        try await connection.appender(to: targetA) { appender in
            try await appendRows(appender, count: 3)
        }

        var iteratorA = registrationA.invalidations.makeAsyncIterator()
        var iteratorB = registrationB.invalidations.makeAsyncIterator()
        var iteratorEmpty = registrationEmpty.invalidations.makeAsyncIterator()
        let countA = await drainAfterUnregister(
            database,
            registrationID: registrationA.id,
            iterator: &iteratorA
        )
        let countB = await drainAfterUnregister(
            database,
            registrationID: registrationB.id,
            iterator: &iteratorB
        )
        let countEmpty = await drainAfterUnregister(
            database,
            registrationID: registrationEmpty.id,
            iterator: &iteratorEmpty
        )
        #expect(countA == 1)
        #expect(countB == 0)
        #expect(countEmpty == 0)
    }

    @Test("OA09 real QueryObservation mixed-case bare/schema/catalog qualification closure")
    func oa09QueryObservationQualificationClosure() async throws {
        let database = try Database()
        let connection = try database.connect()
        let catalog = "memory"
        let tableName = "Oa09_MiXeD_Table"
        #expect(try await currentCatalog(on: connection) == catalog)
        try await connection.execute(
            SQL
                .create
                .table[any: Path.Table(tableName)]
                .tableDefinitions(NewColumn("id", .integer))
        )
        let target = fullyQualifiedTarget(catalog: catalog, table: tableName)

        #expect(
            ObservationTableName(components: ["a.b"]) == nil,
            "A literal dot inside one component must not re-split."
        )
        #expect(ObservationTableName(components: []) == nil)
        #expect(ObservationTableName(components: ["a", "b", "c", "d"]) == nil)
        #expect(ObservationTableName(components: [""]) == nil)
        #expect(ObservationTableName(components: ["a b"]) == nil)
        #expect(ObservationTableName(components: [#""a""#]) == nil)
        #expect(ObservationTableName(components: [catalog, "main", tableName]) != nil)
        #expect(ObservationTableName(binderName: "\(catalog).main.\(tableName)") != nil)

        let mixedCatalog = try #require(ObservationTableName(components: ["Catalog", "Main", "Users"]))
        let lowerCatalog = try #require(ObservationTableName(components: ["catalog", "main", "users"]))
        let binderCatalog = try #require(ObservationTableName(binderName: "CATALOG.MAIN.USERS"))
        #expect(mixedCatalog == lowerCatalog)
        #expect(mixedCatalog == binderCatalog)
        let mixedDollar = try #require(ObservationTableName(components: ["MiXeD_123$"]))
        let lowerDollar = try #require(ObservationTableName(components: ["mixed_123$"]))
        #expect(mixedDollar == lowerDollar)

        let bareTableSpelling = flippedASCIICase(tableName)
        let schemaSpelling = flippedASCIICase("main")
        let schemaTableSpelling = flippedASCIICase(tableName)
        let catalogSpelling = flippedASCIICase(catalog)
        #expect(bareTableSpelling != tableName)
        #expect(schemaSpelling != "main")
        #expect(schemaTableSpelling != tableName)
        #expect(catalogSpelling != catalog)

        let bareObservation = try database.observe(
            SQL
                .select(Path.Column("id"))
                .from(SQL.raw(bareTableSpelling))
        )
        let schemaObservation = try database.observe(
            SQL
                .select(Path.Column("id"))
                .from(SQL.raw("\(schemaSpelling).\(schemaTableSpelling)"))
        )
        let catalogObservation = try database.observe(
            SQL
                .select(Path.Column("id"))
                .from(
                    SQL.raw(
                        "\(catalogSpelling).\(schemaSpelling).\(schemaTableSpelling)"
                    )
                )
        )
        var bareIterator = bareObservation.makeAsyncIterator()
        var schemaIterator = schemaObservation.makeAsyncIterator()
        var catalogIterator = catalogObservation.makeAsyncIterator()

        let bareInitial = try #require(try await bareIterator.next())
        let schemaInitial = try #require(try await schemaIterator.next())
        let catalogInitial = try #require(try await catalogIterator.next())
        #expect(bareInitial.rows.isEmpty)
        #expect(schemaInitial.rows.isEmpty)
        #expect(catalogInitial.rows.isEmpty)

        try await connection.appender(to: target) { appender in
            try await appender.append(Int32(1))
        }

        let bareChanged = try #require(try await bareIterator.next())
        let schemaChanged = try #require(try await schemaIterator.next())
        let catalogChanged = try #require(try await catalogIterator.next())
        #expect(bareChanged.rows.count == 1)
        #expect(schemaChanged.rows.count == 1)
        #expect(catalogChanged.rows.count == 1)
        #expect(bareChanged.rows.first?["id"] == .int32(1))
        #expect(schemaChanged.rows.first?["id"] == .int32(1))
        #expect(catalogChanged.rows.first?["id"] == .int32(1))
    }

    @Test("OA10 unsafe fully-qualified Appender target falls back Database-wide")
    func oa10UnsafeTargetFallsBackDatabaseWide() async throws {
        let database = try Database()
        let connection = try database.connect()
        let catalog = try await currentCatalog(on: connection)
        let unsafeName = "oa10 unsafe target table"
        let storageTable = Path.Table(unsafeName)
        _ = try await connection.execute(
            SQL
                .create
                .table[any: storageTable]
                .tableDefinitions(NewColumn("id", .integer))
        )
        #expect(ObservationTableName(components: [catalog, "main", unsafeName]) == nil)

        let table = fullyQualifiedTarget(catalog: catalog, table: unsafeName)
        let registration = await database.observationCoordinator.register(
            initial: .tables([])
        )

        try await connection.appender(to: table) { appender in
            try await appendRows(appender, count: 4)
        }

        var iterator = registration.invalidations.makeAsyncIterator()
        let count = await drainAfterUnregister(
            database,
            registrationID: registration.id,
            iterator: &iterator
        )
        #expect(count == 1)

        let result = try await connection.query(
            SQL
                .select(Fn.cast(Fn.count(SQL.asterisk), .bigint) => "count")
                .from(storageTable)
        )
        let row = try #require(result.rows.first)
        let value = try #require(row["count"])
        #expect(try #require(value.get(Int64.self)) == 4)
    }

    @Test("OA11 ordinary preflight failure publishes nothing and stays recoverable")
    func oa11OrdinaryPreflightFailurePublishesNothing() async throws {
        let context = try await makeAppenderContext(
            prefix: "oa11",
            columns: [
                NewColumn("id", .integer),
                NewColumn("name", .text)
            ]
        )

        let preflightRegistration = await context.database.observationCoordinator
            .register(initial: .tables([try safeTableName([context.table.name])]))
        var caught: DatabaseError?
        try await context.connection.appender(to: context.table) { appender in
            do {
                try await appender.append("not-an-integer", "wrong")
                Issue.record("Expected the deterministic preflight mismatch.")
            } catch let error as DatabaseError {
                caught = error
            }
        }
        var preflightIterator = preflightRegistration.invalidations.makeAsyncIterator()
        let preflightCount = await drainAfterUnregister(
            context.database,
            registrationID: preflightRegistration.id,
            iterator: &preflightIterator
        )
        #expect(preflightCount == 0)
        guard case .appenderAppend = try #require(caught) else {
            Issue.record(
                "Expected appenderAppend preflight, got \(String(describing: caught))."
            )
            return
        }

        let recoveryRegistration = await context.database.observationCoordinator
            .register(initial: .tables([try safeTableName([context.table.name])]))
        try await context.connection.appender(to: context.table) { appender in
            try await appender.append(Int32(1), "valid")
        }
        var recoveryIterator = recoveryRegistration.invalidations.makeAsyncIterator()
        let recoveryCount = await drainAfterUnregister(
            context.database,
            registrationID: recoveryRegistration.id,
            iterator: &recoveryIterator
        )
        #expect(recoveryCount == 1)
        #expect(try await rowCount(from: context.table, on: context.connection) == 1)
    }

    @Test("OA12 ordinary non-preflight threshold row failure publishes conservatively")
    func oa12OrdinaryThresholdRowFailurePublishesConservatively() async throws {
        let database = try Database()
        let connection = try database.connect()
        let table = Path.Table(uniqueTableName("oa12"))
        _ = try await connection.execute(
            SQL
                .create
                .table[any: table]
                .tableDefinitions(
                    NewColumn("id", .integer)
                        .check(
                        Path.Column("id") >= SQLableParts(
                            parts: SQLPartSafeValue(Int32(0))
                        )
                    )
                )
        )

        let registration = await database.observationCoordinator.register(
            initial: .tables([try safeTableName([table.name])])
        )

        var firstTerminalError: DatabaseError?
        var failureIndex: Int?
        do {
            try await connection.appender(to: table) { appender in
                for index in 0..<ordinaryThreshold {
                    let value = Int32(index == 0 ? -1 : 1)
                    do {
                        try await appender.append(value)
                    } catch let error as DatabaseError {
                        firstTerminalError = error
                        failureIndex = index
                        break
                    }
                }

                let terminal = try #require(firstTerminalError)
                guard case .appenderRowCompletion(let message) = terminal else {
                    Issue.record("Expected appenderRowCompletion, got \(terminal).")
                    return
                }
                #expect(!message.isEmpty)
                #expect(failureIndex == ordinaryThreshold - 1)
            }
            Issue.record(
                "Expected threshold row-completion failure to escape finalization."
            )
        } catch let error as DatabaseError {
            let terminal = try #require(firstTerminalError)
            #expect(error == terminal)
        }

        var iterator = registration.invalidations.makeAsyncIterator()
        let count = await drainAfterUnregister(
            database,
            registrationID: registration.id,
            iterator: &iterator
        )
        #expect(count == 1)

        guard case .appenderRowCompletion = try #require(firstTerminalError) else {
            Issue.record("Expected authoritative appenderRowCompletion truth.")
            return
        }
        #expect(failureIndex == ordinaryThreshold - 1)
        #expect(try await rowCount(from: table, on: connection) == 0)

        let reused = try await connection.query(
            SQL.select(Fn.cast(Int32(42), .integer) => "value")
        )
        #expect(reused.rows.first?["value"] == .int32(42))
    }

    @Test("OA13 ordinary finalization failure publishes conservatively")
    func oa13OrdinaryFinalizationFailurePublishesConservatively() async throws {
        let database = try Database()
        let connection = try database.connect()
        let table = Path.Table(uniqueTableName("oa13"))
        try await connection.execute(
            SQL
                .create
                .table[any: table]
                .tableDefinitions(NewColumn("id", .integer).primaryKey())
        )
        _ = try await connection.execute(
            SQL.insertInto(table, fields: "id").values.values(Int32(1))
        )

        let registration = await database.observationCoordinator.register(
            initial: .tables([try safeTableName([table.name])])
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

        var iterator = registration.invalidations.makeAsyncIterator()
        let count = await drainAfterUnregister(
            database,
            registrationID: registration.id,
            iterator: &iterator
        )
        #expect(count == 1)
        #expect(try await rowCount(from: table, on: connection) == 1)

        let result = try await connection.query(
            SQL.select(Fn.cast(Int32(7), .integer) => "value")
        )
        #expect(result.rows.first?["value"] == .int32(7))
    }

    @Test("OA14 table-scoped Appender invalidation refreshes a .database observer")
    func oa14ExactTargetRefreshesDatabaseDependencyObserver() async throws {
        let context = try await makeAppenderContext(prefix: "oa14")
        let catalog = try await currentCatalog(on: context.connection)
        let target = fullyQualifiedTarget(catalog: catalog, table: context.table.name)

        let analysisDatabase = try NativeDatabase()
        let analysisConnection = try analysisDatabase.connect()
        try executeNative(
            SQL
                .create
                .table[any: context.table]
                .tableDefinitions(
                    NewColumn("id", .integer),
                    NewColumn("value", .integer)
                )
                .prepare(.duck)
                .plain,
            on: analysisConnection
        )
        let aliasQuery = SQL
            .select(SQL.asterisk)
            .from(context.table.as(TableAlias("a")))
        let aliasSQL = aliasQuery.prepare(.duck).plain
        #expect(
            ObservationDependency.analyze(sql: aliasSQL, on: analysisConnection)
                == .database
        )

        let observation = try context.database.observe(aliasQuery)
        var iterator = observation.makeAsyncIterator()
        let initial = try #require(try await iterator.next())
        #expect(initial.rows.isEmpty)

        try await context.connection.appender(to: target) { appender in
            try await appender.append(Int32(1))
        }

        let changed = try #require(try await iterator.next())
        #expect(changed.rows.count == 1)
        #expect(changed.rows.first?["id"] == .int32(1))
    }

    @Test("OA15 205000 flat Transaction Appender has no precommit publication")
    func oa15TransactionAppenderHasNoPrecommitPublication() async throws {
        let context = try await makeAppenderContext(prefix: "oa15")
        let independent = try context.database.connect()
        let registration = await context.database.observationCoordinator.register(
            initial: .database
        )

        let transaction = try await context.connection.transaction()
        try await transaction.appender(to: context.table) { appender in
            try await appendRows(appender, count: transactionVisibilityRowCount)
        }

        #expect(try await rowCount(from: context.table, on: independent) == 0)
        var iterator = registration.invalidations.makeAsyncIterator()
        let preFinalization = await drainAfterUnregister(
            context.database,
            registrationID: registration.id,
            iterator: &iterator
        )
        #expect(preFinalization == 0)

        try await transaction.rollback()
        #expect(try await rowCount(from: context.table, on: independent) == 0)
    }

    @Test("OA16 205000 flat Transaction Appender COMMIT publishes fully-qualified target")
    func oa16TransactionAppenderCommitPublishesExactTarget() async throws {
        let context = try await makeAppenderContext(prefix: "oa16")
        let independent = try context.database.connect()
        let catalog = try await currentCatalog(on: context.connection)
        let otherName = uniqueTableName("oa16_other")
        let otherTable = Path.Table(otherName)
        try await independent.execute(
            SQL
                .create
                .table[any: otherTable]
                .tableDefinitions(NewColumn("id", .integer))
        )
        let target = fullyQualifiedTarget(catalog: catalog, table: context.table.name)

        let scopeRegistration = await context.database.observationCoordinator
            .register(initial: .database)
        let transaction = try await context.connection.transaction()
        try await transaction.appender(to: target) { appender in
            try await appendRows(appender, count: transactionVisibilityRowCount)
        }
        #expect(try await rowCount(from: context.table, on: independent) == 0)
        var scopeIterator = scopeRegistration.invalidations.makeAsyncIterator()
        let scopeSignals = await drainAfterUnregister(
            context.database,
            registrationID: scopeRegistration.id,
            iterator: &scopeIterator
        )
        #expect(scopeSignals == 0)

        let registration = await context.database.observationCoordinator.register(
            initial: try qualificationClosureDependency(
                catalog: catalog,
                table: context.table.name
            )
        )
        let registrationOther = await context.database.observationCoordinator.register(
            initial: try qualificationClosureDependency(catalog: catalog, table: otherName)
        )
        let registrationEmpty = await context.database.observationCoordinator.register(
            initial: .tables([])
        )

        try await transaction.commit()

        var iterator = registration.invalidations.makeAsyncIterator()
        var iteratorOther = registrationOther.invalidations.makeAsyncIterator()
        var iteratorEmpty = registrationEmpty.invalidations.makeAsyncIterator()
        let count = await drainAfterUnregister(
            context.database,
            registrationID: registration.id,
            iterator: &iterator
        )
        let countOther = await drainAfterUnregister(
            context.database,
            registrationID: registrationOther.id,
            iterator: &iteratorOther
        )
        let countEmpty = await drainAfterUnregister(
            context.database,
            registrationID: registrationEmpty.id,
            iterator: &iteratorEmpty
        )
        #expect(count == 1)
        #expect(countOther == 0)
        #expect(countEmpty == 0)
        #expect(
            try await rowCount(from: context.table, on: independent)
                == Int64(transactionVisibilityRowCount)
        )
    }

    @Test("OA17 205000 flat Transaction Appender ROLLBACK publishes fully-qualified target")
    func oa17TransactionAppenderRollbackPublishesExactTarget() async throws {
        let context = try await makeAppenderContext(prefix: "oa17")
        let independent = try context.database.connect()
        let catalog = try await currentCatalog(on: context.connection)
        let target = fullyQualifiedTarget(catalog: catalog, table: context.table.name)

        let scopeRegistration = await context.database.observationCoordinator
            .register(initial: .database)
        let transaction = try await context.connection.transaction()
        try await transaction.appender(to: target) { appender in
            try await appendRows(appender, count: transactionVisibilityRowCount)
        }
        #expect(try await rowCount(from: context.table, on: independent) == 0)
        var scopeIterator = scopeRegistration.invalidations.makeAsyncIterator()
        let scopeSignals = await drainAfterUnregister(
            context.database,
            registrationID: scopeRegistration.id,
            iterator: &scopeIterator
        )
        #expect(scopeSignals == 0)

        let registration = await context.database.observationCoordinator.register(
            initial: try qualificationClosureDependency(
                catalog: catalog,
                table: context.table.name
            )
        )
        try await transaction.rollback()

        var iterator = registration.invalidations.makeAsyncIterator()
        let count = await drainAfterUnregister(
            context.database,
            registrationID: registration.id,
            iterator: &iterator
        )
        #expect(count == 1)
        #expect(try await rowCount(from: context.table, on: independent) == 0)
    }

    @Test("OA18 managed automatic rollback after successful Transaction Appender scope")
    func oa18ManagedAutomaticRollbackAfterSuccessfulTransactionAppender() async throws {
        let context = try await makeAppenderContext(prefix: "oa18")
        let registration = await context.database.observationCoordinator.register(
            initial: .tables([try safeTableName([context.table.name])])
        )

        do {
            try await context.connection.transaction { transaction in
                try await transaction.appender(to: context.table) { appender in
                    try await appendRows(appender, count: 6)
                }
                throw ObservationAppenderBodyError.stop
            }
            Issue.record("Expected the managed outer body error.")
        } catch is ObservationAppenderBodyError {
            // Expected.
        }

        var iterator = registration.invalidations.makeAsyncIterator()
        let count = await drainAfterUnregister(
            context.database,
            registrationID: registration.id,
            iterator: &iterator
        )
        #expect(count == 1)
        #expect(try await rowCount(from: context.table, on: context.connection) == 0)
    }

    @Test("OA19 Transaction Appender body error does not merge target")
    func oa19TransactionAppenderBodyErrorDoesNotMergeTarget() async throws {
        let context = try await makeAppenderContext(prefix: "oa19")
        let failure = ObservationAppenderBodyError.stop
        let expected = DatabaseError.appenderTransactionAborted(
            String(describing: failure)
        )

        let count = try await drainSignals(context.database) {
            do {
                try await context.connection.transaction { transaction in
                    try await transaction.appender(to: context.table) { appender in
                        try await appendRows(
                            appender,
                            count: transactionVisibilityRowCount
                        )
                        throw failure
                    }
                    Issue.record("Expected the Transaction Appender body error.")
                }
                Issue.record(
                    "Expected rollback-only Transaction Appender state to reject COMMIT."
                )
            } catch let error as DatabaseError {
                #expect(error == expected)
            } catch is ObservationAppenderBodyError {
                // Also valid when the original body error remains authoritative.
            }
        }

        #expect(count == 0)
        #expect(try await rowCount(from: context.table, on: context.connection) == 0)
    }

    @Test("OA20 transaction fully-qualified target selectivity on COMMIT")
    func oa20TransactionExactTargetSelectivityOnCommit() async throws {
        let database = try Database()
        let connection = try database.connect()
        let catalog = try await currentCatalog(on: connection)
        let nameA = uniqueTableName("oa20_a")
        let nameB = uniqueTableName("oa20_b")
        for name in [nameA, nameB] {
            try await connection.execute(
                SQL
                    .create
                    .table[any: Path.Table(name)]
                    .tableDefinitions(NewColumn("id", .integer))
            )
        }
        let targetA = fullyQualifiedTarget(catalog: catalog, table: nameA)

        let registrationA = await database.observationCoordinator.register(
            initial: try qualificationClosureDependency(catalog: catalog, table: nameA)
        )
        let registrationB = await database.observationCoordinator.register(
            initial: try qualificationClosureDependency(catalog: catalog, table: nameB)
        )
        let registrationEmpty = await database.observationCoordinator.register(
            initial: .tables([])
        )

        let transaction = try await connection.transaction()
        try await transaction.appender(to: targetA) { appender in
            try await appendRows(appender, count: 4)
        }
        try await transaction.commit()

        var iteratorA = registrationA.invalidations.makeAsyncIterator()
        var iteratorB = registrationB.invalidations.makeAsyncIterator()
        var iteratorEmpty = registrationEmpty.invalidations.makeAsyncIterator()
        let countA = await drainAfterUnregister(
            database,
            registrationID: registrationA.id,
            iterator: &iteratorA
        )
        let countB = await drainAfterUnregister(
            database,
            registrationID: registrationB.id,
            iterator: &iteratorB
        )
        let countEmpty = await drainAfterUnregister(
            database,
            registrationID: registrationEmpty.id,
            iterator: &iteratorEmpty
        )
        #expect(countA == 1)
        #expect(countB == 0)
        #expect(countEmpty == 0)
    }

    @Test("OA21 multiple fully-qualified Transaction Appender targets merge")
    func oa21MultipleTransactionAppenderTargetsMerge() async throws {
        let database = try Database()
        let connection = try database.connect()
        let catalog = try await currentCatalog(on: connection)
        let nameA = uniqueTableName("oa21_a")
        let nameB = uniqueTableName("oa21_b")
        let tableA = Path.Table(nameA)
        let tableB = Path.Table(nameB)
        for table in [tableA, tableB] {
            try await connection.execute(
                SQL
                    .create
                    .table[any: table]
                    .tableDefinitions(NewColumn("id", .integer))
            )
        }
        let targetA = fullyQualifiedTarget(catalog: catalog, table: nameA)
        let targetB = fullyQualifiedTarget(catalog: catalog, table: nameB)

        let registrationA = await database.observationCoordinator.register(
            initial: try qualificationClosureDependency(catalog: catalog, table: nameA)
        )
        let registrationB = await database.observationCoordinator.register(
            initial: try qualificationClosureDependency(catalog: catalog, table: nameB)
        )
        let registrationEmpty = await database.observationCoordinator.register(
            initial: .tables([])
        )

        let transaction = try await connection.transaction()
        try await transaction.appender(to: targetA) { appender in
            try await appendRows(appender, count: 3)
        }
        try await transaction.appender(to: targetB) { appender in
            try await appendRows(appender, count: 3)
        }
        try await transaction.commit()

        var iteratorA = registrationA.invalidations.makeAsyncIterator()
        var iteratorB = registrationB.invalidations.makeAsyncIterator()
        var iteratorEmpty = registrationEmpty.invalidations.makeAsyncIterator()
        let countA = await drainAfterUnregister(
            database,
            registrationID: registrationA.id,
            iterator: &iteratorA
        )
        let countB = await drainAfterUnregister(
            database,
            registrationID: registrationB.id,
            iterator: &iteratorB
        )
        let countEmpty = await drainAfterUnregister(
            database,
            registrationID: registrationEmpty.id,
            iterator: &iteratorEmpty
        )
        #expect(countA == 1)
        #expect(countB == 1)
        #expect(countEmpty == 0)
        #expect(try await rowCount(from: tableA, on: connection) == 3)
        #expect(try await rowCount(from: tableB, on: connection) == 3)
    }

    @Test("OA22 unsafe fully-qualified Transaction Appender target falls back Database-wide")
    func oa22UnsafeTransactionAppenderTargetFallsBackDatabaseWide() async throws {
        let database = try Database()
        let connection = try database.connect()
        let catalog = try await currentCatalog(on: connection)
        let unsafeName = "oa22 unsafe target table"
        let storageTable = Path.Table(unsafeName)
        _ = try await connection.execute(
            SQL
                .create
                .table[any: storageTable]
                .tableDefinitions(NewColumn("id", .integer))
        )
        #expect(ObservationTableName(components: [catalog, "main", unsafeName]) == nil)

        let table = fullyQualifiedTarget(catalog: catalog, table: unsafeName)
        let scopeRegistration = await database.observationCoordinator.register(
            initial: .database
        )
        let transaction = try await connection.transaction()
        try await transaction.appender(to: table) { appender in
            try await appendRows(appender, count: 5)
        }
        var scopeIterator = scopeRegistration.invalidations.makeAsyncIterator()
        let scopeSignals = await drainAfterUnregister(
            database,
            registrationID: scopeRegistration.id,
            iterator: &scopeIterator
        )
        #expect(scopeSignals == 0)

        let registration = await database.observationCoordinator.register(
            initial: .tables([])
        )
        try await transaction.commit()

        var iterator = registration.invalidations.makeAsyncIterator()
        let count = await drainAfterUnregister(
            database,
            registrationID: registration.id,
            iterator: &iterator
        )
        #expect(count == 1)

        let result = try await connection.query(
            SQL
                .select(Fn.cast(Fn.count(SQL.asterisk), .bigint) => "count")
                .from(storageTable)
        )
        let row = try #require(result.rows.first)
        let value = try #require(row["count"])
        #expect(try #require(value.get(Int64.self)) == 5)
    }

    @Test("OA23 managed manual finalizers integrate Transaction Appender impact")
    func oa23ManagedManualFinalizersIntegrateAppenderImpact() async throws {
        let commitContext = try await makeAppenderContext(prefix: "oa23_commit")
        let commitRegistration = await commitContext.database.observationCoordinator
            .register(initial: .tables([try safeTableName([commitContext.table.name])]))
        var commitIterator = commitRegistration.invalidations.makeAsyncIterator()

        try await commitContext.connection.transaction { transaction in
            try await transaction.appender(to: commitContext.table) { appender in
                try await appendRows(appender, count: 4)
            }
            try await transaction.commit()
            #expect(await commitIterator.next() != nil)

            do {
                try await transaction.appender(to: commitContext.table) { _ in }
                Issue.record("Expected transactionEnded after manual commit.")
            } catch let error as DatabaseError {
                #expect(error == .transactionEnded)
            }
        }

        let commitDrained = await drainAfterUnregister(
            commitContext.database,
            registrationID: commitRegistration.id,
            iterator: &commitIterator
        )
        #expect(commitDrained == 0)
        #expect(
            try await rowCount(
                from: commitContext.table,
                on: commitContext.connection
            ) == 4
        )

        let rollbackContext = try await makeAppenderContext(prefix: "oa23_rollback")
        let rollbackRegistration = await rollbackContext.database.observationCoordinator
            .register(
                initial: .tables([try safeTableName([rollbackContext.table.name])])
            )
        var rollbackIterator = rollbackRegistration.invalidations.makeAsyncIterator()

        try await rollbackContext.connection.transaction { transaction in
            try await transaction.appender(to: rollbackContext.table) { appender in
                try await appendRows(appender, count: 4)
            }
            try await transaction.rollback()
            #expect(await rollbackIterator.next() != nil)

            do {
                try await transaction.appender(to: rollbackContext.table) { _ in }
                Issue.record("Expected transactionEnded after manual rollback.")
            } catch let error as DatabaseError {
                #expect(error == .transactionEnded)
            }
        }

        let rollbackDrained = await drainAfterUnregister(
            rollbackContext.database,
            registrationID: rollbackRegistration.id,
            iterator: &rollbackIterator
        )
        #expect(rollbackDrained == 0)
        #expect(
            try await rowCount(
                from: rollbackContext.table,
                on: rollbackContext.connection
            ) == 0
        )
    }

    @Test("OA24 Appender publication remains Database-local")
    func oa24AppenderPublicationRemainsDatabaseLocal() async throws {
        let first = try await makeAppenderContext(prefix: "oa24_first")
        let secondDatabase = try Database()
        let firstRegistration = await first.database.observationCoordinator.register(
            initial: .database
        )
        let secondRegistration = await secondDatabase.observationCoordinator.register(
            initial: .database
        )

        try await first.connection.appender(to: first.table) { appender in
            try await appendRows(appender, count: 2)
        }

        var firstIterator = firstRegistration.invalidations.makeAsyncIterator()
        var secondIterator = secondRegistration.invalidations.makeAsyncIterator()
        let firstCount = await drainAfterUnregister(
            first.database,
            registrationID: firstRegistration.id,
            iterator: &firstIterator
        )
        let secondCount = await drainAfterUnregister(
            secondDatabase,
            registrationID: secondRegistration.id,
            iterator: &secondIterator
        )
        #expect(firstCount == 1)
        #expect(secondCount == 0)
    }

    #if compiler(>=6.4)
    @Test("S64A01 rollbackIfNeeded publishes completed Transaction Appender target")
    func s64a01RollbackIfNeededPublishesTransactionAppenderTarget() async throws {
        let context = try await makeAppenderContext(prefix: "s64a01")
        let independent = try context.database.connect()
        let catalog = try await currentCatalog(on: context.connection)
        let target = fullyQualifiedTarget(catalog: catalog, table: context.table.name)
        let registration = await context.database.observationCoordinator.register(
            initial: .database
        )

        let transaction = try await context.connection.transaction()
        try await transaction.appender(to: target) { appender in
            try await appendRows(appender, count: 9)
        }
        #expect(try await rowCount(from: context.table, on: independent) == 0)
        var scopeIterator = registration.invalidations.makeAsyncIterator()
        let preSignals = await drainAfterUnregister(
            context.database,
            registrationID: registration.id,
            iterator: &scopeIterator
        )
        #expect(preSignals == 0)

        let commitRegistration = await context.database.observationCoordinator
            .register(
                initial: try qualificationClosureDependency(
                    catalog: catalog,
                    table: context.table.name
                )
            )
        await transaction.rollbackIfNeeded()

        var iterator = commitRegistration.invalidations.makeAsyncIterator()
        let count = await drainAfterUnregister(
            context.database,
            registrationID: commitRegistration.id,
            iterator: &iterator
        )
        #expect(count == 1)
        #expect(try await rowCount(from: context.table, on: independent) == 0)

        let reusable = try await context.connection.query(
            SQL.select(Fn.cast(Int32(11), .integer) => "value")
        )
        #expect(reusable.rows.first?["value"] == .int32(11))
    }
    #endif
}

private func executeNative(_ sql: String, on connection: NativeConnection) throws {
    let statement = try connection.prepare(sql)
    let pending = try statement.pending()
    while try pending.executeTask() == .notReady {}
    _ = try pending.execute()
}
