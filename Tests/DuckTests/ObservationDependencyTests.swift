@testable import Duck
import Cduckdb
import SQL
import Testing

@Suite("ObservationDependencyTests")
struct ObservationDependencyTests {
    @Test("Dependency analysis remains conservative and ownership-safe")
    func dependencyAnalysisRemainsConservative() throws {
        let database = try NativeDatabase()
        let connection = try database.connect()
        let table = Path.Table("obs_parameters")
        let logs = Path.Table("obs_logs")

        try execute(tableCreationSQL(for: table), on: connection)
        try execute(tableCreationSQL(for: logs), on: connection)
        try execute(
            SQL
                .create
                .view[any: Path.Identifier("obs_parameters_view")]
                .as
                .select(SQL.asterisk)
                .from(table)
                .prepare(.duck)
                .plain,
            on: connection
        )

        let simpleSQL = SQL.select(table.column("value")).from(table).prepare(.duck).plain
        let simpleNames = try #require(connection.tableNames(in: simpleSQL, qualified: true))
        let simpleTables = try normalized(simpleNames)
        #expect(!simpleTables.isEmpty)
        #expect(ObservationDependency.analyze(sql: simpleSQL, on: connection) == .tables(simpleTables))

        let logsSQL = SQL.select(logs.column("value")).from(logs).prepare(.duck).plain
        let logsNames = try #require(connection.tableNames(in: logsSQL, qualified: true))
        let logsTables = try normalized(logsNames)

        let boundQuery = SQL
            .select(table.column("value"))
            .from(table)
            .where(table.column("id") == Int32(1))
        let bound = boundQuery.prepare(.duck).splitted
        #expect(bound.query.contains("$1"))
        #expect(connection.tableNames(in: bound.query, qualified: true) == nil)
        let boundPlain = boundQuery.prepare(.duck).plain
        let boundDependency = ObservationDependency.analyze(sql: boundPlain, on: connection)
        #expect(boundDependency == .tables(simpleTables))

        let hostile = "x' OR 1=1; DROP TABLE obs_parameters; --"
        let hostileQuery = SQL
            .select(table.column("value"))
            .from(table)
            .where(table.column("value") == hostile)
        let hostilePlain = hostileQuery.prepare(.duck).plain
        #expect(hostilePlain.contains("DROP TABLE obs_parameters"))
        #expect(hostilePlain.contains("'x'' OR 1=1; DROP TABLE obs_parameters; --'"))
        #expect(ObservationDependency.analyze(sql: hostilePlain, on: connection) == .tables(simpleTables))
        _ = try connection.prepare(simpleSQL)

        let joinSQL = SQL {
            Select {
                table.column("id")
            }
            From {
                table
                Join(.none, logs)
                On(table.column("id") == logs.column("id"))
            }
        }
        .prepare(.duck)
        .plain
        let joinNames = try #require(connection.tableNames(in: joinSQL, qualified: true))
        let joinTables = try normalized(joinNames)
        #expect(joinTables == simpleTables.union(logsTables))
        #expect(ObservationDependency.analyze(sql: joinSQL, on: connection) == .tables(joinTables))

        let selected = Path.Table("selected")
        let cteSQL = SQL
            .with(With(selected, SQL.select(SQL.asterisk).from(table)))
            .select(SQL.asterisk)
            .from(selected)
            .prepare(.duck)
            .plain
        let cteNames = try #require(connection.tableNames(in: cteSQL, qualified: true))
        let cteTables = try normalized(cteNames)
        #expect(cteTables == simpleTables)
        #expect(ObservationDependency.analyze(sql: cteSQL, on: connection) == .tables(simpleTables))

        let viewSQL = SQL
            .select(SQL.asterisk)
            .from(Path.Table("obs_parameters_view"))
            .prepare(.duck)
            .plain
        let viewNames = try #require(connection.tableNames(in: viewSQL, qualified: true))
        let viewTables = try normalized(viewNames)
        #expect(viewTables == simpleTables)
        #expect(ObservationDependency.analyze(sql: viewSQL, on: connection) == .tables(simpleTables))

        let aliasSQL = SQL
            .select(SQL.asterisk)
            .from(table.as(TableAlias("a")))
            .prepare(.duck)
            .plain
        #expect(ObservationDependency.analyze(sql: aliasSQL, on: connection) == .database)

        let unresolvedSQL = SQL
            .select(SQL.asterisk)
            .from(table)
            .where(table.column("id") == SQL.raw("$1"))
            .prepare(.duck)
            .plain
        #expect(ObservationDependency.analyze(sql: unresolvedSQL, on: connection) == .database)

        let noTableSQL = SQL.select(Int32(42)).prepare(.duck).plain
        #expect(ObservationDependency.analyze(sql: noTableSQL, on: connection) == .tables([]))

        let sequences = Fn.build(.custom("duckdb_sequences"), body: [])
        let sequenceSQL = SQL
            .select(Path.Column("last_value"))
            .from(sequences)
            .where(Path.Column("sequence_name") == "some_sequence")
            .prepare(.duck)
            .plain
        #expect(ObservationDependency.analyze(sql: sequenceSQL, on: connection) == .tables([]))

        for _ in 0..<100 {
            #expect(ObservationDependency.analyze(sql: simpleSQL, on: connection) == .tables(simpleTables))
        }
    }

