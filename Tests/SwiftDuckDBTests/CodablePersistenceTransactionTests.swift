@testable import SwiftDuckDB
import Foundation
import SwifQL
import Testing

// MARK: - Models

private enum WaveEStatus: String, Codable, Equatable, Sendable {
    case active
    case paused
    case archived
}

private struct WaveEAccount: Table {
    static let tableName = "codable_wave_e_accounts"

    @Column("id", default: .default(100))
    var id: Int64?

    @Column("name")
    var name: String

    @Column("nickname", default: .default("wave-e-default"))
    var nickname: String?

    @Column("score")
    var score: Int

    @Column("external_id")
    var externalId: UUID

    @Column("amount")
    var amount: Decimal

    @Column("status")
    var status: WaveEStatus

    init() {}

    init(
        id: Int64? = nil,
        name: String,
        nickname: String? = nil,
        score: Int,
        externalId: UUID,
        amount: Decimal,
        status: WaveEStatus
    ) {
        self._id = Column("id", default: .default(100))
        self._name = Column("name")
        self._nickname = Column("nickname", default: .default("wave-e-default"))
        self._score = Column("score")
        self._externalId = Column("external_id")
        self._amount = Column("amount")
        self._status = Column("status")

        self.name = name
        self.score = score
        self.externalId = externalId
        self.amount = amount
        self.status = status
        if let id {
            self.id = id
        }
        if let nickname {
            self.nickname = nickname
        }
    }
}

/// Dedicated model whose table is intentionally never created for rollback-only proof.
private struct WaveEMissingTarget: Table {
    static let tableName = "codable_wave_e_missing_target"

    @Column("id")
    var id: Int64?

    @Column("label")
    var label: String

    init() {}

    init(id: Int64? = nil, label: String) {
        self._id = Column("id")
        self._label = Column("label")
        self.label = label
        if let id {
            self.id = id
        }
    }
}

private struct WaveEBodyFailure: Error {}

// MARK: - Fixtures

private let waveEUUID = UUID(uuid: (
    0x12, 0x34, 0x56, 0x78,
    0x9a, 0xbc,
    0xde, 0xf0,
    0x11, 0x22,
    0x33, 0x44, 0x55, 0x66, 0x77, 0x88
))
private let waveEDecimal = Decimal(
    sign: .plus,
    exponent: -2,
    significand: Decimal(99_887)
)

private func makeWaveEAccount(
    id: Int64? = nil,
    name: String,
    nickname: String? = nil,
    score: Int = 10,
    status: WaveEStatus = .active
) -> WaveEAccount {
    WaveEAccount(
        id: id,
        name: name,
        nickname: nickname,
        score: score,
        externalId: waveEUUID,
        amount: waveEDecimal,
        status: status
    )
}

private func createWaveETable(on connection: Connection) async throws {
    try await CreateTableBuilder<WaveEAccount>()
        .checkIfNotExists()
        .column("id", .bigint, ColumnDefault.default(100 as Any))
        .column("name", .text, .notNull)
        .column("nickname", .text, ColumnDefault.default("wave-e-default" as Any))
        .column("score", .bigint, .notNull)
        .column("external_id", .uuid, .notNull)
        .column("amount", .decimal(18, 2), .notNull)
        .column("status", .text, .notNull)
        .execute(on: connection)
}

private func fetchWaveEAccount(id: Int64, on connection: Connection) async throws -> WaveEAccount? {
    try await WaveEAccount
        .select
        .where(Path.Column("id") == id)
        .limit(1)
        .query(on: connection)
        .first(decoding: WaveEAccount.self)
}

// MARK: - E-T01

@Test("Transaction INSERT returning commits DB defaults and exact round-trip")
func transactionInsertReturningCommits() async throws {
    let connection = try Database().connect()
    try await createWaveETable(on: connection)

    let model = makeWaveEAccount(
        name: "wave-e-insert-returning",
        score: 7,
        status: .paused
    )

    let inserted = try await connection.transaction { transaction in
        try await model.insert(on: transaction)
    }

    #expect(inserted.id == 100)
    #expect(inserted.nickname == "wave-e-default")
    #expect(inserted.name == "wave-e-insert-returning")
    #expect(inserted.score == 7)
    #expect(inserted.externalId == waveEUUID)
    #expect(inserted.amount == waveEDecimal)
    #expect(inserted.status == .paused)

    let fetched = try #require(try await fetchWaveEAccount(id: 100, on: connection))
    #expect(fetched.id == 100)
    #expect(fetched.nickname == "wave-e-default")
    #expect(fetched.name == "wave-e-insert-returning")
    #expect(fetched.score == 7)
    #expect(fetched.externalId == waveEUUID)
    #expect(fetched.amount == waveEDecimal)
    #expect(fetched.status == .paused)
}

// MARK: - E-T02

@Test("Transaction INSERT non-returning rolls back on body error")
func transactionInsertNonReturningRollsBack() async throws {
    let connection = try Database().connect()
    try await createWaveETable(on: connection)

    let model = makeWaveEAccount(
        name: "wave-e-insert-rollback",
        score: 3,
        status: .archived
    )

    do {
        try await connection.transaction { transaction in
            try await model.insertNonReturning(on: transaction)
            throw WaveEBodyFailure()
        }
        Issue.record("Expected WaveEBodyFailure from transaction body")
    } catch is WaveEBodyFailure {
        // Expected body-error rollback path.
    }

    let fetched = try await fetchWaveEAccount(id: 100, on: connection)
    #expect(fetched == nil)
}

