@testable import Duck
import Foundation
import SQL
import Testing

// MARK: - Models

private enum ListPermission: String, Codable, Equatable, Sendable, CaseIterable {
    case create
    case edit
    case delete
}

private struct ListUser: Table {
    static let tableName = "list_value_persistence_users"

    @Column("id") var id: Int64
    @Column("tags") var tags: [String]
    @Column("permissions") var permissions: [ListPermission]
    @Column("note") var note: String?

    init() {}

    /// Leaves `note` uninitialized so the database DEFAULT stays eligible.
    init(id: Int64, tags: [String], permissions: [ListPermission]) {
        self.id = id
        self.tags = tags
        self.permissions = permissions
    }

    /// Initializes `note` explicitly, so `nil` binds SQL NULL instead of the DEFAULT.
    init(id: Int64, tags: [String], permissions: [ListPermission], note: String?) {
        self.id = id
        self.tags = tags
        self.permissions = permissions
        self.note = note
    }
}

private let listUsersTable = DB.Table(ListUser.tableName)

/// A keyed `[String?]` property, so a SQL NULL LIST child can be proved through persistence.
private struct ListNullableUser: Table {
    static let tableName = "list_value_nullable_users"

    @Column("id") var id: Int64
    @Column("tags") var tags: [String?]

    init() {}

    init(id: Int64, tags: [String?]) {
        self.id = id
        self.tags = tags
    }
}

private let listNullableUsersTable = DB.Table(ListNullableUser.tableName)
private let permissionTypeName = "list_value_permission"
private let widePermissionTypeName = "list_value_wide_permission"

private enum ListRollbackFailure: Error {
    case rollback
}

// MARK: - Native helpers (Appender and vector rows)

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
        SQL
            .select(Fn.cast(Fn.count(SQL.asterisk), .bigint) => "count")
            .from(DB.Table(table)),
        column: "count"
    )
    return try #require(value.get(Int64.self))
}

private func createNativeListTable(
    _ connection: NativeConnection,
    table: String,
    element: Type
) throws {
    _ = try execute(
        connection,
        SQL
            .create
            .table[any: DB.Table(table)]
            .tableDefinitions(
                NewColumn("id", .bigint),
                NewColumn("payload", .list(element))
            )
    )
}

private func appendNativeListRows(
    _ connection: NativeConnection,
    table: String,
    rows: [(id: Int64, payload: Value)]
) throws {
    let appender = try NativeAppender(connection: connection, table: table)
    for row in rows {
        try appender.appendRow([.int64(row.id), row.payload])
    }
    try appender.close()
}

