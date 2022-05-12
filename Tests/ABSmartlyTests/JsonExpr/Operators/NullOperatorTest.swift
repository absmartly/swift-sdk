import Foundation
import XCTest

@testable import ABSmartly

final class NullOperatorTest: OperatorTest {
	let nullOperator = NullOperator()

	func testNull() {
		XCTAssertTrue(nullOperator.evaluate(evaluator, JSON.null).boolValue)
		XCTAssertEqual(1, evaluator.evaluateCallsCount)
		XCTAssertEqual(JSON.null, evaluator.evaluateReceivedExpr)
	}

	func testNotNull() {
		XCTAssertFalse(nullOperator.evaluate(evaluator, true).boolValue)
		XCTAssertEqual(1, evaluator.evaluateCallsCount)
		XCTAssertEqual(true, evaluator.evaluateReceivedExpr)

		evaluator.clearInvocations()

		XCTAssertFalse(nullOperator.evaluate(evaluator, false).boolValue)
		XCTAssertEqual(1, evaluator.evaluateCallsCount)
		XCTAssertEqual(false, evaluator.evaluateReceivedExpr)

		evaluator.clearInvocations()

		XCTAssertFalse(nullOperator.evaluate(evaluator, 0).boolValue)
		XCTAssertEqual(1, evaluator.evaluateCallsCount)
		XCTAssertEqual(0, evaluator.evaluateReceivedExpr)
	}
}
