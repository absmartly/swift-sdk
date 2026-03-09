import Foundation
import XCTest

@testable import ABSmartly

final class InOperatorTest: OperatorTest {
	let inOperator = InOperator()

	func testString() {
		XCTAssertTrue(inOperator.evaluate(evaluator, ["abc", "abcdefghijk"]).boolValue)
		XCTAssertTrue(inOperator.evaluate(evaluator, ["def", "abcdefghijk"]).boolValue)
		XCTAssertFalse(inOperator.evaluate(evaluator, ["xxx", "abcdefghijk"]).boolValue)
		XCTAssertFalse(inOperator.evaluate(evaluator, [JSON.null, "abcdefghijk"]).boolValue)
		XCTAssertEqual(JSON.null, inOperator.evaluate(evaluator, ["abc", JSON.null]))

		XCTAssertEqual(10, evaluator.evaluateCallsCount)
		XCTAssertEqual(
			["abc", "abcdefghijk", "def", "abcdefghijk", "xxx", "abcdefghijk", JSON.null, "abcdefghijk", "abc", JSON.null],
			evaluator.evaluateReceivedInvocations)
		XCTAssertEqual(4, evaluator.stringConvertCallsCount)
		XCTAssertEqual(["abc", "def", "xxx", JSON.null], evaluator.stringConvertReceivedInvocations)

	}

	func testArrayEmpty() {
		XCTAssertFalse(inOperator.evaluate(evaluator, [1, []]).boolValue)
		XCTAssertFalse(inOperator.evaluate(evaluator, ["1", []]).boolValue)
		XCTAssertFalse(inOperator.evaluate(evaluator, [true, []]).boolValue)
		XCTAssertFalse(inOperator.evaluate(evaluator, [false, []]).boolValue)
		XCTAssertFalse(inOperator.evaluate(evaluator, [JSON.null, []]).boolValue)

		XCTAssertFalse(evaluator.booleanConvertCalled)
		XCTAssertFalse(evaluator.numberConvertCalled)
		XCTAssertFalse(evaluator.stringConvertCalled)
		XCTAssertFalse(evaluator.compareCalled)
	}

	func testArrayCompares() {
		let haystack01 = JSON([0, 1])
		let haystack12 = JSON([1, 2])

		XCTAssertFalse(inOperator.evaluate(evaluator, [2, haystack01]).boolValue)
		XCTAssertEqual(2, evaluator.evaluateCallsCount)
		XCTAssertEqual([2, haystack01], evaluator.evaluateReceivedInvocations)
		XCTAssertEqual(2, evaluator.compareCallsCount)
		XCTAssertTrue((0, 2) == evaluator.compareReceivedInvocations[0])
		XCTAssertTrue((1, 2) == evaluator.compareReceivedInvocations[1])

		evaluator.clearInvocations()

		XCTAssertFalse(inOperator.evaluate(evaluator, [0, haystack12]).boolValue)
		XCTAssertEqual(2, evaluator.evaluateCallsCount)
		XCTAssertEqual([0, haystack12], evaluator.evaluateReceivedInvocations)
		XCTAssertEqual(2, evaluator.compareCallsCount)
		XCTAssertTrue((1, 0) == evaluator.compareReceivedInvocations[0])
		XCTAssertTrue((2, 0) == evaluator.compareReceivedInvocations[1])

		evaluator.clearInvocations()

		XCTAssertTrue(inOperator.evaluate(evaluator, [1, haystack12]).boolValue)
		XCTAssertEqual(2, evaluator.evaluateCallsCount)
		XCTAssertEqual([1, haystack12], evaluator.evaluateReceivedInvocations)
		XCTAssertEqual(1, evaluator.compareCallsCount)
		XCTAssertTrue((1, 1) == evaluator.compareReceivedArguments!)

		evaluator.clearInvocations()

		XCTAssertTrue(inOperator.evaluate(evaluator, [2, haystack12]).boolValue)
		XCTAssertEqual(2, evaluator.evaluateCallsCount)
		XCTAssertEqual([2, haystack12], evaluator.evaluateReceivedInvocations)
		XCTAssertEqual(2, evaluator.compareCallsCount)
		XCTAssertTrue((1, 2) == evaluator.compareReceivedInvocations[0])
		XCTAssertTrue((2, 2) == evaluator.compareReceivedInvocations[1])

		evaluator.clearInvocations()
	}

	func testObject() {
		let haystackab = JSON(["a": 1, "b": 2])
		let haystackbc = JSON(["b": 2, "c": 3, "0": 100])

		XCTAssertFalse(inOperator.evaluate(evaluator, ["c", haystackab]).boolValue)
		XCTAssertEqual(2, evaluator.evaluateCallsCount)
		XCTAssertEqual(["c", haystackab], evaluator.evaluateReceivedInvocations)
		XCTAssertEqual(1, evaluator.stringConvertCallsCount)
		XCTAssertTrue("c" == evaluator.stringConvertReceivedX)

		evaluator.clearInvocations()

		XCTAssertFalse(inOperator.evaluate(evaluator, ["a", haystackbc]).boolValue)
		XCTAssertEqual(2, evaluator.evaluateCallsCount)
		XCTAssertEqual(["a", haystackbc], evaluator.evaluateReceivedInvocations)
		XCTAssertEqual(1, evaluator.stringConvertCallsCount)
		XCTAssertTrue("a" == evaluator.stringConvertReceivedX)

		evaluator.clearInvocations()

		XCTAssertTrue(inOperator.evaluate(evaluator, ["b", haystackbc]).boolValue)
		XCTAssertEqual(2, evaluator.evaluateCallsCount)
		XCTAssertEqual(["b", haystackbc], evaluator.evaluateReceivedInvocations)
		XCTAssertEqual(1, evaluator.stringConvertCallsCount)
		XCTAssertTrue("b" == evaluator.stringConvertReceivedX)

		evaluator.clearInvocations()

		XCTAssertTrue(inOperator.evaluate(evaluator, ["c", haystackbc]).boolValue)

		XCTAssertEqual(2, evaluator.evaluateCallsCount)
		XCTAssertEqual(["c", haystackbc], evaluator.evaluateReceivedInvocations)
		XCTAssertEqual(1, evaluator.stringConvertCallsCount)
		XCTAssertTrue("c" == evaluator.stringConvertReceivedX)

		evaluator.clearInvocations()

		XCTAssertTrue(inOperator.evaluate(evaluator, [0, haystackbc]).boolValue)
		XCTAssertEqual(2, evaluator.evaluateCallsCount)
		XCTAssertEqual([0, haystackbc], evaluator.evaluateReceivedInvocations)
		XCTAssertEqual(1, evaluator.stringConvertCallsCount)
		XCTAssertTrue(0 == evaluator.stringConvertReceivedX)

		evaluator.clearInvocations()
	}
}
