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
		XCTAssertEqual(JSON.null, matchOperator.evaluate(evaluator, ["abcdefghijk", JSON.null]))
	}

	// v1.4.0 had no pattern or input length limits and no nested-quantifier rejection; long patterns,
	// long inputs and nested quantifiers that do not blow up still match normally. Only a match that
	// runs past the timeout gives up (testOverlappingAlternationTimesOut).
	func testLongPatternAndInputMatchAsBefore() {
		XCTAssertEqual(JSON(false), matchOperator.evaluate(evaluator, ["test", String(repeating: "a", count: 1001)]))
		XCTAssertEqual(JSON(true), matchOperator.evaluate(evaluator, [String(repeating: "a", count: 10001), "a"]))
	}

	func testNestedQuantifiersMatchAsBefore() {
		XCTAssertEqual(JSON(false), matchOperator.evaluate(evaluator, ["test", "(a+)+b"]))
		XCTAssertEqual(JSON(true), matchOperator.evaluate(evaluator, ["aaab", "(a+)+b"]))
		XCTAssertEqual(JSON(true), matchOperator.evaluate(evaluator, ["test", "(?:x|a+)*"]))
	}

	func testSequentialQuantifiers() {
		XCTAssertEqual(JSON(true), matchOperator.evaluate(evaluator, ["ABC-123", "^([A-Z]+)-[0-9]+$"]))
		XCTAssertEqual(JSON(true), matchOperator.evaluate(evaluator, ["ab12", "(a|b)+[0-9]{2}"]))
		XCTAssertEqual(JSON(true), matchOperator.evaluate(evaluator, ["192.168.1.1", "^([0-9]{1,3}\\.){3}[0-9]{1,3}$"]))
	}

	func testOverlappingAlternationTimesOut() {
		// No nested quantifier, but exponential backtracking on a near-miss input.
		// Evaluated off the test thread with an outer deadline, so a regression fails instead of hanging.
		let input = String(repeating: "a", count: 60) + "b"
		let matchOperator = self.matchOperator
		let evaluator = self.evaluator
		let finished = XCTestExpectation(description: "evaluate returns")
		var result: JSON?
		var elapsed: TimeInterval = 0
		DispatchQueue.global().async {
			let start = Date()
			let value = matchOperator.evaluate(evaluator, [input, "^(a|aa)+$"])
			elapsed = Date().timeIntervalSince(start)
			result = value
			finished.fulfill()
		}
		XCTAssertEqual(.completed, XCTWaiter().wait(for: [finished], timeout: 5.0))
		XCTAssertEqual(JSON.null, result)
		XCTAssertLessThan(elapsed, 2.0)

		XCTAssertEqual(JSON(true), matchOperator.evaluate(evaluator, ["aaaa", "^(a|aa)+$"]))
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