private func selectNativeList(_ connection: NativeConnection, table: String) throws -> [Value] {
    let result = try execute(
        connection,
        SQL
            .select(DB.Table(table).column("payload"))
            .from(DB.Table(table))
            .orderBy(.asc(DB.Table(table).column("id")))
    )
    var values: [Value] = []
    while let chunk = try result.materializeNextChunk() {
        for row in chunk {
            values.append(try #require(row["payload"]))
        }
    }
    return values
}

private func createPermissionEnum(_ connection: NativeConnection) throws {
    _ = try execute(
        connection,
        SQL
            .create
            .type[any: DB.Object(permissionTypeName)]
            .as
            .enum(Array(ListPermission.allCases.map(\.rawValue)))
    )
}

// MARK: - Public prepared helpers

private func payloadType(_ element: Type) -> Type {
    .list(element)
}

private func queryListPayload(
    on connection: Connection,
    element: Type,
    binding: Value
) async throws -> Value {
    let statement = try await connection.prepare { parameters in
        SQL.select(Fn.cast(parameters.parameter(), payloadType(element)) => "payload")
    }
    let result = try await statement.query(binding)
    return try #require(result.rows.first?["payload"])
}

// MARK: - L01, L02: Value facade

@Test("L01 Value.Kind keeps LIST at raw ID 23 and appends STRUCT at 24")
func valueKindListIsAppendOnly() {
    #expect(Value.Kind.list.rawValue == 23)
    #expect(Value.Kind.structure.rawValue == 24)
    #expect(Value.Kind.allKnown.map(\.rawValue) == Array(0...24))
    #expect(Value.Kind.allKnown.prefix(24).map(\.rawValue) == Array(0...23))
    #expect(Value.Kind.allKnown[23] == .list)
    #expect(Value.Kind.allKnown.last == .structure)
    #expect(Value.Kind.decimal.rawValue == 22)
    #expect(Value.list([]).kind == .list)
}

@Test("L02 Value.list preserves order, emptiness, null children and exact extraction")
func valueListFacade() throws {
    let list = Value.list([.string("a"), .null, .int64(7)])

    #expect(list.listValue == [.string("a"), .null, .int64(7)])
    #expect(list.get([Value].self) == [.string("a"), .null, .int64(7)])
    #expect(Value.list([]).listValue == [])
    #expect(Value.list([.null]).listValue == [.null])

    #expect(Value.list([.string("a"), .string("b")]) == Value.list([.string("a"), .string("b")]))
    #expect(Value.list([.string("a"), .string("b")]) != Value.list([.string("b"), .string("a")]))

    // A SQL NULL list is neither an empty list nor a list of one NULL.
    #expect(Value.list([]) != Value.null)
    #expect(Value.list([.null]) != Value.null)
    #expect(Value.list([.null]) != Value.list([]))
    #expect(!Value.list([]).isNull)
    #expect(Value.list([]).get(String.self) == nil)
    #expect(Value.int64(1).listValue == nil)
    #expect(Value.null.listValue == nil)
}

// MARK: - L03-L08: prepared binding

@Test("L03 prepared LIST(VARCHAR) round-trips a non-empty list")
func preparedListVarcharRoundTrip() async throws {
    let connection = try Database().connect()
    let children: [Value] = [.string("a"), .string("b")]

    let payload = try await queryListPayload(
        on: connection,
        element: .varchar,
        binding: .list(children)
    )
    #expect(payload == Value.list(children))
}

@Test("L04 prepared empty LIST obeys C3 and round-trips")
func preparedEmptyList() async throws {
    let connection = try Database().connect()

    // C3/C1: value_count == 0 still needs a live values pointer and the element type only
    // exists once the target resolves to a LIST, so an empty LIST cannot travel untyped.
    let payload = try await queryListPayload(
        on: connection,
        element: .varchar,
        binding: .list([])
    )
    #expect(payload == Value.list([]))
    #expect(payload.listValue?.isEmpty == true)
}

@Test("L05 prepared LIST(VARCHAR) preserves a SQL NULL child")
func preparedListWithNullChild() async throws {
    let connection = try Database().connect()
    let children: [Value] = [.string("a"), .null, .string("c")]

    let payload = try await queryListPayload(
        on: connection,
        element: .varchar,
        binding: .list(children)
    )
    #expect(payload == Value.list(children))
}

@Test("L06 LIST against a non-LIST target fails before execution")
func preparedListTargetMismatchFailsBeforeMutation() async throws {
    let database = try Database()
    let connection = try database.connect()
    let table = DB.Table("list_value_scalar_target")
    try await connection.execute(
        SQL
            .create
            .table[any: table]
            .tableDefinitions(NewColumn("id", .bigint), NewColumn("payload", .varchar))
    )
    #expect(try await countRows(table, on: connection) == 0)

    let statement = try await connection.prepare { parameters in
        SQL
            .insertInto(table, fields: "id", "payload")
            .values
            .values(Int64(1), parameters.parameter())
    }
    do {
        _ = try await statement.execute(Value.list([.string("a")]))
        Issue.record("Expected LIST binding against a VARCHAR target to fail.")
    } catch let error as DatabaseError {
        guard case .binding(let index, let message) = error else {
            Issue.record("Expected a binding failure, got \(error).")
            return
        }
        #expect(index == 2)
        #expect(message.contains("LIST"))
    }

    // The failure happened while preparing the value, so nothing was inserted.
    #expect(try await countRows(table, on: connection) == 0)
}

@Test("L07 native LIST(ENUM) dictionary mapping round-trips through prepared binding")
func preparedListEnumRoundTrip() async throws {
    let connection = try Database().connect()
    try await connection.execute(
        SQL
            .create
            .type[any: DB.Object(permissionTypeName)]
            .as
            .enum(Array(ListPermission.allCases.map(\.rawValue)))
    )

    let payload = try await queryListPayload(
        on: connection,
        element: .custom(permissionTypeName),
        binding: .list([.string("create"), .string("edit"), .string("delete")])
    )
    #expect(payload == .list([.string("create"), .string("edit"), .string("delete")]))
}

@Test("L08 unknown ENUM label fails before mutation and leaves rows unchanged")
func preparedListUnknownEnumLabelFailsBeforeMutation() async throws {
    let database = try Database()
    let connection = try database.connect()
    let table = DB.Table("list_value_enum_target")
    try await connection.execute(
        SQL
            .create
            .type[any: DB.Object(permissionTypeName)]
            .as
            .enum(Array(ListPermission.allCases.map(\.rawValue)))
    )
    try await connection.execute(
        SQL
            .create
            .table[any: table]
            .tableDefinitions(
                NewColumn("id", .bigint),
                NewColumn("payload", .list(.custom(permissionTypeName)))
            )
    )

    let seed = try await connection.prepare { parameters in
        SQL
            .insertInto(table, fields: "id", "payload")
            .values
            .values(Int64(1), parameters.parameter())
    }
    _ = try await seed.execute(Value.list([.string("create")]))
    #expect(try await countRows(table, on: connection) == 1)

    let failing = try await connection.prepare { parameters in
        SQL
            .insertInto(table, fields: "id", "payload")
            .values
            .values(Int64(2), parameters.parameter())
    }
    do {
        _ = try await failing.execute(Value.list([.string("create"), .string("delete_all")]))
        Issue.record("Expected an unknown ENUM label to fail before binding.")
    } catch let error as DatabaseError {
        guard case .binding = error else {
            Issue.record("Expected a binding failure, got \(error).")
            return
        }
    }

    #expect(try await countRows(table, on: connection) == 1)
}

@Test("L24 scalar LIST children convert exactly and cross-family children stay rejected")
func preparedListScalarChildFamilies() async throws {
    let connection = try Database().connect()

    let epoch = Date(timeIntervalSince1970: 1_700_000_000)
    let day = try #require(PureDate(year: 2026, month: 2, day: 3))
    let time = try #require(PureTime(nanosecondsSinceMidnight: 12_345_678_000_000))
    let dateTime = try #require(DateTime(date: day, time: time))
    let accepted: [(name: String, element: Type, children: [Value])] = [
        ("BOOLEAN", .boolean, [.boolean(true), .boolean(false)]),
        ("TINYINT", .tinyint, [.int8(-8), .int8(8)]),
        ("SMALLINT", .smallint, [.int16(-16), .int16(16)]),
        ("INTEGER", .integer, [.int32(-32), .int32(32)]),
        ("BIGINT", .bigint, [.int64(-64), .int64(64)]),
        ("UTINYINT", .utinyint, [.uint8(8), .uint8(255)]),
        ("USMALLINT", .usmallint, [.uint16(16)]),
        ("UINTEGER", .uinteger, [.uint32(32)]),
        ("UBIGINT", .ubigint, [.uint64(64)]),
        ("FLOAT", .real, [.float(1.5)]),
        ("DOUBLE", .doublePrecision, [.double(2.5)]),
        ("VARCHAR", .varchar, [.string("a"), .string("")]),
        ("BLOB", .blob, [.blob(Data([0x00, 0xFF]))]),
        ("UUID", .uuid, [.uuid(UUID(uuidString: "11111111-1111-1111-1111-111111111111")!)]),
        ("DATE", .date, [.date(try #require(PureDate(year: 2026, month: 2, day: 3)))]),
        ("TIME", .time, [.time(time)]),
        ("TIMESTAMP", .timestamp, [.dateTime(dateTime)]),
        ("TIMESTAMPTZ", .timestamptz, [.timestampTZ(epoch)]),
        ("INTERVAL", .interval, [.interval(Interval(months: 1, days: 2, microseconds: 3))]),
        (
            "DECIMAL",
            .decimal(10, 2),
            [.decimal(try #require(Decimal(string: "12.34", locale: Locale(identifier: "en_US_POSIX"))))]
        )
    ]

    for case let (name, element, children) in accepted {
        let payload = try await queryListPayload(
            on: connection,
            element: element,
            binding: .list(children)
        )
        #expect(payload == Value.list(children), "LIST(\(name)) round-trip")
    }

    // Same-sign widening into a 128-bit element target is lossless; the runtime stores and
    // reports those children as exact 128-bit words.
    let widened = try await queryListPayload(
        on: connection,
        element: .hugeint,
        binding: .list([.int64(-1), .int64(1)])
    )
    #expect(widened == .list([
        Value(signedUpper: -1, lower: UInt64.max),
        Value(signedUpper: 0, lower: 1)
    ]))

    let unsignedWidened = try await queryListPayload(
        on: connection,
        element: .uhugeint,
        binding: .list([.uint64(1)])
    )
    #expect(unsignedWidened == .list([Value(unsignedUpper: 0, lower: 1)]))

    // Rejections: no cross-family coercion, no signed/unsigned crossing, no string parsing,
    // and lossless width rules still apply inside a LIST.
    let rejections: [(String, Type, [Value])] = [
        ("VARCHAR element with an integer child", .varchar, [.int32(1)]),
        ("UINTEGER element with a signed child", .uinteger, [.int32(1)]),
        ("TINYINT element with a too-wide child", .tinyint, [.int64(1000)]),
        ("INTEGER element parsed from text", .integer, [.string("42")]),
        ("BOOLEAN element from an integer", .boolean, [.int32(1)]),
        ("DATE element from text", .date, [.string("2026-02-03")])
    ]

    for case let (label, element, children) in rejections {
        try await expectListRejection(
            connection,
            label: label,
            element: element,
            children: children
        )
    }
}

@Test("L14 nested LIST children are rejected before mutation")
func nestedListChildIsRejected() async throws {
    let database = try Database()
    let connection = try database.connect()
    let table = DB.Table("list_value_nested_target")
    try await connection.execute(
        SQL
            .create
            .table[any: table]
            .tableDefinitions(NewColumn("id", .bigint), NewColumn("payload", .list(.varchar)))
    )

    let statement = try await connection.prepare { parameters in
        SQL
            .insertInto(table, fields: "id", "payload")
            .values
            .values(Int64(1), parameters.parameter())
    }
    await #expect(throws: DatabaseError.self) {
        _ = try await statement.execute(Value.list([.list([.string("inner")])]))
    }
    #expect(try await countRows(table, on: connection) == 0)

    // A LIST-of-LIST element target is rejected too, even when the children would fit.
    let nestedTarget = try await connection.prepare { parameters in
        SQL.select(Fn.cast(parameters.parameter(), .list(.list(.varchar))) => "payload")
    }
    await #expect(throws: DatabaseError.self) {
        _ = try await nestedTarget.query(Value.list([.string("a")]))
    }
}

@Test("L14 STRUCT/MAP/UNION/fixed ARRAY LIST children stay unsupported")
func compositeListChildTargetsAreRejected() async throws {
    let connection = try Database().connect()

    let compositeTargets: [(String, Type)] = [
        ("fixed ARRAY", .array(.varchar, length: 2)),
        ("MAP", .map(key: .varchar, value: .varchar)),
        ("STRUCT", .struct(("id", .integer), ("label", .varchar)))
    ]

    for case let (label, element) in compositeTargets {
        try await expectListRejection(
            connection,
            label: label,
            element: element,
            children: [.string("a")]
        )
    }
}

private func expectListRejection(
    _ connection: Connection,
    label: String,
    element: Type,
    children: [Value]
) async throws {
    let statement = try await connection.prepare { parameters in
        SQL.select(Fn.cast(parameters.parameter(), payloadType(element)) => "payload")
    }
    do {
        _ = try await statement.query(Value.list(children))
        Issue.record("\(label): expected LIST rejection")
    } catch let error as DatabaseError {
        guard case .binding = error else {
            Issue.record("\(label): expected a binding failure, got \(error)")
            return
        }
    }
}

// MARK: - L09-L10: Appender

@Test("L09 Appender persists LIST(VARCHAR) non-empty, empty, with a NULL child and NULL parent")
func appenderListVarchar() throws {
    let database = try NativeDatabase()
    let connection = try database.connect()
    try createNativeListTable(connection, table: "list_appender_varchar", element: .varchar)

    let appender = try NativeAppender(connection: connection, table: "list_appender_varchar")
    try appender.appendRow([.int64(1), .list([.string("a"), .string("b")])])
    try appender.appendRow([.int64(2), .list([])])
    try appender.appendRow([.int64(3), .list([.string("a"), .null, .string("c")])])
    try appender.appendRow([.int64(4), .null])
    try appender.close()

    #expect(try nativeRowCount(connection, table: "list_appender_varchar") == 4)
    #expect(try selectNativeList(connection, table: "list_appender_varchar") == [
        .list([.string("a"), .string("b")]),
        .list([]),
        .list([.string("a"), .null, .string("c")]),
        .null
    ])
}

