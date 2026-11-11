@testable import Duck
import Foundation
import SQL
import Testing

private struct AccountOptions: Codable, Equatable, Sendable {
    var twoFactorAuthEnabled: Bool
    var lastPasswordChangeDate: Date?

    enum CodingKeys: String, CodingKey {
        case twoFactorAuthEnabled = "two_factor_auth_enabled"
        case lastPasswordChangeDate = "last_password_change_date"
    }
}

private struct HasAccountOptions: Encodable, Sendable {
    let options: AccountOptions
}

private enum StructuredPermission: String, Codable, Sendable {
    case read
    case write
}

private struct StructuredPermissionOptions: Codable, Sendable {
    let permission: StructuredPermission
}

private struct HasStructuredPermission: Decodable, Sendable {
    let options: StructuredPermissionOptions
}

private struct HasRequiredStructuredValue: Decodable, Sendable {
    let options: RequiredStructuredValue
}

private struct RequiredStructuredValue: Decodable, Sendable {
    let required: String
}

private struct NestedStructuredMember: Codable, Sendable {
    let inner: String
}

private struct ParentStructuredMember: Encodable, Sendable {
    let child: NestedStructuredMember
}

private struct HasNestedStructuredMember: Encodable, Sendable {
    let options: ParentStructuredMember
}

private struct HasArrayStructuredMember: Encodable, Sendable {
    let options: ArrayStructuredMember
}

private struct ArrayStructuredMember: Encodable, Sendable {
    let values: [String]
}

private struct HasArrayInStructuredValue: Decodable, Sendable {
    let options: ArrayInStructuredValue
}

private struct ArrayInStructuredValue: Decodable, Sendable {
    let values: [String]
}

private struct StructuredAccount: Table {
    static let tableName = "structured_value_accounts"

    @Column("id") var id: Int64
    @Column("options") var options: AccountOptions
    @Column("note") var note: String?

    init() {}

    init(id: Int64, options: AccountOptions) {
        self.id = id
        self.options = options
    }

    init(id: Int64, options: AccountOptions, note: String?) {
        self.id = id
        self.options = options
        self.note = note
    }
}

private let structuredAccountTable = DB.Table(StructuredAccount.tableName)
private let structuredAccountOptionsType = Type.struct([
    ("two_factor_auth_enabled", .boolean),
    ("last_password_change_date", .timestamptz)
])
private let structuredEnumName = "structured_value_permission"

private enum StructuredRollbackFailure: Error {
    case rollback
}

private func execute(
    _ connection: NativeConnection,
    _ query: any SQLable
) throws -> NativeResult {
    let statement = try connection.prepare(query.prepare(.duck).plain)
    let pending = try statement.pending()
    while try pending.executeTask() == .notReady {}
    return try pending.execute()
}

private func nativeFirstValue(
    _ connection: NativeConnection,
    _ query: any SQLable,
    column: String
) throws -> Value {
    let result = try execute(connection, query)
    let rows = try #require(try result.materializeNextChunk())
    return try #require(rows.first?[column])
}

private func nativeRowCount(_ connection: NativeConnection, table: String) throws -> Int64 {
    let value = try nativeFirstValue(
        connection,
        SQL.select(Fn.cast(Fn.count(SQL.asterisk), .bigint) => "count").from(DB.Table(table)),
        column: "count"
    )
    return try #require(value.get(Int64.self))
}

private func createNativeStructTable(
    _ connection: NativeConnection,
    table: String,
    members: [(String, Type)]
) throws {
    _ = try execute(
        connection,
        SQL
            .create
            .table[any: DB.Table(table)]
            .tableDefinitions(
                NewColumn("id", .bigint),
                NewColumn("payload", .struct(members))
            )
    )
}

