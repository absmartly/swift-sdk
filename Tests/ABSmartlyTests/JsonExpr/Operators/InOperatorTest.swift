import Foundation
import XCTest

@testable import ABSmartly

final class InOperatorTest: OperatorTest {
	let inOperator = InOperator()

	func testString() {
		XCTAssertTrue(inOperator.evaluate(evaluator, ["abcdefghijk", "abc"]).boolValue)
		XCTAssertTrue(inOperator.evaluate(evaluator, ["abcdefghijk", "def"]).boolValue)
		XCTAssertFalse(inOperator.evaluate(evaluator, ["abcdefghijk", "xxx"]).boolValue)
		XCTAssertEqual(JSON.null, inOperator.evaluate(evaluator, ["abcdefghijk", JSON.null]))
		XCTAssertEqual(JSON.null, inOperator.evaluate(evaluator, [JSON.null, "abc"]))

		XCTAssertEqual(9, evaluator.evaluateCallsCount)
		XCTAssertEqual(
			["abcdefghijk", "abc", "abcdefghijk", "def", "abcdefghijk", "xxx", "abcdefghijk", JSON.null, JSON.null],
			evaluator.evaluateReceivedInvocations)
		XCTAssertEqual(3, evaluator.stringConvertCallsCount)
		XCTAssertEqual(["abc", "def", "xxx"], evaluator.stringConvertReceivedInvocations)

	}

	func testArrayEmpty() {
		XCTAssertFalse(inOperator.evaluate(evaluator, [[], 1]).boolValue)
		XCTAssertFalse(inOperator.evaluate(evaluator, [[], "1"]).boolValue)
		XCTAssertFalse(inOperator.evaluate(evaluator, [[], true]).boolValue)
		XCTAssertFalse(inOperator.evaluate(evaluator, [[], false]).boolValue)
		XCTAssertEqual(JSON.null, inOperator.evaluate(evaluator, [[], JSON.null]))

		XCTAssertFalse(evaluator.booleanConvertCalled)
		XCTAssertFalse(evaluator.numberConvertCalled)
		XCTAssertFalse(evaluator.stringConvertCalled)
		XCTAssertFalse(evaluator.compareCalled)
	}

	func testArrayCompares() {
		let haystack01 = JSON([0, 1])
		let haystack12 = JSON([1, 2])

		XCTAssertFalse(inOperator.evaluate(evaluator, [haystack01, 2]).boolValue)
		XCTAssertEqual(2, evaluator.evaluateCallsCount)
		XCTAssertEqual([haystack01, 2], evaluator.evaluateReceivedInvocations)
		XCTAssertEqual(2, evaluator.compareCallsCount)
		XCTAssertTrue((0, 2) == evaluator.compareReceivedInvocations[0])
		XCTAssertTrue((1, 2) == evaluator.compareReceivedInvocations[1])

		evaluator.clearInvocations()

		XCTAssertFalse(inOperator.evaluate(evaluator, [haystack12, 0]).boolValue)
		XCTAssertEqual(2, evaluator.evaluateCallsCount)
		XCTAssertEqual([haystack12, 0], evaluator.evaluateReceivedInvocations)
		XCTAssertEqual(2, evaluator.compareCallsCount)
		XCTAssertTrue((1, 0) == evaluator.compareReceivedInvocations[0])
		XCTAssertTrue((2, 0) == evaluator.compareReceivedInvocations[1])

		evaluator.clearInvocations()

		XCTAssertTrue(inOperator.evaluate(evaluator, [haystack12, 1]).boolValue)
		XCTAssertEqual(2, evaluator.evaluateCallsCount)
		XCTAssertEqual([haystack12, 1], evaluator.evaluateReceivedInvocations)
		XCTAssertEqual(1, evaluator.compareCallsCount)
		XCTAssertTrue((1, 1) == evaluator.compareReceivedArguments!)

		evaluator.clearInvocations()

		XCTAssertTrue(inOperator.evaluate(evaluator, [haystack12, 2]).boolValue)
		XCTAssertEqual(2, evaluator.evaluateCallsCount)
		XCTAssertEqual([haystack12, 2], evaluator.evaluateReceivedInvocations)
		XCTAssertEqual(2, evaluator.compareCallsCount)
		XCTAssertTrue((1, 2) == evaluator.compareReceivedInvocations[0])
		XCTAssertTrue((2, 2) == evaluator.compareReceivedInvocations[1])

		evaluator.clearInvocations()
	}

	func testObject() {
		let haystackab = JSON(["a": 1, "b": 2])
		let haystackbc = JSON(["b": 2, "c": 3, "0": 100])

		XCTAssertFalse(inOperator.evaluate(evaluator, [haystackab, "c"]).boolValue)
		XCTAssertEqual(2, evaluator.evaluateCallsCount)
		XCTAssertEqual([haystackab, "c"], evaluator.evaluateReceivedInvocations)
		XCTAssertEqual(1, evaluator.stringConvertCallsCount)
		XCTAssertTrue("c" == evaluator.stringConvertReceivedX)

		evaluator.clearInvocations()

		XCTAssertFalse(inOperator.evaluate(evaluator, [haystackbc, "a"]).boolValue)
		XCTAssertEqual(2, evaluator.evaluateCallsCount)
		XCTAssertEqual([haystackbc, "a"], evaluator.evaluateReceivedInvocations)
		XCTAssertEqual(1, evaluator.stringConvertCallsCount)
		XCTAssertTrue("a" == evaluator.stringConvertReceivedX)

		evaluator.clearInvocations()

		XCTAssertTrue(inOperator.evaluate(evaluator, [haystackbc, "b"]).boolValue)
		XCTAssertEqual(2, evaluator.evaluateCallsCount)
		XCTAssertEqual([haystackbc, "b"], evaluator.evaluateReceivedInvocations)
		XCTAssertEqual(1, evaluator.stringConvertCallsCount)
		XCTAssertTrue("b" == evaluator.stringConvertReceivedX)

		evaluator.clearInvocations()

		XCTAssertTrue(inOperator.evaluate(evaluator, [haystackbc, "c"]).boolValue)

		XCTAssertEqual(2, evaluator.evaluateCallsCount)
		XCTAssertEqual([haystackbc, "c"], evaluator.evaluateReceivedInvocations)
		XCTAssertEqual(1, evaluator.stringConvertCallsCount)
		XCTAssertTrue("c" == evaluator.stringConvertReceivedX)

		evaluator.clearInvocations()

		XCTAssertTrue(inOperator.evaluate(evaluator, [haystackbc, 0]).boolValue)
		XCTAssertEqual(2, evaluator.evaluateCallsCount)
		XCTAssertEqual([haystackbc, 0], evaluator.evaluateReceivedInvocations)
		XCTAssertEqual(1, evaluator.stringConvertCallsCount)
		XCTAssertTrue(0 == evaluator.stringConvertReceivedX)

		evaluator.clearInvocations()
	}
}
