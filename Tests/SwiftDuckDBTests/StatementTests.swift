@testable import SwiftDuckDB
import SwifQL
import Testing

private struct UnsupportedStatementBinding: Encodable, SwifQLable {
    let value: String

    var parts: [SwifQLPart] {
        [SwifQLPartUnsafeValue(self)]
    }
}

private final class StatefulStatementTemplateValue: SwifQLable {
    private let builder: (Int) -> [SwifQLPart]
    private(set) var evaluationCount = 0

    init(builder: @escaping (Int) -> [SwifQLPart]) {
        self.builder = builder
    }

    var parts: [SwifQLPart] {
        evaluationCount += 1
        return builder(evaluationCount)
    }
}

private struct StatementTemplateProbeArray: SwifQLPartArray {
    let elements: [SwifQLable]
}

private func requireSendable<ValueType: Sendable>(_: ValueType.Type) {}

@Test("Stateful top-level template graph is rendered once")
func statefulTopLevelStatementTemplateUsesOneRender() throws {
    let parameters = Statement.Parameters()
    let parameter = parameters.parameter()
    let query = StatefulStatementTemplateValue { evaluation in
        if evaluation == 1 {
            return SwifQL.select(Fn.cast(parameter, .integer) => "value").parts
        }
        return SwifQL.select(Fn.cast(Int32(99), .integer) => "value").parts
    }

    let snapshot = try StatementTemplateSnapshot(query, parameters: parameters)

    #expect(query.evaluationCount == 1)
    #expect(snapshot.dynamicArgumentCount == 1)
    #expect(snapshot.bindingLayout == [.dynamic(0)])
}

@Test("Stateful nested template value is rendered once")
func statefulNestedStatementTemplateUsesOneRender() throws {
    let parameters = Statement.Parameters()
    let parameter = parameters.parameter()
    let child = StatefulStatementTemplateValue { evaluation in
        if evaluation == 1 {
            return parameter.parts
        }
        return [SwifQLPartUnsafeValue(Int32(99))]
    }
    let arrayPart: SwifQLPart = StatementTemplateProbeArray(elements: [child])
    let query = SwifQL.select(SwifQLableParts(parts: [arrayPart]))

    let snapshot = try StatementTemplateSnapshot(query, parameters: parameters)

    #expect(child.evaluationCount == 1)
    #expect(snapshot.dynamicArgumentCount == 1)
    #expect(snapshot.bindingLayout == [.dynamic(0)])
}

@Test("Direct template rejects an escaped bound Statement.Parameter")
func directStatementTemplateRejectsEscapedBoundParameter() throws {
    let parameters = Statement.Parameters()
    let escaped = parameters.parameter()

    do {
        _ = try StatementTemplateSnapshot(
            SwifQL.select(Fn.cast(escaped, .integer) => "value")
        )
        Issue.record("Expected direct prepare of an escaped bound Statement.Parameter to be rejected.")
    } catch let error as DatabaseError {
        guard case .invalidStatementTemplate = error else {
            Issue.record("Expected invalidStatementTemplate, got \(error).")
            return
        }
    }
}

@Test("Statement is truthfully Sendable and installs one dynamic parameter")
func statementSendabilityAndSingleParameter() async throws {
    requireSendable(Statement.self)

    let connection = try Database().connect()
    let statement = try await connection.prepare { parameters -> any SwifQLable in
        let value = parameters.parameter()
        return SwifQL.select(Fn.cast(value, .integer) => "value")
    }

    #expect(statement.dynamicArgumentCount == 1)
    #expect(await connection.preparedStatementDynamicArgumentCount(statement.id) == 1)
    #expect(await connection.preparedStatementBindingLayout(statement.id) == [.dynamic(0)])
}

@Test("Statement parameter creation order is independent from SQL occurrence order")
func statementParameterCreationOrderIsIndependentFromOccurrenceOrder() async throws {
    let connection = try Database().connect()
    let statement = try await connection.prepare { parameters in
        let first = parameters.parameter()
        let second = parameters.parameter()
        return SwifQL.select(
            Fn.cast(second, .integer) => "second",
            Fn.cast(first, .integer) => "first"
        )
    }

    #expect(statement.dynamicArgumentCount == 2)
    #expect(
        await connection.preparedStatementBindingLayout(statement.id)
            == [.dynamic(1), .dynamic(0)]
    )
}

@Test("Repeated logical parameter maps every SQL slot to one dynamic argument")
func repeatedStatementParameterUsesOneDynamicArgument() async throws {
    let connection = try Database().connect()
    let statement = try await connection.prepare { parameters in
        let value = parameters.parameter()
        return SwifQL.select(
            Fn.cast(value, .integer) => "first",
            Fn.cast(value, .integer) => "second"
        )
    }

    #expect(statement.dynamicArgumentCount == 1)
    #expect(
        await connection.preparedStatementBindingLayout(statement.id)
            == [.dynamic(0), .dynamic(0)]
    )
}