private func selectNativeStructValues(_ connection: NativeConnection, table: String) throws -> [Value] {
    let table = DB.Table(table)
    let result = try execute(
        connection,
        SQL
            .select(table.column("payload"))
            .from(table)
            .orderBy(.asc(table.column("id")))
    )
    var values: [Value] = []
    while let chunk = try result.materializeNextChunk() {
        for row in chunk {
            values.append(try #require(row["payload"]))
        }
    }
    return values
}

private func queryStruct(
    on connection: Connection,
    target: Type,
    value: Value
) async throws -> Value {
    let statement = try await connection.prepare { parameters in
        SQL.select(Fn.cast(parameters.parameter(), target) => "payload")
    }
    let result = try await statement.query(value)
    return try #require(result.rows.first?["payload"])
}

private func accountOptions(_ enabled: Bool, _ date: Date?) -> AccountOptions {
    AccountOptions(twoFactorAuthEnabled: enabled, lastPasswordChangeDate: date)
}

private func createStructuredAccountSchema(on connection: Connection) async throws {
    try await connection.execute(
        SQL
            .create
            .table[any: structuredAccountTable]
            .tableDefinitions(
                NewColumn("id", .bigint).primaryKey(),
                NewColumn("options", structuredAccountOptionsType).notNull(),
                NewColumn("note", .varchar).default(
                    expression: SQL.default[any: SQLableParts(parts: SQLPartSafeValue("fallback-note"))]
                )
            )
    )
}

@Test("ST01-ST02 STRUCT Value facade preserves identities, names, order and NULL scope")
func structuredValueFacade() {
    #expect(Value.Kind.list.rawValue == 23)
    #expect(Value.Kind.structure.rawValue == 24)
    #expect(Value.Kind.allKnown.map(\.rawValue) == Array(0...24))
    #expect(Value.Kind.allKnown.prefix(24).map(\.rawValue) == Array(0...23))

    let members = [
        Value.StructMember(name: "second", value: .null),
        Value.StructMember(name: "first", value: .boolean(true))
    ]
    let structure = Value.structure(members)
    #expect(structure.structureValue == members)
    #expect(structure.get([Value.StructMember].self) == members)
    #expect(structure.kind == .structure)
    #expect(structure == Value.structure(members))
    #expect(structure != Value.structure(Array(members.reversed())))
    #expect(structure != .null)
    #expect(structure.structureValue?.first?.value == .null)
    #expect(Value.null.structureValue == nil)
    #expect(Value.structure([]).structureValue == [])
}

@Test("ST17-ST20 synthesized keyed Codable captures exact STRUCT names, NULL Optional and enum scalar")
func synthesizedStructEncodingAndOptionals() throws {
    let nilOptional = try ModelEncoder().encode(
        HasAccountOptions(options: accountOptions(true, nil))
    )
    #expect(nilOptional.fields.map(\.key) == ["options"])
    #expect(try #require(nilOptional.fields.first?.value).structureValue == [
        .init(name: "two_factor_auth_enabled", value: .boolean(true)),
        .init(name: "last_password_change_date", value: .null)
    ])

    let date = Date(timeIntervalSince1970: 1_700_000_000)
    let presentOptional = try ModelEncoder().encode(
        HasAccountOptions(options: accountOptions(false, date))
    )
    #expect(try #require(presentOptional.fields.first?.value).structureValue == [
        .init(name: "two_factor_auth_enabled", value: .boolean(false)),
        .init(name: "last_password_change_date", value: .timestampTZ(date))
    ])

    struct EnumOptions: Encodable {
        let options: StructuredPermissionOptions
    }
    let permissionEncoded = try ModelEncoder().encode(
        EnumOptions(options: StructuredPermissionOptions(permission: .write))
    )
    #expect(try #require(permissionEncoded.fields.first?.value).structureValue == [
        .init(name: "permission", value: .string("write"))
    ])
}

@Test("ST21-ST22 keyed and unkeyed values nested inside STRUCT keep the coding path")
func nestedCompositeStructEncodingRejectsWithPath() throws {
    let nestedKeyed = HasNestedStructuredMember(
        options: ParentStructuredMember(child: NestedStructuredMember(inner: "x"))
    )
    let nestedArray = HasArrayStructuredMember(
        options: ArrayStructuredMember(values: ["x"])
    )

    let keyedError = captureEncodingError(for: nestedKeyed)
    guard case .invalidValue(_, let keyedContext)? = keyedError else {
        Issue.record("Expected invalidValue for nested keyed STRUCT member")
        return
    }
    #expect(keyedContext.codingPath.map(\.stringValue) == ["options", "child", "inner"])

    let arrayError = captureEncodingError(for: nestedArray)
    guard case .invalidValue(_, let arrayContext)? = arrayError else {
        Issue.record("Expected invalidValue for nested unkeyed STRUCT member")
        return
    }
    #expect(arrayContext.codingPath.map(\.stringValue) == ["options", "values"])
}

