import Foundation
import XCTest

@testable import ABSmartly

final class GreaterThanOperatorTest: OperatorTest {
	let greaterThanOperator = GreaterThanOperator()

	func testEvaluate() {
		XCTAssertFalse(greaterThanOperator.evaluate(evaluator, [0, 0]).boolValue)
		XCTAssertEqual(2, evaluator.evaluateCallsCount)
		XCTAssertEqual([0, 0], evaluator.evaluateReceivedInvocations)
		XCTAssertEqual(1, evaluator.compareCallsCount)
		XCTAssertEqual(0, evaluator.compareReceivedArguments!.lhs)
		XCTAssertEqual(0, evaluator.compareReceivedArguments!.rhs)

		evaluator.clearInvocations()

		XCTAssertTrue(greaterThanOperator.evaluate(evaluator, [1, 0]).boolValue)
		XCTAssertEqual(2, evaluator.evaluateCallsCount)
		XCTAssertEqual([1, 0], evaluator.evaluateReceivedInvocations)
		XCTAssertEqual(1, evaluator.compareCallsCount)
		XCTAssertEqual(1, evaluator.compareReceivedArguments!.lhs)
		XCTAssertEqual(0, evaluator.compareReceivedArguments!.rhs)

		evaluator.clearInvocations()

		XCTAssertFalse(greaterThanOperator.evaluate(evaluator, [0, 1]).boolValue)
		XCTAssertEqual(2, evaluator.evaluateCallsCount)
		XCTAssertEqual([0, 1], evaluator.evaluateReceivedInvocations)
		XCTAssertEqual(1, evaluator.compareCallsCount)
		XCTAssertEqual(0, evaluator.compareReceivedArguments!.lhs)
		XCTAssertEqual(1, evaluator.compareReceivedArguments!.rhs)

		evaluator.clearInvocations()

		XCTAssertEqual(JSON.null, greaterThanOperator.evaluate(evaluator, [JSON.null, JSON.null]))
		XCTAssertEqual(1, evaluator.evaluateCallsCount)
		XCTAssertEqual(JSON.null, evaluator.evaluateReceivedExpr)
		XCTAssertFalse(evaluator.compareCalled)
	}
}