@Test("L10 Appender persists native LIST(ENUM)")
func appenderListEnum() throws {
    let database = try NativeDatabase()
    let connection = try database.connect()
    try createPermissionEnum(connection)
    try createNativeListTable(
        connection,
        table: "list_appender_enum",
        element: .custom(permissionTypeName)
    )

    let appender = try NativeAppender(connection: connection, table: "list_appender_enum")
    try appender.appendRow([
        .int64(1),
        .list([.string("create"), .string("edit"), .string("delete")])
    ])
    try appender.appendRow([
        .int64(2),
        .list([.string("delete"), .string("create")])
    ])
    try appender.close()

    #expect(try selectNativeList(connection, table: "list_appender_enum") == [
        .list([.string("create"), .string("edit"), .string("delete")]),
        .list([.string("delete"), .string("create")])
    ])
}

@Test("L08/L10 Appender LIST preflight failure never partially appends a row")
func appenderListPreflightFailureDoesNotMutate() throws {
    let database = try NativeDatabase()
    let connection = try database.connect()
    try createPermissionEnum(connection)
    try createNativeListTable(
        connection,
        table: "list_appender_preflight",
        element: .custom(permissionTypeName)
    )

    let appender = try NativeAppender(connection: connection, table: "list_appender_preflight")
    do {
        try appender.appendRow([
            .int64(1),
            .list([.string("create"), .string("not-a-permission")])
        ])
        Issue.record("Expected LIST appender preflight failure.")
    } catch let error as NativeAppenderError {
        #expect(error.isPreflight)
        #expect(error.stage == .appendColumn(2))
    }

    // A retry with a valid payload still works on the same appender.
    try appender.appendRow([.int64(2), .list([.string("edit")])])
    try appender.close()

    #expect(try nativeRowCount(connection, table: "list_appender_preflight") == 1)
    #expect(try selectNativeList(connection, table: "list_appender_preflight") == [
        .list([.string("edit")])
    ])
}

