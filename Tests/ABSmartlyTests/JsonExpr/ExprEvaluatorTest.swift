import Foundation
import XCTest

@testable import ABSmartly

final class ExprEvaluatorTest: XCTestCase {
	func testEvaluateConsidersListAsAndCombinator() {
		let andOperator = OperatorMock()
		let orOperator = OperatorMock()
		andOperator.evaluateReturnValue = JSON(true)

		let evaluator = ExprEvaluator(operators: ["and": andOperator, "or": orOperator], vars: [:])
		let args = JSON([["value": true], ["value": false]])

		XCTAssertNotEqual(JSON.null, evaluator.evaluate(args))

		XCTAssertFalse(orOperator.evaluateCalled)
		XCTAssertEqual(1, andOperator.evaluateCallsCount)
		XCTAssertIdentical(evaluator, andOperator.evaluateReceivedArguments!.evaluator)
		XCTAssertEqual(args, andOperator.evaluateReceivedArguments!.args)
	}

	func testEvaluateReturnsNullIfOperatorNotFound() {
		let valueOperator = OperatorMock()
		valueOperator.evaluateReturnValue = JSON(true)

		let evaluator = ExprEvaluator(operators: ["value": valueOperator], vars: [:])
		XCTAssertEqual(JSON.null, evaluator.evaluate(["not_found": true]))

		XCTAssertFalse(valueOperator.evaluateCalled)
	}

	func testEvaluateCallsOperatorWithArgs() {
		let valueOperator = OperatorMock()

		let args = JSON([1, 2, 3])

		valueOperator.evaluateReturnValue = args

		let evaluator = ExprEvaluator(operators: ["value": valueOperator], vars: [:])
		XCTAssertEqual(args, evaluator.evaluate(JSON(["value": args])))
		XCTAssertEqual(1, valueOperator.evaluateCallsCount)
		XCTAssertIdentical(evaluator, valueOperator.evaluateReceivedArguments!.evaluator)
		XCTAssertEqual(args, valueOperator.evaluateReceivedArguments!.args)
	}

	func testBooleanConvert() {
		let evaluator = ExprEvaluator(operators: [:], vars: [:])

		XCTAssertEqual(true, evaluator.booleanConvert([:]))
		XCTAssertEqual(true, evaluator.booleanConvert([]))
		XCTAssertEqual(false, evaluator.booleanConvert(JSON.null))

		XCTAssertEqual(true, evaluator.booleanConvert(true))
		XCTAssertEqual(true, evaluator.booleanConvert(1))
		XCTAssertEqual(true, evaluator.booleanConvert(2))
		XCTAssertEqual(true, evaluator.booleanConvert("abc"))
		XCTAssertEqual(true, evaluator.booleanConvert("1"))

		XCTAssertEqual(false, evaluator.booleanConvert(false))
		XCTAssertEqual(false, evaluator.booleanConvert(0))
		XCTAssertEqual(false, evaluator.booleanConvert(""))
		XCTAssertEqual(false, evaluator.booleanConvert("0"))
		XCTAssertEqual(false, evaluator.booleanConvert("false"))
	}