private func captureEncodingError<T: Encodable>(for value: T) -> EncodingError? {
    do {
        _ = try ModelEncoder().encode(value)
        Issue.record("Expected a nested composite STRUCT member to be rejected")
        return nil
    } catch let error as EncodingError {
        return error
    } catch {
        Issue.record("Expected EncodingError for nested composite STRUCT member, got \(error)")
        return nil
    }
}

@Test("ST03-ST06 prepared STRUCT uses parent target, exact names, order and NULL members")
func preparedStructNameAuthoritativeRoundTrip() async throws {
    let connection = try Database().connect()
    let date = Date(timeIntervalSince1970: 1_700_000_000)
    let reversed = Value.structure([
        .init(name: "last_password_change_date", value: .timestampTZ(date)),
        .init(name: "two_factor_auth_enabled", value: .boolean(true))
    ])
    #expect(try await queryStruct(on: connection, target: structuredAccountOptionsType, value: reversed)
        == .structure([
            .init(name: "two_factor_auth_enabled", value: .boolean(true)),
            .init(name: "last_password_change_date", value: .timestampTZ(date))
        ]))

    let withNullMember = Value.structure([
        .init(name: "two_factor_auth_enabled", value: .boolean(false)),
        .init(name: "last_password_change_date", value: .null)
    ])
    #expect(try await queryStruct(on: connection, target: structuredAccountOptionsType, value: withNullMember)
        == withNullMember)

    #expect(try await queryStruct(on: connection, target: structuredAccountOptionsType, value: .null) == .null)
}

@Test("ST07-ST10 prepared STRUCT rejects duplicate, missing, unknown and wrong members")
func preparedStructRejectsInvalidMembers() async throws {
    let connection = try Database().connect()
    let badValues: [Value] = [
        .structure([
            .init(name: "two_factor_auth_enabled", value: .boolean(true)),
            .init(name: "two_factor_auth_enabled", value: .boolean(false)),
            .init(name: "last_password_change_date", value: .null)
        ]),
        .structure([.init(name: "two_factor_auth_enabled", value: .boolean(true))]),
        .structure([
            .init(name: "two_factor_auth_enabled", value: .boolean(true)),
            .init(name: "last_password_change_date", value: .null),
            .init(name: "unexpected", value: .string("x"))
        ]),
        .structure([
            .init(name: "two_factor_auth_enabled", value: .int8(1)),
            .init(name: "last_password_change_date", value: .null)
        ])
    ]

    for value in badValues {
        do {
            _ = try await queryStruct(on: connection, target: structuredAccountOptionsType, value: value)
            Issue.record("Expected invalid STRUCT input to fail before query execution")
        } catch let error as DatabaseError {
            guard case .binding = error else {
                Issue.record("Expected binding failure for invalid STRUCT input, got \(error)")
                return
            }
        }
    }
}

@Test("ST11-ST14 Appender STRUCT preserves members and reads flat child vectors by parent row index")
func appenderStructRoundTripAndResultVectors() throws {
    let database = try NativeDatabase()
    let connection = try database.connect()
    try createNativeStructTable(
        connection,
        table: "structured_appender_rows",
        members: [("first", .varchar), ("second", .bigint)]
    )

    let appender = try NativeAppender(connection: connection, table: "structured_appender_rows")
    try appender.appendRow([
        .int64(1),
        .structure([.init(name: "second", value: .int64(20)), .init(name: "first", value: .string("one"))])
    ])
    try appender.appendRow([
        .int64(2),
        .structure([.init(name: "first", value: .string("two")), .init(name: "second", value: .null)])
    ])
    try appender.appendRow([.int64(3), .null])
    try appender.appendRow([
        .int64(4),
        .structure([.init(name: "first", value: .string("four")), .init(name: "second", value: .int64(40))])
    ])
    try appender.close()

    #expect(try selectNativeStructValues(connection, table: "structured_appender_rows") == [
        .structure([.init(name: "first", value: .string("one")), .init(name: "second", value: .int64(20))]),
        .structure([.init(name: "first", value: .string("two")), .init(name: "second", value: .null)]),
        .null,
        .structure([.init(name: "first", value: .string("four")), .init(name: "second", value: .int64(40))])
    ])
}

