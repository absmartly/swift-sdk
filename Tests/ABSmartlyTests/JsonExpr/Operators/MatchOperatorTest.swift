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

		XCTAssertEqual(JSON.null, matchOperator.evaluate(evaluator, [JSON.null, "abc"]))
		XCTAssertEqual(JSON.null, matchOperator.evaluate(evaluator, ["abcdefghijk", JSON.null]))
	}
}