    @Test("Invalidation merge and matching preserve empty-table semantics")
    func invalidationMergeAndMatchingPreserveEmptyTableSemantics() throws {
        let users = try #require(ObservationTableName(binderName: "main.users"))
        let logs = try #require(ObservationTableName(binderName: "main.logs"))
        let usersInvalidation = ObservationInvalidation.tables([users])
        let logsInvalidation = ObservationInvalidation.tables([logs])

        #expect(ObservationInvalidation.none.merged(with: usersInvalidation) == usersInvalidation)
        #expect(usersInvalidation.merged(with: ObservationInvalidation.none) == usersInvalidation)
        #expect(
            usersInvalidation.merged(with: logsInvalidation)
                == .tables([users, logs])
        )
        #expect(ObservationInvalidation.database.merged(with: usersInvalidation) == .database)
        #expect(usersInvalidation.merged(with: .database) == .database)

        let emptyDependency = ObservationDependency.tables([])
        let usersDependency = ObservationDependency.tables([users])
        #expect(!emptyDependency.matches(.none))
        #expect(emptyDependency.matches(.database))
        #expect(!emptyDependency.matches(usersInvalidation))
        #expect(ObservationDependency.database.matches(usersInvalidation))
        #expect(usersDependency.matches(usersInvalidation))
        #expect(!usersDependency.matches(logsInvalidation))
    }

    @Test("Coordinator registrations update, coalesce, finish, and remain database-local")
    func coordinatorRegistrationsUpdateCoalesceFinishAndRemainDatabaseLocal() async throws {
        let firstDatabase = try Database()
        let secondDatabase = try Database()
        let users = try #require(ObservationTableName(binderName: "main.users"))
        let logs = try #require(ObservationTableName(binderName: "main.logs"))

        let defaultRegistration = await firstDatabase.observationCoordinator.register()
        var defaultIterator = defaultRegistration.invalidations.makeAsyncIterator()
        await firstDatabase.observationCoordinator.invalidate(.tables([users]))
        #expect(await defaultIterator.next() != nil)
        await firstDatabase.observationCoordinator.unregister(defaultRegistration.id)
        #expect(await defaultIterator.next() == nil)

        let first = await firstDatabase.observationCoordinator.register(
            initial: .tables([])
        )
        var firstIterator = first.invalidations.makeAsyncIterator()
        await firstDatabase.observationCoordinator.invalidate(.tables([users]))
        await firstDatabase.observationCoordinator.unregister(first.id)
        #expect(await firstIterator.next() == nil)

        let coalesced = await firstDatabase.observationCoordinator.register(
            initial: .tables([])
        )
        var coalescedIterator = coalesced.invalidations.makeAsyncIterator()
        await firstDatabase.observationCoordinator.invalidate(.database)
        await firstDatabase.observationCoordinator.invalidate(.database)
        #expect(await coalescedIterator.next() != nil)
        await firstDatabase.observationCoordinator.unregister(coalesced.id)
        #expect(await coalescedIterator.next() == nil)

        let updated = await firstDatabase.observationCoordinator.register(
            initial: .tables([users])
        )
        var updatedIterator = updated.invalidations.makeAsyncIterator()
        await firstDatabase.observationCoordinator.update(
            subscriptionID: updated.id,
            dependency: .tables([logs])
        )
        await firstDatabase.observationCoordinator.invalidate(.tables([users]))
        await firstDatabase.observationCoordinator.unregister(updated.id)
        #expect(await updatedIterator.next() == nil)

        let second = await secondDatabase.observationCoordinator.register(initial: .tables([users]))
        var secondIterator = second.invalidations.makeAsyncIterator()
        await firstDatabase.observationCoordinator.invalidate(.tables([users]))
        await secondDatabase.observationCoordinator.unregister(second.id)
        #expect(await secondIterator.next() == nil)

        let secondPositive = await secondDatabase.observationCoordinator.register(initial: .tables([users]))
        var secondPositiveIterator = secondPositive.invalidations.makeAsyncIterator()
        await secondDatabase.observationCoordinator.invalidate(.tables([users]))
        #expect(await secondPositiveIterator.next() != nil)
        await secondDatabase.observationCoordinator.unregister(secondPositive.id)
        #expect(await secondPositiveIterator.next() == nil)

        await firstDatabase.observationCoordinator.unregister(first.id)
        await firstDatabase.observationCoordinator.unregister(updated.id)
        await secondDatabase.observationCoordinator.unregister(second.id)
        await secondDatabase.observationCoordinator.unregister(secondPositive.id)
    }
}

private func tableCreationSQL(for table: Path.Table) -> String {
    SQL.create.table[any: table]
        .tableDefinitions(
            NewColumn("id", .integer),
            NewColumn("value", .text)
        )
        .prepare(.duck)
        .plain
}

private func execute(_ sql: String, on connection: NativeConnection) throws {
    let statement = try connection.prepare(sql)
    let pending = try statement.pending()
    while try pending.executeTask() == .notReady {}
    _ = try pending.execute()
}

private func normalized(_ names: [String]) throws -> Set<ObservationTableName> {
    var result: Set<ObservationTableName> = []
    for name in names {
        result.insert(try #require(ObservationTableName(binderName: name)))
    }
    return result
}
