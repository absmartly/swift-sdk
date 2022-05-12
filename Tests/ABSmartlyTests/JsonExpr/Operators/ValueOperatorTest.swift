import Foundation
import XCTest

@testable import ABSmartly

final class ValueOperatorTest: OperatorTest {
	let valueOperator = ValueOperator()

	func testEvaluate() {
		XCTAssertEqual(0, valueOperator.evaluate(evaluator, 0))
		XCTAssertEqual(1, valueOperator.evaluate(evaluator, 1))
		XCTAssertEqual(true, valueOperator.evaluate(evaluator, true))
		XCTAssertEqual(false, valueOperator.evaluate(evaluator, false))
		XCTAssertEqual("", valueOperator.evaluate(evaluator, ""))
		XCTAssertEqual([:], valueOperator.evaluate(evaluator, [:]))
		XCTAssertEqual([], valueOperator.evaluate(evaluator, []))
		XCTAssertEqual(JSON.null, valueOperator.evaluate(evaluator, JSON.null))

		XCTAssertFalse(evaluator.evaluateCalled)
	}
}