// MARK: - L11-L13: result vectors

@Test("L11 a SQL NULL LIST parent yields Value.null without reading the entry")
func resultParentNullListDoesNotReadEntry() throws {
    let database = try NativeDatabase()
    let connection = try database.connect()
    try createNativeListTable(connection, table: "list_result_null_parent", element: .varchar)

    let appender = try NativeAppender(connection: connection, table: "list_result_null_parent")
    try appender.appendRow([.int64(1), .null])
    try appender.appendRow([.int64(2), .list([.string("a")])])
    try appender.appendRow([.int64(3), .list([])])
    try appender.close()

    // C5: for the invalid parent row the entry bytes are undefined, so only validity decides.
    #expect(try selectNativeList(connection, table: "list_result_null_parent") == [
        .null,
        .list([.string("a")]),
        .list([])
    ])
}

@Test("L12 child offsets and validity produce the exact Value.list per row")
func resultChildOffsetsAndValidityAreExact() throws {
    let database = try NativeDatabase()
    let connection = try database.connect()
    try createNativeListTable(connection, table: "list_result_offsets", element: .varchar)

    // Mirrors the probe layout: 2 + 0 + 3 referenced children share one flattened vector,
    // so each row must read from its own offset within the child vector.
    let appender = try NativeAppender(connection: connection, table: "list_result_offsets")
    try appender.appendRow([.int64(1), .list([.string("a"), .string("b")])])
    try appender.appendRow([.int64(2), .list([])])
    try appender.appendRow([.int64(3), .list([.string("a"), .null, .string("c")])])
    try appender.appendRow([.int64(4), .null])
    try appender.close()

    #expect(try selectNativeList(connection, table: "list_result_offsets") == [
        .list([.string("a"), .string("b")]),
        .list([]),
        .list([.string("a"), .null, .string("c")]),
        .null
    ])
}