@Test("SR01 STRUCT result failure releases the acquired nested child type")
func structResultCompositeFailure() throws {
    let database = try NativeDatabase()
    let connection = try database.connect()
    let result = try execute(
        connection,
        SQL.select(
            SQL.raw("struct_pack(nested := struct_pack(value := 'x'))") => "payload"
        )
    )

    do {
        _ = try result.materializeNextChunk()
        Issue.record("Expected nested STRUCT result materialization to be rejected")
    } catch let error as NativeDuckDBError {
        guard case .unsupportedResultType = error.operation else {
            Issue.record("Expected unsupportedResultType for nested STRUCT result, got \(error)")
            return
        }
    }
}

@Test("ST07-ST10 Appender preflight failures do not mutate and valid retry succeeds")
func appenderStructPreflightAndRetry() throws {
    let database = try NativeDatabase()
    let connection = try database.connect()
    try createNativeStructTable(
        connection,
        table: "structured_appender_preflight",
        members: [("flag", .boolean), ("count", .tinyint)]
    )

    let appender = try NativeAppender(connection: connection, table: "structured_appender_preflight")
    let invalidValues = [
        Value.structure([
            .init(name: "flag", value: .boolean(true)),
            .init(name: "flag", value: .boolean(false)),
            .init(name: "count", value: .int8(7))
        ]),
        Value.structure([.init(name: "flag", value: .boolean(true))]),
        Value.structure([
            .init(name: "flag", value: .boolean(true)),
            .init(name: "count", value: .int8(7)),
            .init(name: "extra", value: .string("x"))
        ]),
        Value.structure([
            .init(name: "flag", value: .int8(1)),
            .init(name: "count", value: .int8(7))
        ]),
        Value.structure([
            .init(name: "flag", value: .boolean(true)),
            .init(name: "count", value: .int64(128))
        ])
    ]
    for invalid in invalidValues {
        do {
            try appender.appendRow([.int64(1), invalid])
            Issue.record("Expected STRUCT appender preflight failure")
        } catch let error as NativeAppenderError {
            #expect(error.isPreflight)
            #expect(error.stage == .appendColumn(2))
        }
    }

    #expect(try nativeRowCount(connection, table: "structured_appender_preflight") == 0)
    try appender.appendRow([
        .int64(2),
        .structure([.init(name: "count", value: .int8(7)), .init(name: "flag", value: .boolean(true))])
    ])
    try appender.close()
    #expect(try selectNativeStructValues(connection, table: "structured_appender_preflight") == [
        .structure([.init(name: "flag", value: .boolean(true)), .init(name: "count", value: .int8(7))])
    ])
}