	func testNumberConvert() {
		let evaluator = ExprEvaluator(operators: [:], vars: [:])

		XCTAssertEqual(JSON.null, evaluator.numberConvert([:]))
		XCTAssertEqual(JSON.null, evaluator.numberConvert([]))
		XCTAssertEqual(JSON.null, evaluator.numberConvert(JSON.null))
		XCTAssertEqual(JSON.null, evaluator.numberConvert(""))
		XCTAssertEqual(JSON.null, evaluator.numberConvert("abcd"))
		XCTAssertEqual(JSON.null, evaluator.numberConvert("x1234"))

		XCTAssertEqual(1.0, evaluator.numberConvert(true))
		XCTAssertEqual(0.0, evaluator.numberConvert(false))

		XCTAssertEqual(-1.0, evaluator.numberConvert(-1.0))
		XCTAssertEqual(0.0, evaluator.numberConvert(0.0))
		XCTAssertEqual(1.0, evaluator.numberConvert(1.0))
		XCTAssertEqual(1.5, evaluator.numberConvert(1.5))
		XCTAssertEqual(2.0, evaluator.numberConvert(2.0))
		XCTAssertEqual(3.0, evaluator.numberConvert(3.0))

		XCTAssertEqual(-1.0, evaluator.numberConvert(-1))
		XCTAssertEqual(0.0, evaluator.numberConvert(0))
		XCTAssertEqual(1.0, evaluator.numberConvert(1))
		XCTAssertEqual(2.0, evaluator.numberConvert(2))
		XCTAssertEqual(3.0, evaluator.numberConvert(3))
		XCTAssertEqual(2147483647.0, evaluator.numberConvert(2_147_483_647))
		XCTAssertEqual(-2147483647.0, evaluator.numberConvert(-2_147_483_647))
		XCTAssertEqual(9007199254740991.0, evaluator.numberConvert(9_007_199_254_740_991))
		XCTAssertEqual(-9007199254740991.0, evaluator.numberConvert(-9_007_199_254_740_991))

		XCTAssertEqual(-1.0, evaluator.numberConvert("-1"))
		XCTAssertEqual(0.0, evaluator.numberConvert("0"))
		XCTAssertEqual(1.0, evaluator.numberConvert("1"))
		XCTAssertEqual(1.5, evaluator.numberConvert("1.5"))
		XCTAssertEqual(2.0, evaluator.numberConvert("2"))
		XCTAssertEqual(3.0, evaluator.numberConvert("3.0"))
	}

	func testStringConvert() {
		let evaluator = ExprEvaluator(operators: [:], vars: [:])

		XCTAssertEqual(JSON.null, evaluator.stringConvert(JSON.null))
		XCTAssertEqual(JSON.null, evaluator.stringConvert([:]))
		XCTAssertEqual(JSON.null, evaluator.stringConvert([]))

		XCTAssertEqual("true", evaluator.stringConvert(true))
		XCTAssertEqual("false", evaluator.stringConvert(false))

		XCTAssertEqual("", evaluator.stringConvert(""))
		XCTAssertEqual("abc", evaluator.stringConvert("abc"))

		XCTAssertEqual("-1", evaluator.stringConvert(-1.0))
		XCTAssertEqual("0", evaluator.stringConvert(0.0))
		XCTAssertEqual("1", evaluator.stringConvert(1.0))
		XCTAssertEqual("1.5", evaluator.stringConvert(1.5))
		XCTAssertEqual("2", evaluator.stringConvert(2.0))
		XCTAssertEqual("3", evaluator.stringConvert(3.0))
		XCTAssertEqual("2147483647", evaluator.stringConvert(2147483647.0))
		XCTAssertEqual("-2147483647", evaluator.stringConvert(-2147483647.0))
		XCTAssertEqual("9007199254740991", evaluator.stringConvert(9007199254740991.0))
		XCTAssertEqual("-9007199254740991", evaluator.stringConvert(-9007199254740991.0))
		XCTAssertEqual("0.900719925474099", evaluator.stringConvert(0.9007199254740991))
		XCTAssertEqual("-0.900719925474099", evaluator.stringConvert(-0.9007199254740991))

		XCTAssertEqual("-1", evaluator.stringConvert(-1))
		XCTAssertEqual("0", evaluator.stringConvert(0))
		XCTAssertEqual("1", evaluator.stringConvert(1))
		XCTAssertEqual("2", evaluator.stringConvert(2))
		XCTAssertEqual("3", evaluator.stringConvert(3))
		XCTAssertEqual("2147483647", evaluator.stringConvert(2_147_483_647))
		XCTAssertEqual("-2147483647", evaluator.stringConvert(-2_147_483_647))
		XCTAssertEqual("9007199254740991", evaluator.stringConvert(9_007_199_254_740_991))
		XCTAssertEqual("-9007199254740991", evaluator.stringConvert(-9_007_199_254_740_991))
	}