@Test("L13 ENUM physical dictionary index widths materialize their labels")
func resultEnumPhysicalIndexWidths() throws {
    let database = try NativeDatabase()
    let connection = try database.connect()
    try createPermissionEnum(connection)
    _ = try execute(
        connection,
        SQL
            .create
            .type[any: DB.Object(widePermissionTypeName)]
            .as
            .enum((0..<300).map { "w\($0)" })
    )

    // DuckDB picks the physical index width from the dictionary size, so the two tables
    // exercise the narrow and the wider index readers.
    try createNativeListTable(
        connection,
        table: "list_enum_narrow",
        element: .custom(permissionTypeName)
    )
    try createNativeListTable(
        connection,
        table: "list_enum_wide",
        element: .custom(widePermissionTypeName)
    )

    let narrow = try NativeAppender(connection: connection, table: "list_enum_narrow")
    try narrow.appendRow([
        .int64(1),
        .list([.string("create"), .string("delete"), .string("edit")])
    ])
    try narrow.close()

    let wide = try NativeAppender(connection: connection, table: "list_enum_wide")
    try wide.appendRow([
        .int64(1),
        .list([.string("w0"), .string("w299"), .string("w255"), .string("w256")])
    ])
    try wide.close()

    #expect(try selectNativeList(connection, table: "list_enum_narrow") == [
        .list([.string("create"), .string("delete"), .string("edit")])
    ])
    #expect(try selectNativeList(connection, table: "list_enum_wide") == [
        .list([.string("w0"), .string("w299"), .string("w255"), .string("w256")])
    ])

    // The two dictionaries differ in size, which is what makes DuckDB store their index
    // physically differently; both must still resolve to the exact labels above.
    #expect(try enumChildKind(connection, element: permissionTypeName) == .enumeration)
    #expect(try enumChildKind(connection, element: widePermissionTypeName) == .enumeration)
    #expect(try enumDictionarySize(connection, element: permissionTypeName) == 3)
    #expect(try enumDictionarySize(connection, element: widePermissionTypeName) == 300)
}

private func enumChildLogicalType(
    _ connection: NativeConnection,
    element: String
) throws -> LogicalType {
    // Casting SQL NULL only inspects type metadata; it never constructs a LIST value.
    let result = try execute(
        connection,
        SQL.select(Fn.cast(SQL.null, .list(.custom(element))) => "payload")
    )
    let column = try #require(result.resultColumns().first)
    guard case .list(let child) = column.logicalType.detail else {
        Issue.record("Expected a LIST descriptor.")
        return LogicalType(id: .invalid)
    }
    return child
}

private func enumChildKind(
    _ connection: NativeConnection,
    element: String
) throws -> LogicalTypeID {
    try enumChildLogicalType(connection, element: element).id
}

private func enumDictionarySize(
    _ connection: NativeConnection,
    element: String
) throws -> Int {
    guard case .enumeration(let labels) = try enumChildLogicalType(
        connection,
        element: element
    ).detail else {
        Issue.record("Expected an ENUM dictionary.")
        return -1
    }
    return labels.count
}

// MARK: - R01 ownership stress

