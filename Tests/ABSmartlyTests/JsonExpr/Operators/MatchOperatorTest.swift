import Foundation
import XCTest

@testable import ABSmartly

final class MatchOperatorTest: OperatorTest {
	let matchOperator = MatchOperator()

	func testEvaluate() {
		XCTAssertTrue(matchOperator.evaluate(evaluator, ["abcdefghijk", ""]).boolValue)
		XCTAssertTrue(matchOperator.evaluate(evaluator, ["abcdefghijk", "abc"]).boolValue)
		XCTAssertTrue(matchOperator.evaluate(evaluator, ["abcdefghijk", "ijk"]).boolValue)
		XCTAssertTrue(matchOperator.evaluate(evaluator, ["abcdefghijk", "^abc"]).boolValue)
		XCTAssertTrue(matchOperator.evaluate(evaluator, [",l5abcdefghijk", "ijk$"]).boolValue)
		XCTAssertTrue(matchOperator.evaluate(evaluator, ["abcdefghijk", "def"]).boolValue)
		XCTAssertTrue(matchOperator.evaluate(evaluator, ["abcdefghijk", "b.*j"]).boolValue)
		XCTAssertFalse(matchOperator.evaluate(evaluator, ["abcdefghijk", "xyz"]).boolValue)

		XCTAssertFalse(matchOperator.evaluate(evaluator, [JSON.null, "abc"]).boolValue)
		XCTAssertTrue(matchOperator.evaluate(evaluator, ["abcdefghijk", JSON.null]).boolValue)
	}

	func testRejectsLongPattern() {
		let longPattern = String(repeating: "a", count: 1001)
		let result = matchOperator.evaluate(evaluator, ["test", longPattern])
		XCTAssertEqual(JSON.null, result)
	}

	func testRejectsLongInput() {
		let longInput = String(repeating: "a", count: 10001)
		let result = matchOperator.evaluate(evaluator, [longInput, "a"])
		XCTAssertEqual(JSON.null, result)
	}

	func testRejectsNestedQuantifiers() {
		let result = matchOperator.evaluate(evaluator, ["test", "(a+)+b"])
		XCTAssertEqual(JSON.null, result)
	}

	func testAcceptsNormalPatternWithinLimits() {
		let pattern = String(repeating: "a", count: 999)
		let input = String(repeating: "a", count: 9999)
		let result = matchOperator.evaluate(evaluator, [input, pattern])
		XCTAssertTrue(result.boolValue)
	}

	func testNoSemaphoreThreadLeak() {
		let result = matchOperator.evaluate(evaluator, ["hello world", "hello"])
		XCTAssertTrue(result.boolValue)

		let result2 = matchOperator.evaluate(evaluator, ["hello world", "^world"])
		XCTAssertFalse(result2.boolValue)
	}

	func testInvalidRegexReturnsNull() {
		let result = matchOperator.evaluate(evaluator, ["test", "[invalid"])
		XCTAssertEqual(JSON.null, result)
	}
}
