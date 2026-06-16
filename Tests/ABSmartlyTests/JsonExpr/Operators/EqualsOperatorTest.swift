import Foundation
import XCTest

@testable import ABSmartly

final class EqualsOperatorTest: OperatorTest {
	let equalsOperator = EqualsOperator()

	func testEvaluate() {
		XCTAssertTrue(equalsOperator.evaluate(evaluator, [0, 0]).boolValue)
		XCTAssertEqual(2, evaluator.evaluateCallsCount)
		XCTAssertEqual([0, 0], evaluator.evaluateReceivedInvocations)
		XCTAssertEqual(1, evaluator.compareCallsCount)
		XCTAssertEqual(0, evaluator.compareReceivedArguments!.lhs)
		XCTAssertEqual(0, evaluator.compareReceivedArguments!.rhs)

		evaluator.clearInvocations()

		XCTAssertFalse(equalsOperator.evaluate(evaluator, [1, 0]).boolValue)
		XCTAssertEqual(2, evaluator.evaluateCallsCount)
		XCTAssertEqual([1, 0], evaluator.evaluateReceivedInvocations)
		XCTAssertEqual(1, evaluator.compareCallsCount)
		XCTAssertEqual(1, evaluator.compareReceivedArguments!.lhs)
		XCTAssertEqual(0, evaluator.compareReceivedArguments!.rhs)

		evaluator.clearInvocations()

		XCTAssertFalse(equalsOperator.evaluate(evaluator, [0, 1]).boolValue)
		XCTAssertEqual(2, evaluator.evaluateCallsCount)
		XCTAssertEqual([0, 1], evaluator.evaluateReceivedInvocations)
		XCTAssertEqual(1, evaluator.compareCallsCount)
		XCTAssertEqual(0, evaluator.compareReceivedArguments!.lhs)
		XCTAssertEqual(1, evaluator.compareReceivedArguments!.rhs)

		evaluator.clearInvocations()

		XCTAssertEqual(JSON.null, equalsOperator.evaluate(evaluator, [JSON.null, JSON.null]))
		XCTAssertEqual(1, evaluator.evaluateCallsCount)
		XCTAssertEqual(JSON.null, evaluator.evaluateReceivedExpr)
		XCTAssertFalse(evaluator.compareCalled)

		evaluator.clearInvocations()

		XCTAssertTrue(equalsOperator.evaluate(evaluator, [[1, 2], [1, 2]]).boolValue)
		XCTAssertEqual(2, evaluator.evaluateCallsCount)
		XCTAssertEqual(1, evaluator.compareCallsCount)

		evaluator.clearInvocations()

		XCTAssertEqual(JSON.null, equalsOperator.evaluate(evaluator, [[1, 2], [2, 3]]))
		XCTAssertEqual(2, evaluator.evaluateCallsCount)
		XCTAssertEqual(1, evaluator.compareCallsCount)

		evaluator.clearInvocations()

		XCTAssertTrue(equalsOperator.evaluate(evaluator, [["a": 1, "b": 2], ["a": 1, "b": 2]]).boolValue)
		XCTAssertEqual(2, evaluator.evaluateCallsCount)
		XCTAssertEqual(1, evaluator.compareCallsCount)

		evaluator.clearInvocations()

		XCTAssertEqual(JSON.null, equalsOperator.evaluate(evaluator, [["a": 1, "b": 2], ["a": 3, "b": 4]]))
		XCTAssertEqual(2, evaluator.evaluateCallsCount)
		XCTAssertEqual(1, evaluator.compareCallsCount)
	}
}