@Test("ST15 scalar STRUCT member census covers native families, widths, DECIMAL and ENUM")
func structScalarMemberCensus() async throws {
    let connection = try Database().connect()
    try await connection.execute(
        SQL.create.type[any: DB.Object(structuredEnumName)].as.enum(["read", "write"])
    )

    let date = try #require(PureDate(year: 2025, month: 1, day: 2))
    let time = try #require(PureTime(nanosecondsSinceMidnight: 45_296_000_000_000))
    let dateTime = try #require(DateTime(date: date, time: time))
    let uuid = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
    let decimal = Decimal(string: "123.45")!
    let values: [(String, Type, Value)] = [
        ("boolean", .boolean, .boolean(true)),
        ("tinyint", .tinyint, .int8(-8)),
        ("smallint", .smallint, .int16(-16)),
        ("integer", .integer, .int32(-32)),
        ("bigint", .bigint, .int64(-64)),
        ("hugeint", .hugeint, Value(signedUpper: 0, lower: 42)),
        ("utinyint", .utinyint, .uint8(8)),
        ("usmallint", .usmallint, .uint16(16)),
        ("uinteger", .uinteger, .uint32(32)),
        ("ubigint", .ubigint, .uint64(64)),
        ("uhugeint", .uhugeint, Value(unsignedUpper: 0, lower: 84)),
        ("float", .real, .float(1.25)),
        ("double", .doublePrecision, .double(2.5)),
        ("varchar", .varchar, .string("text")),
        ("blob", .blob, .blob(Data([0xCA, 0xFE]))),
        ("uuid", .uuid, .uuid(uuid)),
        ("date", .date, .date(date)),
        ("time", .time, .time(time)),
        ("time_ns", .timeNs, .time(time)),
        ("timestamp_s", .timestampS, .dateTime(dateTime)),
        ("timestamp_ms", .timestampMs, .dateTime(dateTime)),
        ("timestamp_us", .timestamp, .dateTime(dateTime)),
        ("timestamp_ns", .timestampNs, .dateTime(dateTime)),
        ("timestamptz", .timestamptz, .timestampTZ(Date(timeIntervalSince1970: 1_700_000_000))),
        ("interval", .interval, .interval(Interval(months: 2, days: 3, microseconds: 4))),
        ("decimal", .decimal(9, 2), .decimal(decimal)),
        ("enumeration", .custom(structuredEnumName), .string("write"))
    ]
    let target = Type.struct(values.map { ($0.0, $0.1) })
    let input = Value.structure(values.map { .init(name: $0.0, value: $0.2) })
    let expected = Value.structure(values.map { .init(name: $0.0, value: $0.2) })
    #expect(try await queryStruct(on: connection, target: target, value: input) == expected)
}

@Test("ST16 unsupported composite STRUCT child targets reject before scalar construction")
func nestedStructChildTargetsReject() async throws {
    let connection = try Database().connect()
    let targets: [(String, Type)] = [
        ("nested", .struct(("value", .varchar))),
        ("list", .list(.varchar)),
        ("map", .map(key: .varchar, value: .varchar)),
        ("union", .union(("text", .varchar), ("count", .integer))),
        ("array", .array(.varchar, length: 2))
    ]

    for (name, childType) in targets {
        do {
            _ = try await queryStruct(
                on: connection,
                target: .struct((name, childType)),
                value: .structure([.init(name: name, value: .null)])
            )
            Issue.record("Expected unsupported composite child target \(name) to fail")
        } catch let error as DatabaseError {
            guard case .binding = error else {
                Issue.record("Expected binding failure for \(name), got \(error)")
                return
            }
        }
    }
}