@Test("R01 repeated LIST prepared bind and Appender success/failure loops stay stable")
func ownershipStressLoops() async throws {
    let database = try Database()
    let connection = try database.connect()
    let table = DB.Table("list_value_ownership")
    try await connection.execute(
        SQL
            .create
            .type[any: DB.Object(permissionTypeName)]
            .as
            .enum(Array(ListPermission.allCases.map(\.rawValue)))
    )
    try await connection.execute(
        SQL
            .create
            .table[any: table]
            .tableDefinitions(
                NewColumn("id", .bigint),
                NewColumn("payload", .list(.varchar)),
                NewColumn("permissions", .list(.custom(permissionTypeName)))
            )
    )

    let children: [Value] = [.string("a"), .null, .string("c")]

    // Success path: parent target, derived child target, temporary child values and the
    // returned parent LIST value are each released exactly once per iteration.
    for index in 0..<200 {
        let statement = try await connection.prepare { parameters in
            SQL
                .insertInto(table, fields: "id", "payload")
                .values
                .values(Int64(index), parameters.parameter())
        }
        _ = try await statement.execute(Value.list(children))
    }
    #expect(try await countRows(table, on: connection) == 200)

    // Failure paths still release the borrowed parent target and codec-owned child resources.
    for _ in 0..<200 {
        let mismatched = try await connection.prepare { parameters in
            SQL
                .insertInto(table, fields: "id", "permissions")
                .values
                .values(Int64(0), parameters.parameter())
        }
        _ = try? await mismatched.execute(Value.list(children))
    }

    let enumTarget = try await connection.prepare { parameters in
        SQL
            .insertInto(table, fields: "id", "permissions")
            .values
            .values(Int64(1), parameters.parameter())
    }
    await #expect(throws: DatabaseError.self) {
        _ = try await enumTarget.execute(Value.list([.string("create"), .string("nope")]))
    }

    // ENUM success rows persist, then a long read-back loop over LIST and LIST(ENUM) vectors.
    for index in 0..<200 {
        let statement = try await connection.prepare { parameters in
            SQL
                .insertInto(table, fields: "id", "permissions")
                .values
                .values(Int64(index), parameters.parameter())
        }
        _ = try await statement.execute(Value.list([.string("edit"), .string("delete")]))
    }

    for _ in 0..<50 {
        let result = try await connection.query(
            SQL.select(table.column("payload"), table.column("permissions")).from(table)
        )
        #expect(result.rows.count == 400)
    }

    // Appender success/failure loops through the same owned-value cleanup discipline.
    let appended = DB.Table("list_value_ownership_appender")
    let native = try NativeDatabase()
    let nativeConnection = try native.connect()
    try createPermissionEnum(nativeConnection)
    try createNativeListTable(
        nativeConnection,
        table: appended.name,
        element: .custom(permissionTypeName)
    )
    let appender = try NativeAppender(connection: nativeConnection, table: appended.name)
    for index in 0..<200 {
        try appender.appendRow([
            .int64(Int64(index)),
            .list([.string("edit"), .string("delete")])
        ])
    }
    for _ in 0..<200 {
        #expect(throws: NativeAppenderError.self) {
            try appender.appendRow([.int64(0), .list([.string("nope")])])
        }
    }
    try appender.close()
    #expect(try nativeRowCount(nativeConnection, table: appended.name) == 200)

    for _ in 0..<50 {
        _ = try selectNativeList(nativeConnection, table: appended.name)
    }
}

private func countRows(_ table: DB.Table, on connection: Connection) async throws -> Int64 {
    let result = try await connection.query(
        SQL
            .select(Fn.cast(Fn.count(SQL.asterisk), .bigint) => "count")
            .from(table)
    )
    let value = try #require(result.rows.first?["count"])
    return try #require(value.get(Int64.self))
}

// MARK: - L15-L25 are owned by CodableEncodingTests and CodableDecodingTests.

// MARK: - L26-L34: model persistence

private func createListUserSchema(on connection: Connection) async throws {
    try await connection.execute(
        SQL
            .create
            .type[any: DB.Object(permissionTypeName)]
            .as
            .enum(Array(ListPermission.allCases.map(\.rawValue)))
    )
    try await connection.execute(
        SQL
            .create
            .table[any: listUsersTable]
            .tableDefinitions(
                NewColumn("id", .bigint).primaryKey(),
                NewColumn("tags", .list(.varchar)).notNull(),
                NewColumn("permissions", .list(.custom(permissionTypeName))).notNull(),
                NewColumn("note", .varchar).default(
                    expression: SQL.default[any: SQLableParts(parts: SQLPartSafeValue("fallback-note"))]
                )
            )
    )
}

@Test("L26 Connection insert returning exact arrays")
func connectionInsertReturningExactArrays() async throws {
    let connection = try Database().connect()
    try await createListUserSchema(on: connection)

    let inserted = try await ListUser(
        id: 1,
        tags: ["alpha", "beta"],
        permissions: [.create, .edit]
    ).insert(on: connection)
    #expect(inserted.id == 1)
    #expect(inserted.tags == ["alpha", "beta"])
    #expect(inserted.permissions == [.create, .edit])

    let stored = try await ListUser
        .select
        .where(listUsersTable.column("id") == 1)
        .limit(1)
        .query(on: connection)
        .first(decoding: ListUser.self)
    #expect(stored?.tags == ["alpha", "beta"])
    #expect(stored?.permissions == [.create, .edit])

    let empty = try await ListUser(id: 2, tags: [], permissions: []).insert(on: connection)
    #expect(empty.tags.isEmpty)
    #expect(empty.permissions.isEmpty)
}

@Test("L26 Connection insert preserves NULL LIST elements")
func connectionInsertPreservesNullListElements() async throws {
    let connection = try Database().connect()
    try await connection.execute(
        SQL
            .create
            .table[any: listNullableUsersTable]
            .tableDefinitions(
                NewColumn("id", .bigint).primaryKey(),
                NewColumn("tags", .list(.varchar)).notNull()
            )
    )

    let inserted = try await ListNullableUser(id: 1, tags: ["keep", nil, "last"]).insert(
        on: connection
    )
    #expect(inserted.tags == ["keep", nil, "last"])

    let stored = try await ListNullableUser
        .select
        .where(listNullableUsersTable.column("id") == 1)
        .limit(1)
        .query(on: connection)
        .first(decoding: ListNullableUser.self)
    #expect(stored?.tags == ["keep", nil, "last"])
}

