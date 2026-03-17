import Foundation
import XCTest

@testable import ABSmartly

final class BinaryOperatorNullSafetyTest: OperatorTest {
	let equalsOp = EqualsOperator()
	let greaterOp = GreaterThanOperator()
	let lessOp = LessThanOperator()
	let greaterEqOp = GreaterThanOrEqualOperator()
	let lessEqOp = LessThanOrEqualOperator()
	let matchOp = MatchOperator()
	let inOp = InOperator()

	func testEqualsNullNull() {
		let result = equalsOp.evaluate(evaluator, [JSON.null, JSON.null])
		XCTAssertTrue(result.boolValue)
	}

	func testEqualsNullVsNumber() {
		evaluator.clearInvocations()
		let result = equalsOp.evaluate(evaluator, [JSON.null, 1])
		XCTAssertFalse(result.boolValue)
	}

	func testEqualsNumberVsNull() {
		evaluator.clearInvocations()
		let result = equalsOp.evaluate(evaluator, [1, JSON.null])
		XCTAssertFalse(result.boolValue)
	}

	func testGreaterThanNullNull() {
		let result = greaterOp.evaluate(evaluator, [JSON.null, JSON.null])
		XCTAssertFalse(result.boolValue)
	}

	func testLessThanNullNull() {
		let result = lessOp.evaluate(evaluator, [JSON.null, JSON.null])
		XCTAssertFalse(result.boolValue)
	}

	func testGreaterThanOrEqualNullNull() {
		let result = greaterEqOp.evaluate(evaluator, [JSON.null, JSON.null])
		XCTAssertTrue(result.boolValue)
	}

	func testLessThanOrEqualNullNull() {
		let result = lessEqOp.evaluate(evaluator, [JSON.null, JSON.null])
		XCTAssertTrue(result.boolValue)
	}

	func testMatchWithNullLhsDoesNotCrash() {
		let result = matchOp.evaluate(evaluator, [JSON.null, "abc"])
		XCTAssertNotNil(result)
	}

	func testMatchWithNullRhsDoesNotCrash() {
		let result = matchOp.evaluate(evaluator, ["abc", JSON.null])
		XCTAssertNotNil(result)
	}

	func testInWithNullHaystack() {
		let result = inOp.evaluate(evaluator, ["abc", JSON.null])
		XCTAssertEqual(JSON.null, result)
	}

	func testBinaryOperatorNotEnoughArgs() {
		let result = equalsOp.evaluate(evaluator, [1])
		XCTAssertEqual(JSON.null, result)

		evaluator.clearInvocations()
		let result2 = equalsOp.evaluate(evaluator, JSON.null)
		XCTAssertEqual(JSON.null, result2)
	}
}