@Test("ST24-ST30 STRUCT decoding supports one keyed layer and preserves Codable errors")
func structDecodeBoundaries() throws {
    let structure = Value.structure([
        .init(name: "two_factor_auth_enabled", value: .boolean(true)),
        .init(name: "last_password_change_date", value: .null)
    ])
    let row = ResultRow(columns: ["options"], values: [structure])
    #expect(try row.decode(HasStructuredAccountOptions.self).options == accountOptions(true, nil))

    let missing = ResultRow(columns: ["options"], values: [.structure([])])
    do {
        _ = try missing.decode(HasRequiredStructuredValue.self)
        Issue.record("Expected missing required STRUCT member to throw keyNotFound")
    } catch let error as DecodingError {
        guard case .keyNotFound = error else {
            Issue.record("Expected keyNotFound for missing STRUCT member, got \(error)")
            return
        }
    }

    let wrong = ResultRow(
        columns: ["options"],
        values: [.structure([
            .init(name: "two_factor_auth_enabled", value: .string("yes")),
            .init(name: "last_password_change_date", value: .null)
        ])]
    )
    do {
        _ = try wrong.decode(HasStructuredAccountOptions.self)
        Issue.record("Expected wrong STRUCT member type to throw typeMismatch")
    } catch let error as DecodingError {
        guard case .typeMismatch = error else {
            Issue.record("Expected typeMismatch for wrong STRUCT member, got \(error)")
            return
        }
    }

    let scalar = ResultRow(columns: ["options"], values: [.string("scalar")])
    do {
        _ = try scalar.decode(HasStructuredAccountOptions.self)
        Issue.record("Expected scalar requested as nested model to throw typeMismatch")
    } catch let error as DecodingError {
        guard case .typeMismatch = error else {
            Issue.record("Expected typeMismatch for scalar nested model, got \(error)")
            return
        }
    }

    let nested = ResultRow(
        columns: ["options"],
        values: [.structure([
            .init(name: "two_factor_auth_enabled", value: .structure([])),
            .init(name: "last_password_change_date", value: .null)
        ])]
    )
    do {
        _ = try nested.decode(HasStructuredAccountOptions.self)
        Issue.record("Expected nested STRUCT member to throw typeMismatch")
    } catch let error as DecodingError {
        guard case .typeMismatch = error else {
            Issue.record("Expected typeMismatch for nested STRUCT member, got \(error)")
            return
        }
    }

    let enumRow = ResultRow(
        columns: ["options"],
        values: [.structure([.init(name: "permission", value: .string("write"))])]
    )
    #expect(try enumRow.decode(HasStructuredPermission.self).options.permission == .write)

    let arrayRow = ResultRow(
        columns: ["options"],
        values: [.structure([.init(name: "values", value: .list([.string("x")]))])]
    )
    do {
        _ = try arrayRow.decode(HasArrayInStructuredValue.self)
        Issue.record("Expected an unkeyed composite STRUCT member to throw typeMismatch")
    } catch let error as DecodingError {
        guard case .typeMismatch = error else {
            Issue.record("Expected typeMismatch for unkeyed STRUCT member, got \(error)")
            return
        }
    }
}

private struct HasStructuredAccountOptions: Decodable, Sendable {
    let options: AccountOptions
}

@Test("ST31-ST34 Connection persistence covers insert, update, upsert and batch Appender")
func connectionStructPersistenceSurfaces() async throws {
    let connection = try Database().connect()
    try await createStructuredAccountSchema(on: connection)

    let original = try await StructuredAccount(id: 1, options: accountOptions(true, nil)).insert(on: connection)
    #expect(original.id == 1)
    #expect(original.options == accountOptions(true, nil))

    original.options = accountOptions(false, Date(timeIntervalSince1970: 1_700_000_000))
    let updated = try await original.update(on: \.$id, on: connection)
    #expect(updated.options == original.options)

    let upserted = try await StructuredAccount(id: 1, options: accountOptions(true, nil))
        .upsert(conflictColumn: \.$id, on: connection)
    #expect(upserted.options == accountOptions(true, nil))

    try await [
        StructuredAccount(id: 2, options: accountOptions(false, nil)),
        StructuredAccount(id: 3, options: accountOptions(true, Date(timeIntervalSince1970: 1_650_000_000)))
    ].batchInsert(on: connection)
    let batched = try await StructuredAccount
        .select
        .where(structuredAccountTable.column("id") >= 2)
        .orderBy(.asc(structuredAccountTable.column("id")))
        .query(on: connection)
        .all(decoding: StructuredAccount.self)
    #expect(batched.map(\.options) == [
        accountOptions(false, nil),
        accountOptions(true, Date(timeIntervalSince1970: 1_650_000_000))
    ])
}

@Test("ST35 DatabaseIdentifier target stores and reads an AccountOptions STRUCT")
func databaseIdentifierStructPersistence() async throws {
    let identifier = DatabaseIdentifier.memory()
    try await SQL
        .create
        .table[any: structuredAccountTable]
        .tableDefinitions(
            NewColumn("id", .bigint).primaryKey(),
            NewColumn("options", structuredAccountOptionsType).notNull()
        )
        .execute(on: identifier)

    let inserted = try await StructuredAccount(id: 7, options: accountOptions(true, nil)).insert(on: identifier)
    #expect(inserted.options == accountOptions(true, nil))
    let stored = try await StructuredAccount
        .select
        .where(structuredAccountTable.column("id") == 7)
        .limit(1)
        .query(on: identifier)
        .first(decoding: StructuredAccount.self)
    #expect(stored?.options == accountOptions(true, nil))
}