@Test("L27 Connection update carries exact arrays")
func connectionUpdateCarriesExactArrays() async throws {
    let connection = try Database().connect()
    try await createListUserSchema(on: connection)

    let inserted = try await ListUser(
        id: 1,
        tags: ["alpha"],
        permissions: [.create]
    ).insert(on: connection)

    inserted.tags = ["gamma", "delta"]
    inserted.permissions = [.delete]
    let updated = try await inserted.update(on: \.$id, on: connection)
    #expect(updated.tags == ["gamma", "delta"])
    #expect(updated.permissions == [.delete])

    let stored = try await ListUser
        .select
        .where(listUsersTable.column("id") == 1)
        .limit(1)
        .query(on: connection)
        .first(decoding: ListUser.self)
    #expect(stored?.tags == ["gamma", "delta"])
    #expect(stored?.permissions == [.delete])
}

@Test("L28 Connection upsert carries exact arrays through the existing UPSERT path")
func connectionUpsertCarriesExactArrays() async throws {
    let connection = try Database().connect()
    try await createListUserSchema(on: connection)

    _ = try await ListUser(id: 1, tags: ["first"], permissions: [.create]).insert(on: connection)

    let incoming = ListUser(id: 1, tags: ["delta", "epsilon"], permissions: [.edit, .delete])
    let upserted = try await incoming.upsert(conflictColumn: \.$id, on: connection)
    #expect(upserted.tags == ["delta", "epsilon"])
    #expect(upserted.permissions == [.edit, .delete])

    let stored = try await ListUser
        .select
        .where(listUsersTable.column("id") == 1)
        .limit(1)
        .query(on: connection)
        .first(decoding: ListUser.self)
    #expect(stored?.tags == ["delta", "epsilon"])
    #expect(stored?.permissions == [.edit, .delete])
}

@Test("L29 Collection batchInsert through Appender carries exact arrays")
func batchInsertCarriesExactArrays() async throws {
    let connection = try Database().connect()
    try await createListUserSchema(on: connection)

    try await [
        ListUser(id: 10, tags: ["batch-a", "batch-b"], permissions: [.create]),
        ListUser(id: 11, tags: [], permissions: [.delete, .edit]),
        ListUser(id: 12, tags: ["only"], permissions: [])
    ].batchInsert(on: connection)

    let batched = try await ListUser
        .select
        .where(listUsersTable.column("id") >= 10)
        .orderBy(.asc(listUsersTable.column("id")))
        .query(on: connection)
        .all(decoding: ListUser.self)

    #expect(batched.count == 3)
    #expect(batched[0].tags == ["batch-a", "batch-b"])
    #expect(batched[0].permissions == [.create])
    #expect(batched[1].tags == [])
    #expect(batched[1].permissions == [.delete, .edit])
    #expect(batched[2].tags == ["only"])
    #expect(batched[2].permissions == [])
}

@Test("L30 DatabaseIdentifier public target inserts and reads LIST properties")
func databaseIdentifierTarget() async throws {
    let identifier = DatabaseIdentifier.memory()

    try await SQL
        .create
        .type[any: DB.Object(permissionTypeName)]
        .as
        .enum(Array(ListPermission.allCases.map(\.rawValue)))
        .execute(on: identifier)
    try await SQL
        .create
        .table[any: listUsersTable]
        .tableDefinitions(
            NewColumn("id", .bigint).primaryKey(),
            NewColumn("tags", .list(.varchar)).notNull(),
            NewColumn("permissions", .list(.custom(permissionTypeName))).notNull()
        )
        .execute(on: identifier)

    let inserted = try await ListUser(
        id: 1,
        tags: ["identifier", "second"],
        permissions: [.create, .edit, .delete]
    ).insert(on: identifier)
    #expect(inserted.tags == ["identifier", "second"])
    #expect(inserted.permissions == [.create, .edit, .delete])

    let readBack = try await ListUser
        .select
        .where(listUsersTable.column("id") == 1)
        .limit(1)
        .query(on: identifier)
        .first(decoding: ListUser.self)
    #expect(readBack?.tags == ["identifier", "second"])
    #expect(readBack?.permissions == [.create, .edit, .delete])

    try await [
        ListUser(id: 2, tags: [], permissions: [.edit])
    ].batchInsert(on: identifier)

    let batched = try await ListUser
        .select
        .where(listUsersTable.column("id") == 2)
        .limit(1)
        .query(on: identifier)
        .first(decoding: ListUser.self)
    #expect(batched?.tags == [])
    #expect(batched?.permissions == [.edit])
}