	func testExtractVar() {
		let vars: [String: JSON] = [
			"a": 1,
			"b": true,
			"c": false,
			"d": [1, 2, 3],
			"e": [1, ["z": 2], 3],
			"f": ["y": ["x": 3, "0": 10]],
		]

		let evaluator = ExprEvaluator(operators: [:], vars: vars)

		XCTAssertEqual(1, evaluator.extractVar("a"))
		XCTAssertEqual(true, evaluator.extractVar("b"))
		XCTAssertEqual(false, evaluator.extractVar("c"))
		XCTAssertEqual([1, 2, 3], evaluator.extractVar("d"))
		XCTAssertEqual([1, ["z": 2], 3], evaluator.extractVar("e"))
		XCTAssertEqual(["y": ["x": 3, "0": 10]], evaluator.extractVar("f"))

		XCTAssertEqual(JSON.null, evaluator.extractVar("a/0"))
		XCTAssertEqual(JSON.null, evaluator.extractVar("a/b"))
		XCTAssertEqual(JSON.null, evaluator.extractVar("b/0"))
		XCTAssertEqual(JSON.null, evaluator.extractVar("b/e"))

		XCTAssertEqual(1, evaluator.extractVar("d/0"))
		XCTAssertEqual(2, evaluator.extractVar("d/1"))
		XCTAssertEqual(3, evaluator.extractVar("d/2"))
		XCTAssertEqual(JSON.null, evaluator.extractVar("d/3"))

		XCTAssertEqual(1, evaluator.extractVar("e/0"))
		XCTAssertEqual(2, evaluator.extractVar("e/1/z"))
		XCTAssertEqual(3, evaluator.extractVar("e/2"))
		XCTAssertEqual(JSON.null, evaluator.extractVar("e/1/0"))

		XCTAssertEqual(["x": 3, "0": 10], evaluator.extractVar("f/y"))
		XCTAssertEqual(3, evaluator.extractVar("f/y/x"))
		XCTAssertEqual(10, evaluator.extractVar("f/y/0"))
	}

	func testCompareNull() {
		let evaluator = ExprEvaluator(operators: [:], vars: [:])

		XCTAssertEqual(0, evaluator.compare(JSON.null, JSON.null))

		XCTAssertNil(evaluator.compare(JSON.null, 0))
		XCTAssertNil(evaluator.compare(JSON.null, 1))
		XCTAssertNil(evaluator.compare(JSON.null, true))
		XCTAssertNil(evaluator.compare(JSON.null, false))
		XCTAssertNil(evaluator.compare(JSON.null, ""))
		XCTAssertNil(evaluator.compare(JSON.null, "abc"))
		XCTAssertNil(evaluator.compare(JSON.null, [:]))
		XCTAssertNil(evaluator.compare(JSON.null, []))
	}

	func testCompareObjects() {
		let evaluator = ExprEvaluator(operators: [:], vars: [:])

		XCTAssertEqual(nil, evaluator.compare([:], 0))
		XCTAssertNil(evaluator.compare([:], 1))
		XCTAssertNil(evaluator.compare([:], true))
		XCTAssertNil(evaluator.compare([:], false))
		XCTAssertNil(evaluator.compare([:], ""))
		XCTAssertNil(evaluator.compare([:], "abc"))
		XCTAssertEqual(0, evaluator.compare([:], [:]))
		XCTAssertEqual(0, evaluator.compare(["a": 1], ["a": 1]))
		XCTAssertNil(evaluator.compare(["a": 1], ["b": 2]))
		XCTAssertNil(evaluator.compare([:], []))

		XCTAssertNil(evaluator.compare([], 0))
		XCTAssertNil(evaluator.compare([], 1))
		XCTAssertNil(evaluator.compare([], true))
		XCTAssertNil(evaluator.compare([], false))
		XCTAssertNil(evaluator.compare([], ""))
		XCTAssertNil(evaluator.compare([], "abc"))
		XCTAssertNil(evaluator.compare([], [:]))
		XCTAssertEqual(0, evaluator.compare([], []))
		XCTAssertEqual(0, evaluator.compare([1, 2], [1, 2]))
		XCTAssertNil(evaluator.compare([1, 2], [3, 4]))
	}

