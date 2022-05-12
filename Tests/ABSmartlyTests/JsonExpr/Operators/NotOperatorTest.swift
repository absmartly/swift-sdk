import Foundation
import XCTest

@testable import ABSmartly

final class NotOperatorTest: OperatorTest {
	let notOperator = NotOperator()

	func testFalse() {
		XCTAssertTrue(notOperator.evaluate(evaluator, false).boolValue)
		XCTAssertEqual(1, evaluator.booleanConvertCallsCount)
		XCTAssertEqual(false, evaluator.booleanConvertReceivedX)
		XCTAssertEqual(1, evaluator.evaluateCallsCount)
		XCTAssertEqual(false, evaluator.evaluateReceivedExpr)
	}

	func testTrue() {
		XCTAssertFalse(notOperator.evaluate(evaluator, true).boolValue)
		XCTAssertEqual(1, evaluator.booleanConvertCallsCount)
		XCTAssertEqual(true, evaluator.booleanConvertReceivedX)
		XCTAssertEqual(1, evaluator.evaluateCallsCount)
		XCTAssertEqual(true, evaluator.evaluateReceivedExpr)
	}

	func testNull() {
		XCTAssertTrue(notOperator.evaluate(evaluator, JSON.null).boolValue)
		XCTAssertEqual(1, evaluator.booleanConvertCallsCount)
		XCTAssertEqual(JSON.null, evaluator.booleanConvertReceivedX)
		XCTAssertEqual(1, evaluator.evaluateCallsCount)
		XCTAssertEqual(JSON.null, evaluator.evaluateReceivedExpr)
	}
}