@Test("L31 DuckTransaction insert/update/read then rollback proves no committed row")
func transactionRollbackLeavesNoCommittedList() async throws {
    let database = try Database()
    let connection = try database.connect()
    try await createListUserSchema(on: connection)

    do {
        try await connection.transaction { transaction in
            try await ListUser(id: 1, tags: ["inside"], permissions: [.create])
                .insertNonReturning(on: transaction)

            let inside = try await ListUser
                .select
                .where(listUsersTable.column("id") == 1)
                .limit(1)
                .query(on: transaction)
                .first(decoding: ListUser.self)
            #expect(inside?.tags == ["inside"])
            #expect(inside?.permissions == [.create])

            throw ListRollbackFailure.rollback
        }
        Issue.record("Expected the transaction body to roll back.")
    } catch ListRollbackFailure.rollback {
        // The managed transaction must roll the LIST insert back.
    }

    let afterRollback = try await ListUser
        .select
        .where(listUsersTable.column("id") == 1)
        .limit(1)
        .query(on: connection)
        .first(decoding: ListUser.self)
    #expect(afterRollback == nil)

    // The committed branch keeps the exact arrays.
    try await connection.transaction { transaction in
        try await ListUser(id: 2, tags: ["committed"], permissions: [.delete, .edit])
            .insertNonReturning(on: transaction)
    }
    let committed = try await ListUser
        .select
        .where(listUsersTable.column("id") == 2)
        .limit(1)
        .query(on: connection)
        .first(decoding: ListUser.self)
    #expect(committed?.tags == ["committed"])
    #expect(committed?.permissions == [.delete, .edit])
}

@Test("L31 LIST writes survive a committed transaction and stay visible")
func listValueReadsInsideTransactionRollbackAreConsistent() async throws {
    let database = try Database()
    let connection = try database.connect()
    try await createListUserSchema(on: connection)

    _ = try await ListUser(id: 1, tags: ["durable"], permissions: [.create]).insert(on: connection)

    do {
        try await connection.transaction { transaction in
            let loaded = try await ListUser
                .select
                .where(listUsersTable.column("id") == 1)
                .limit(1)
                .query(on: transaction)
                .first(decoding: ListUser.self)
            let existing = try #require(loaded)
            existing.tags = ["changed"]
            _ = try await existing.update(on: \.$id, on: transaction)
            throw ListRollbackFailure.rollback
        }
        Issue.record("Expected the transaction body to roll back.")
    } catch ListRollbackFailure.rollback {
        // The managed transaction must roll the LIST update back.
    }

    let afterRollback = try await ListUser
        .select
        .where(listUsersTable.column("id") == 1)
        .limit(1)
        .query(on: connection)
        .first(decoding: ListUser.self)
    #expect(afterRollback?.tags == ["durable"])
}

@Test("L32-L34 schema target, DEFAULT-vs-NULL and changed-field selection stay preserved")
func persistenceSemanticsRemainUnchanged() async throws {
    let database = try Database()
    let connection = try database.connect()
    try await createListUserSchema(on: connection)

    // L33: an uninitialized unrelated field still receives the database DEFAULT.
    _ = try await ListUser(id: 1, tags: ["a"], permissions: [.create]).insert(on: connection)
    let defaulted = try await connection.query(
        SQL.select(listUsersTable.column("note")).from(listUsersTable)
    )
    #expect(defaulted.rows.first?["note"] == Value.string("fallback-note"))

    // L33: an explicitly initialized nil binds SQL NULL instead of the DEFAULT.
    _ = try await ListUser(
        id: 2,
        tags: ["b"],
        permissions: [.edit],
        note: nil
    ).insert(on: connection)
    let explicitNull = try await ListUser
        .select
        .where(listUsersTable.column("id") == 2)
        .limit(1)
        .query(on: connection)
        .first(decoding: ListUser.self)
    #expect(explicitNull?.note == nil)

    // L34: only the changed LIST field is rewritten; untouched fields keep their values.
    let loaded = try #require(await ListUser
        .select
        .where(listUsersTable.column("id") == 1)
        .limit(1)
        .query(on: connection)
        .first(decoding: ListUser.self))
    #expect(loaded.tags == ["a"])
    loaded.tags = ["changed"]
    _ = try await loaded.update(on: \.$id, on: connection)

    let afterUpdate = try #require(await ListUser
        .select
        .where(listUsersTable.column("id") == 1)
        .limit(1)
        .query(on: connection)
        .first(decoding: ListUser.self))
    #expect(afterUpdate.tags == ["changed"])
    #expect(afterUpdate.permissions == [.create])
    #expect(afterUpdate.note == "fallback-note")

    // L34: UPSERT keeps the same changed-field selection for LIST properties.
    let incoming = ListUser(id: 1, tags: ["upserted"], permissions: [.delete])
    let upserted = try await incoming.upsert(conflictColumn: \.$id, on: connection)
    #expect(upserted.tags == ["upserted"])
    #expect(upserted.permissions == [.delete])

    // L32: a schema-qualified LIST target still works end to end.
    try await connection.execute(SQL.create.schema[any: DB.Object("list_value_schema")])
    let scoped = DB.Schema("list_value_schema").table("list_value_scoped")
    try await connection.execute(
        SQL
            .create
            .table[any: scoped]
            .tableDefinitions(
                NewColumn("id", .bigint).primaryKey(),
                NewColumn("tags", .list(.varchar)).notNull()
            )
    )
    let scopedStatement = try await connection.prepare { parameters in
        SQL
            .insertInto(scoped, fields: "id", "tags")
            .values
            .values(Int64(1), parameters.parameter())
    }
    _ = try await scopedStatement.execute(Value.list([.string("scoped")]))

    let scopedResult = try await connection.query(
        SQL.select(scoped.column("tags")).from(scoped)
    )
    #expect(scopedResult.rows.first?["tags"] == Value.list([.string("scoped")]))
}