@Test("ST36 STRUCT mutation rolls back with DuckTransaction")
func structTransactionRollback() async throws {
    let connection = try Database().connect()
    try await createStructuredAccountSchema(on: connection)

    do {
        try await connection.transaction { transaction in
            try await StructuredAccount(id: 9, options: accountOptions(true, nil))
                .insertNonReturning(on: transaction)
            throw StructuredRollbackFailure.rollback
        }
        Issue.record("Expected the STRUCT transaction to roll back")
    } catch StructuredRollbackFailure.rollback {
        // The managed transaction must remove the STRUCT row.
    }

    let stored = try await StructuredAccount
        .select
        .where(structuredAccountTable.column("id") == 9)
        .limit(1)
        .query(on: connection)
        .first(decoding: StructuredAccount.self)
    #expect(stored == nil)
}

@Test("ST37-ST38 schema target, DEFAULT-vs-NULL and unrelated changed fields stay exact")
func structSchemaDefaultNullAndChangedFields() async throws {
    let connection = try Database().connect()
    try await createStructuredAccountSchema(on: connection)

    _ = try await StructuredAccount(id: 10, options: accountOptions(true, nil)).insert(on: connection)
    let defaultResult = try await connection.query(
        SQL.select(structuredAccountTable.column("note")).from(structuredAccountTable)
    )
    #expect(defaultResult.rows.first?["note"] == .string("fallback-note"))

    _ = try await StructuredAccount(id: 11, options: accountOptions(false, nil), note: nil).insert(on: connection)
    let nullResult = try await connection.query(
        SQL.select(structuredAccountTable.column("note")).from(structuredAccountTable)
            .where(structuredAccountTable.column("id") == 11)
    )
    #expect(nullResult.rows.first?["note"] == .null)

    let loaded = try #require(await StructuredAccount
        .select
        .where(structuredAccountTable.column("id") == 10)
        .limit(1)
        .query(on: connection)
        .first(decoding: StructuredAccount.self))
    loaded.note = "kept"
    loaded.options = accountOptions(false, nil)
    _ = try await loaded.update(on: \.$id, on: connection)
    let afterUpdate = try #require(await StructuredAccount
        .select
        .where(structuredAccountTable.column("id") == 10)
        .limit(1)
        .query(on: connection)
        .first(decoding: StructuredAccount.self))
    #expect(afterUpdate.options == accountOptions(false, nil))
    #expect(afterUpdate.note == "kept")

    _ = try await StructuredAccount(id: 10, options: accountOptions(true, nil))
        .upsert(conflictColumn: \.$id, on: connection)
    let afterUpsert = try #require(await StructuredAccount
        .select
        .where(structuredAccountTable.column("id") == 10)
        .limit(1)
        .query(on: connection)
        .first(decoding: StructuredAccount.self))
    #expect(afterUpsert.options == accountOptions(true, nil))
    #expect(afterUpsert.note == "kept")

    let scoped = DB.Schema("structured_value_schema").table("structured_value_scoped")
    try await connection.execute(SQL.create.schema[any: DB.Object("structured_value_schema")])
    try await connection.execute(
        SQL
            .create
            .table[any: scoped]
            .tableDefinitions(
                NewColumn("id", .bigint).primaryKey(),
                NewColumn("options", structuredAccountOptionsType).notNull()
            )
    )
    let statement = try await connection.prepare { parameters in
        SQL.insertInto(scoped, fields: "id", "options").values.values(Int64(1), parameters.parameter())
    }
    _ = try await statement.execute(Value.structure([
        .init(name: "last_password_change_date", value: .null),
        .init(name: "two_factor_auth_enabled", value: .boolean(true))
    ]))
    let scopedResult = try await connection.query(SQL.select(scoped.column("options")).from(scoped))
    #expect(scopedResult.rows.first?["options"] == .structure([
        .init(name: "two_factor_auth_enabled", value: .boolean(true)),
        .init(name: "last_password_change_date", value: .null)
    ]))
}