// MARK: - E-T03

@Test("Transaction UPDATE returning commits durable non-key change")
func transactionUpdateReturningCommits() async throws {
    let connection = try Database().connect()
    try await createWaveETable(on: connection)

    let baseline = try await makeWaveEAccount(
        name: "wave-e-update-before",
        score: 11,
        status: .active
    ).insert(on: connection)
    #expect(baseline.id == 100)

    baseline.name = "wave-e-update-after"
    baseline.score = 22
    baseline.status = .archived

    let updated = try await connection.transaction { transaction in
        try await baseline.update(on: \.$id, on: transaction)
    }

    #expect(updated.id == 100)
    #expect(updated.name == "wave-e-update-after")
    #expect(updated.score == 22)
    #expect(updated.status == .archived)
    #expect(updated.nickname == "wave-e-default")
    #expect(updated.externalId == waveEUUID)
    #expect(updated.amount == waveEDecimal)

    let fetched = try #require(try await fetchWaveEAccount(id: 100, on: connection))
    #expect(fetched.name == "wave-e-update-after")
    #expect(fetched.score == 22)
    #expect(fetched.status == .archived)
    #expect(fetched.nickname == "wave-e-default")
}

// MARK: - E-T04

@Test("Transaction UPDATE non-returning rolls back on body error")
func transactionUpdateNonReturningRollsBack() async throws {
    let connection = try Database().connect()
    try await createWaveETable(on: connection)

    let baseline = try await makeWaveEAccount(
        name: "wave-e-update-keep",
        score: 15,
        status: .active
    ).insert(on: connection)

    baseline.name = "wave-e-update-should-rollback"
    baseline.score = 99
    baseline.status = .paused

    do {
        try await connection.transaction { transaction in
            try await baseline.updateNonReturning(on: \.$id, on: transaction)
            throw WaveEBodyFailure()
        }
        Issue.record("Expected WaveEBodyFailure from transaction body")
    } catch is WaveEBodyFailure {
        // Expected body-error rollback path.
    }

    let fetched = try #require(try await fetchWaveEAccount(id: 100, on: connection))
    #expect(fetched.name == "wave-e-update-keep")
    #expect(fetched.score == 15)
    #expect(fetched.status == .active)
}

// MARK: - E-T05

@Test("Transaction model execution failure participates in rollback-only first-error propagation")
func transactionModelFailureParticipatesInRollbackOnly() async throws {
    let connection = try Database().connect()
    // WaveEMissingTarget.table is intentionally not created.
    let model = WaveEMissingTarget(label: "wave-e-missing")

    var storedFirstFailure: DatabaseError?

    do {
        try await connection.transaction { transaction in
            do {
                _ = try await model.insert(on: transaction)
                Issue.record("Expected DatabaseError from insert against missing table")
            } catch let error as DatabaseError {
                storedFirstFailure = error
            }

            guard let firstFailure = storedFirstFailure else {
                return
            }

            do {
                _ = try await transaction.query(
                    SwifQL.select(Fn.cast(Int32(1), .integer) => "value")
                )
                Issue.record("Expected later transaction.query to throw stored first failure")
            } catch let laterError as DatabaseError {
                #expect(laterError == firstFailure)
            }

            return
        }
        Issue.record("Expected transaction finalization to throw stored first failure")
    } catch let finalizationError as DatabaseError {
        let firstFailure = try #require(storedFirstFailure)
        #expect(finalizationError == firstFailure)
    }
}

// MARK: - E-T06

@Test("Escaped Transaction rejects actual SQL persistence with transactionEnded")
func escapedTransactionRejectsPersistence() async throws {
    let connection = try Database().connect()
    try await createWaveETable(on: connection)

    var escaped: Transaction?
    try await connection.transaction { transaction in
        escaped = transaction
    }

    guard let escaped else {
        Issue.record("Expected escaped Transaction capture")
        return
    }

    let model = makeWaveEAccount(
        name: "wave-e-escaped-insert",
        score: 5,
        status: .paused
    )

    do {
        _ = try await model.insert(on: escaped)
        Issue.record("Expected escaped Transaction insert to throw")
    } catch let error as DatabaseError {
        #expect(error == .transactionEnded)
    }

    let fetched = try await fetchWaveEAccount(id: 100, on: connection)
    #expect(fetched == nil)
}

// MARK: - E-T07

@Test("Zero-changed Transaction UPDATE performs no SQL-visible access after drop")
func zeroChangedTransactionUpdateNoSQLAfterDrop() async throws {
    let connection = try Database().connect()
    try await createWaveETable(on: connection)

    let decoded = try await makeWaveEAccount(
        name: "wave-e-noop",
        score: 8,
        status: .active
    ).insert(on: connection)

    try await connection.transaction { transaction in
        try await DropTableBuilder<WaveEAccount>()
            .checkIfExists()
            .execute(on: transaction)

        let same = try await decoded.update(on: \.$id, on: transaction)
        #expect(same.id == decoded.id)
        #expect(same.name == decoded.name)
        #expect(same.score == decoded.score)
        #expect(same.nickname == decoded.nickname)
        #expect(same.externalId == decoded.externalId)
        #expect(same.amount == decoded.amount)
        #expect(same.status == decoded.status)

        try await decoded.updateNonReturning(on: \.$id, on: transaction)
    }
}