@Test("Fixed and dynamic bindings preserve exact native slot order")
func fixedAndDynamicStatementBindingOrder() async throws {
    let connection = try Database().connect()
    let statement = try await connection.prepare { parameters in
        let value = parameters.parameter()
        return SwifQL.select(
            Fn.cast(Int32(7), .integer) => "fixed",
            Fn.cast(value, .integer) => "dynamic"
        )
    }

    #expect(statement.dynamicArgumentCount == 1)
    #expect(
        await connection.preparedStatementBindingLayout(statement.id)
            == [.fixed(.int32(7)), .dynamic(0)]
    )
}

@Test("Direct prepare installs a zero-dynamic fixed template")
func directStatementPrepareHasZeroDynamicArguments() async throws {
    let connection = try Database().connect()
    let statement = try await connection.prepare(
        SwifQL.select(Fn.cast(Int32(42), .integer) => "value")
    )

    #expect(statement.dynamicArgumentCount == 0)
    #expect(await connection.preparedStatementDynamicArgumentCount(statement.id) == 0)
    #expect(
        await connection.preparedStatementBindingLayout(statement.id)
            == [.fixed(.int32(42))]
    )
}

@Test("Unused Statement.Parameter is rejected")
func unusedStatementParameterIsRejected() async throws {
    let connection = try Database().connect()

    do {
        _ = try await connection.prepare { parameters in
            _ = parameters.parameter()
            return SwifQL.select(Fn.cast(Int32(1), .integer) => "value")
        }
        Issue.record("Expected an unused Statement.Parameter to be rejected.")
    } catch let error as DatabaseError {
        guard case .invalidStatementTemplate = error else {
            Issue.record("Expected invalidStatementTemplate, got \(error).")
            return
        }
    }
}

@Test("Foreign Statement.Parameter is rejected")
func foreignStatementParameterIsRejected() async throws {
    let connection = try Database().connect()
    var foreignParameter: Statement.Parameter?

    do {
        _ = try await connection.prepare { parameters in
            foreignParameter = parameters.parameter()
            return SwifQL.select(Fn.cast(Int32(1), .integer) => "value")
        }
        Issue.record("Expected the source builder's unused parameter to be rejected.")
    } catch let error as DatabaseError {
        guard case .invalidStatementTemplate = error else {
            Issue.record("Expected invalidStatementTemplate, got \(error).")
            return
        }
    }

    let foreign = try #require(foreignParameter)
    do {
        _ = try await connection.prepare { _ in
            SwifQL.select(Fn.cast(foreign, .integer) => "value")
        }
        Issue.record("Expected a foreign Statement.Parameter to be rejected.")
    } catch let error as DatabaseError {
        guard case .invalidStatementTemplate = error else {
            Issue.record("Expected invalidStatementTemplate, got \(error).")
            return
        }
    }
}

@Test("Foreign inline Statement.Parameter is rejected before Duck rendering hides it")
func foreignInlineStatementParameterIsRejected() async throws {
    let connection = try Database().connect()
    var foreignParameter: Statement.Parameter?

    do {
        _ = try await connection.prepare { parameters in
            foreignParameter = parameters.parameter()
            return SwifQL.select(Fn.cast(Int32(1), .integer) => "value")
        }
        Issue.record("Expected the source builder's unused parameter to be rejected.")
    } catch let error as DatabaseError {
        guard case .invalidStatementTemplate = error else {
            Issue.record("Expected invalidStatementTemplate, got \(error).")
            return
        }
    }

    let foreign = try #require(foreignParameter)
    do {
        _ = try await connection.prepare { _ in
            SwifQL.select(SwifQL.asterisk.like(foreign))
        }
        Issue.record("Expected a foreign inline Statement.Parameter to be rejected.")
    } catch let error as DatabaseError {
        guard case .invalidStatementTemplate = error else {
            Issue.record("Expected invalidStatementTemplate, got \(error).")
            return
        }
    }

    do {
        _ = try await connection.prepare(SwifQL.select(SwifQL.asterisk.like(foreign)))
        Issue.record("Expected direct prepare of an escaped inline Statement.Parameter to be rejected.")
    } catch let error as DatabaseError {
        guard case .invalidStatementTemplate = error else {
            Issue.record("Expected invalidStatementTemplate, got \(error).")
            return
        }
    }
}

@Test("Star-pattern inline Statement.Parameter is rejected")
func starPatternStatementParameterIsRejected() async throws {
    let connection = try Database().connect()

    do {
        _ = try await connection.prepare { parameters in
            let pattern = parameters.parameter()
            return SwifQL.select(SwifQL.asterisk.like(pattern))
        }
        Issue.record("Expected a star-pattern inline Parameter to be rejected.")
    } catch let error as DatabaseError {
        guard case .invalidStatementTemplate = error else {
            Issue.record("Expected invalidStatementTemplate, got \(error).")
            return
        }
    }
}