	func testCompareBooleans() {
		let evaluator = ExprEvaluator(operators: [:], vars: [:])

		XCTAssertEqual(0, evaluator.compare(false, 0))
		XCTAssertEqual(-1, evaluator.compare(false, 1))
		XCTAssertEqual(-1, evaluator.compare(false, true))
		XCTAssertEqual(0, evaluator.compare(false, false))
		XCTAssertEqual(0, evaluator.compare(false, ""))
		XCTAssertEqual(-1, evaluator.compare(false, "abc"))
		XCTAssertEqual(-1, evaluator.compare(false, [:]))
		XCTAssertEqual(-1, evaluator.compare(false, []))

		XCTAssertEqual(1, evaluator.compare(true, 0))
		XCTAssertEqual(0, evaluator.compare(true, 1))
		XCTAssertEqual(0, evaluator.compare(true, true))
		XCTAssertEqual(1, evaluator.compare(true, false))
		XCTAssertEqual(1, evaluator.compare(true, ""))
		XCTAssertEqual(0, evaluator.compare(true, "abc"))
		XCTAssertEqual(0, evaluator.compare(true, [:]))
		XCTAssertEqual(0, evaluator.compare(true, []))
	}

	func testCompareNumbers() {
		let evaluator = ExprEvaluator(operators: [:], vars: [:])

		XCTAssertEqual(0, evaluator.compare(0, 0))
		XCTAssertEqual(-1, evaluator.compare(0, 1))
		XCTAssertEqual(-1, evaluator.compare(0, true))
		XCTAssertEqual(0, evaluator.compare(0, false))
		XCTAssertNil(evaluator.compare(0, ""))
		XCTAssertNil(evaluator.compare(0, "abc"))
		XCTAssertNil(evaluator.compare(0, [:]))
		XCTAssertNil(evaluator.compare(0, []))

		XCTAssertEqual(1, evaluator.compare(1, 0))
		XCTAssertEqual(0, evaluator.compare(1, 1))
		XCTAssertEqual(0, evaluator.compare(1, true))
		XCTAssertEqual(1, evaluator.compare(1, false))
		XCTAssertNil(evaluator.compare(1, ""))
		XCTAssertNil(evaluator.compare(1, "abc"))
		XCTAssertNil(evaluator.compare(1, [:]))
		XCTAssertNil(evaluator.compare(1, []))

		XCTAssertEqual(0, evaluator.compare(1.0, 1))
		XCTAssertEqual(1, evaluator.compare(1.5, 1))
		XCTAssertEqual(1, evaluator.compare(2.0, 1))
		XCTAssertEqual(1, evaluator.compare(3.0, 1))

		XCTAssertEqual(0, evaluator.compare(1, 1.0))
		XCTAssertEqual(-1, evaluator.compare(1, 1.5))
		XCTAssertEqual(-1, evaluator.compare(1, 2.0))
		XCTAssertEqual(-1, evaluator.compare(1, 3.0))

		XCTAssertEqual(0, evaluator.compare(9_007_199_254_740_991, 9_007_199_254_740_991))
		XCTAssertEqual(-1, evaluator.compare(0, 9_007_199_254_740_991))
		XCTAssertEqual(1, evaluator.compare(9_007_199_254_740_991, 0))

		XCTAssertEqual(0, evaluator.compare(9007199254740991.0, 9007199254740991.0))
		XCTAssertEqual(-1, evaluator.compare(0.0, 9007199254740991.0))
		XCTAssertEqual(1, evaluator.compare(9007199254740991.0, 0.0))
	}

	func testCompareStrings() {
		let evaluator = ExprEvaluator(operators: [:], vars: [:])

		XCTAssertEqual(0, evaluator.compare("", ""))
		XCTAssertEqual(0, evaluator.compare("abc", "abc"))
		XCTAssertEqual(0, evaluator.compare("0", 0))
		XCTAssertEqual(0, evaluator.compare("1", 1))
		XCTAssertEqual(0, evaluator.compare("true", true))
		XCTAssertEqual(0, evaluator.compare("false", false))
		XCTAssertNil(evaluator.compare("", [:]))
		XCTAssertNil(evaluator.compare("abc", [:]))
		XCTAssertNil(evaluator.compare("", []))
		XCTAssertNil(evaluator.compare("abc", []))

		XCTAssertEqual(-1, evaluator.compare("abc", "bcd"))
		XCTAssertEqual(1, evaluator.compare("bcd", "abc"))
		XCTAssertEqual(-1, evaluator.compare("0", "1"))
		XCTAssertEqual(1, evaluator.compare("1", "0"))
		XCTAssertEqual(1, evaluator.compare("9", "100"))
		XCTAssertEqual(-1, evaluator.compare("100", "9"))
	}
}