@Test("Sampling inline Statement.Parameter is rejected")
func samplingStatementParameterIsRejected() async throws {
    let connection = try Database().connect()

    do {
        _ = try await connection.prepare { parameters in
            let percentage = parameters.parameter()
            return SwifQL
                .select(Fn.cast(Int32(1), .integer) => "value")
                .usingSample(
                    Sample(
                        arguments: [SampleArgument(percentage: percentage)],
                        method: .system
                    )
                )
        }
        Issue.record("Expected a sampling inline Parameter to be rejected.")
    } catch let error as DatabaseError {
        guard case .invalidStatementTemplate = error else {
            Issue.record("Expected invalidStatementTemplate, got \(error).")
            return
        }
    }
}

@Test("Mixed bound and inline occurrences of one Statement.Parameter are rejected")
func mixedBoundAndInlineStatementParameterIsRejected() async throws {
    let connection = try Database().connect()

    do {
        _ = try await connection.prepare { parameters in
            let value = parameters.parameter()
            return SwifQL.select(
                Fn.cast(value, .integer) => "bound_value",
                SwifQL.asterisk.like(value)
            )
        }
        Issue.record("Expected a mixed bound/inline Parameter to be rejected.")
    } catch let error as DatabaseError {
        guard case .invalidStatementTemplate = error else {
            Issue.record("Expected invalidStatementTemplate, got \(error).")
            return
        }
    }
}

@Test("Unsupported fixed template value is rejected before installation")
func unsupportedFixedStatementValueIsRejected() async throws {
    let connection = try Database().connect()

    do {
        _ = try await connection.prepare(
            SwifQL.select(UnsupportedStatementBinding(value: "unsupported"))
        )
        Issue.record("Expected unsupported fixed Statement binding to be rejected.")
    } catch let error as DatabaseError {
        guard case .unsupportedBindingType = error else {
            Issue.record("Expected unsupportedBindingType, got \(error).")
            return
        }
    }
}

@Test("User transaction-control statement cannot be prepared for reuse")
func transactionControlStatementCannotBePreparedForReuse() async throws {
    let connection = try Database().connect()

    do {
        _ = try await connection.prepare(SwifQL.begin)
        Issue.record("Expected transaction-control prepare to be rejected.")
    } catch let error as DatabaseError {
        #expect(error == .transactionControlNotAllowed)
    }
}

@Test("Prepare inside live transaction scope rejects before builder side effects")
func statementPrepareRejectsTransactionScopeBeforeBuilderRuns() async throws {
    let connection = try Database().connect()
    var builderRan = false

    try await connection.transaction { _ in
        do {
            _ = try await connection.prepare { _ in
                builderRan = true
                return SwifQL.select(Fn.cast(Int32(1), .integer) => "value")
            }
            Issue.record("Expected prepare inside transaction body to be rejected.")
        } catch let error as DatabaseError {
            #expect(error == .transactionScopeViolation)
        }

        #expect(builderRan == false)
    }
}

@Test("Manual placeholder mismatch is rejected as an adapter invariant")
func reusableStatementParameterCountMismatchIsRejected() async throws {
    let connection = try Database().connect()

    do {
        _ = try await connection.prepare(SwifQL.raw("SELECT $1"))
        Issue.record("Expected native/template parameter-count mismatch to be rejected.")
    } catch let error as DatabaseError {
        guard case .invalidResult = error else {
            Issue.record("Expected invalidResult, got \(error).")
            return
        }
    }
}

@Test("Statement operation lifetime helper survives suspension")
func statementOperationLifetimeHelperSurvivesSuspension() async throws {
    let connection = try Database().connect()
    let statement = try await connection.prepare(
        SwifQL.select(Fn.cast(Int32(1), .integer) => "value")
    )
    let expectedId = statement.id

    let count = await statement.withOperationLifetime { connection, id in
        await Task.yield()
        #expect(id == expectedId)
        return await connection.preparedStatementDynamicArgumentCount(id)
    }

    #expect(count == 0)
}

@Test("Statement strongly retains its originating Connection and Database")
func statementRetainsOriginatingConnectionAndDatabase() async throws {
    var database: Database? = try Database()
    weak let weakDatabase = database
    var connection: Connection? = try database?.connect()
    weak let weakConnection = connection

    let strongConnection = try #require(connection)
    let statement = try await strongConnection.prepare(
        SwifQL.select(Fn.cast(Int32(1), .integer) => "value")
    )

    database = nil
    connection = nil

    #expect(weakDatabase != nil)
    #expect(weakConnection != nil)
    withExtendedLifetime(statement) {}
}
