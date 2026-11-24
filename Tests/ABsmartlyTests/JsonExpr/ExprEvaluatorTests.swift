import Foundation
import Testing

@testable import ABsmartly

#if DEBUG
	private let countsConversions = true
#else
	private let countsConversions = false
#endif

@Suite struct ExprEvaluatorTests {
	@Test func evaluateConsidersListAsAndCombinator() {
		let evaluator = ExprEvaluator(vars: [:])
		let args: ExprValue = [["value": true], ["value": false]]

		#expect(evaluator.evaluate(args) != .null)
		#expect(evaluator.evaluate(args) == evaluator.evaluate(["and": args]))
		#expect(evaluator.evaluate(args) != evaluator.evaluate(["or": args]))
		#expect(evaluator.evaluate(args) == false)
	}

	// The positive control for `evaluationProbe`, which the dispatch and
	// short-circuit tests rely on to observe that an argument was not evaluated.
	@Test func evaluationProbeIsDetectedWhenEvaluated() {
		let marker = uniqueMarker()
		#expect(ExprEvaluator(vars: [:]).evaluate(ExprValue(evaluationProbe(marker))) == .null)
		#expect(wasEvaluated(marker))
	}

	@Test func evaluateReturnsNullIfOperatorNotFound() {
		let marker = uniqueMarker()
		let evaluator = ExprEvaluator(vars: [:])
		#expect(evaluator.evaluate(["not_found": true]) == .null)
		#expect(evaluator.evaluate(["not_found": ExprValue(evaluationProbe(marker))]) == .null)

		#expect(!wasEvaluated(marker))
	}

	@Test func evaluateCallsOperatorWithArgs() {
		let args: ExprValue = [1, 2, 3]
		let evaluator = ExprEvaluator(vars: [:])
		#expect(evaluator.evaluate(["value": args]) == args)
	}

	@Test func booleanConvert() {
		let evaluator = ExprEvaluator(vars: [:])

		#expect(evaluator.booleanConvert([:]) == true)
		#expect(evaluator.booleanConvert([]) == true)
		#expect(evaluator.booleanConvert(.null) == false)

		#expect(evaluator.booleanConvert(true) == true)
		#expect(evaluator.booleanConvert(1) == true)
		#expect(evaluator.booleanConvert(2) == true)
		#expect(evaluator.booleanConvert("abc") == true)
		#expect(evaluator.booleanConvert("1") == true)

		#expect(evaluator.booleanConvert(false) == false)
		#expect(evaluator.booleanConvert(0) == false)
		#expect(evaluator.booleanConvert("") == false)
		#expect(evaluator.booleanConvert("0") == false)
		#expect(evaluator.booleanConvert("false") == false)
	}

	@Test func numberConvert() {
		let evaluator = ExprEvaluator(vars: [:])

		#expect(evaluator.numberConvert([:]) == nil)
		#expect(evaluator.numberConvert([]) == nil)
		#expect(evaluator.numberConvert(.null) == nil)
		#expect(evaluator.numberConvert("") == nil)
		#expect(evaluator.numberConvert("abcd") == nil)
		#expect(evaluator.numberConvert("x1234") == nil)

		#expect(evaluator.numberConvert(true) == 1.0)
		#expect(evaluator.numberConvert(false) == 0.0)

		#expect(evaluator.numberConvert(-1.0) == -1.0)
		#expect(evaluator.numberConvert(0.0) == 0.0)
		#expect(evaluator.numberConvert(1.0) == 1.0)
		#expect(evaluator.numberConvert(1.5) == 1.5)
		#expect(evaluator.numberConvert(2.0) == 2.0)
		#expect(evaluator.numberConvert(3.0) == 3.0)

		#expect(evaluator.numberConvert(-1) == -1.0)
		#expect(evaluator.numberConvert(0) == 0.0)
		#expect(evaluator.numberConvert(1) == 1.0)
		#expect(evaluator.numberConvert(2) == 2.0)
		#expect(evaluator.numberConvert(3) == 3.0)
		#expect(evaluator.numberConvert(2_147_483_647) == 2147483647.0)
		#expect(evaluator.numberConvert(-2_147_483_647) == -2147483647.0)
		#expect(evaluator.numberConvert(9_007_199_254_740_991) == 9007199254740991.0)
		#expect(evaluator.numberConvert(-9_007_199_254_740_991) == -9007199254740991.0)

		#expect(evaluator.numberConvert("-1") == -1.0)
		#expect(evaluator.numberConvert("0") == 0.0)
		#expect(evaluator.numberConvert("1") == 1.0)
		#expect(evaluator.numberConvert("1.5") == 1.5)
		#expect(evaluator.numberConvert("2") == 2.0)
		#expect(evaluator.numberConvert("3.0") == 3.0)
	}

	@Test func stringConvert() {
		let evaluator = ExprEvaluator(vars: [:])

		#expect(evaluator.stringConvert(.null) == nil)
		#expect(evaluator.stringConvert([:]) == nil)
		#expect(evaluator.stringConvert([]) == nil)

		#expect(evaluator.stringConvert(true) == "true")
		#expect(evaluator.stringConvert(false) == "false")

		#expect(evaluator.stringConvert("") == "")
		#expect(evaluator.stringConvert("abc") == "abc")

		#expect(evaluator.stringConvert(-1.0) == "-1")
		#expect(evaluator.stringConvert(0.0) == "0")
		#expect(evaluator.stringConvert(1.0) == "1")
		#expect(evaluator.stringConvert(1.5) == "1.5")
		#expect(evaluator.stringConvert(2.0) == "2")
		#expect(evaluator.stringConvert(3.0) == "3")
		#expect(evaluator.stringConvert(2147483647.0) == "2147483647")
		#expect(evaluator.stringConvert(-2147483647.0) == "-2147483647")
		#expect(evaluator.stringConvert(9007199254740991.0) == "9007199254740991")
		#expect(evaluator.stringConvert(-9007199254740991.0) == "-9007199254740991")
		#expect(evaluator.stringConvert(0.9007199254740991) == "0.900719925474099")
		#expect(evaluator.stringConvert(-0.9007199254740991) == "-0.900719925474099")

		#expect(evaluator.stringConvert(-1) == "-1")
		#expect(evaluator.stringConvert(0) == "0")
		#expect(evaluator.stringConvert(1) == "1")
		#expect(evaluator.stringConvert(2) == "2")
		#expect(evaluator.stringConvert(3) == "3")
		#expect(evaluator.stringConvert(2_147_483_647) == "2147483647")
		#expect(evaluator.stringConvert(-2_147_483_647) == "-2147483647")
		#expect(evaluator.stringConvert(9_007_199_254_740_991) == "9007199254740991")
		#expect(evaluator.stringConvert(-9_007_199_254_740_991) == "-9007199254740991")
	}

	@Test func extractVar() {
		let vars: [String: JSONValue] = [
			"a": 1,
			"b": true,
			"c": false,
			"d": [1, 2, 3],
			"e": [1, ["z": 2], 3],
			"f": ["y": ["x": 3, "0": 10]],
		]

		let evaluator = ExprEvaluator(vars: vars)

		#expect(evaluator.extractVar("a") == 1)
		#expect(evaluator.extractVar("b") == true)
		#expect(evaluator.extractVar("c") == false)
		#expect(evaluator.extractVar("d") == [1, 2, 3])
		#expect(evaluator.extractVar("e") == [1, ["z": 2], 3])
		#expect(evaluator.extractVar("f") == ["y": ["x": 3, "0": 10]])

		#expect(evaluator.extractVar("a/0") == .null)
		#expect(evaluator.extractVar("a/b") == .null)
		#expect(evaluator.extractVar("b/0") == .null)
		#expect(evaluator.extractVar("b/e") == .null)

		#expect(evaluator.extractVar("d/0") == 1)
		#expect(evaluator.extractVar("d/1") == 2)
		#expect(evaluator.extractVar("d/2") == 3)
		#expect(evaluator.extractVar("d/3") == .null)

		#expect(evaluator.extractVar("e/0") == 1)
		#expect(evaluator.extractVar("e/1/z") == 2)
		#expect(evaluator.extractVar("e/2") == 3)
		#expect(evaluator.extractVar("e/1/0") == .null)

		#expect(evaluator.extractVar("f/y") == ["x": 3, "0": 10])
		#expect(evaluator.extractVar("f/y/x") == 3)
		#expect(evaluator.extractVar("f/y/0") == 10)
	}

	@Test(.enabled(if: countsConversions), arguments: [10, 10_000]) func firstAttributeMatchSkipsRemainingConversions(size: Int) {
		let roles = JSONValue.array(["admin"] + Array(repeating: "guest", count: size - 1))
		let evaluator = ExprEvaluator(vars: ["roles": roles])
		let count = Locked(0)
		ExprValue.$attributeConversionCount.withValue(count) {
			#expect(evaluator.evaluate(["in": [["var": "roles"], ["value": "admin"]]]) == true)
		}
		#expect(count.withLock { $0 } == 2)
	}

	@Test(.enabled(if: countsConversions), arguments: [10, 10_000]) func nestedAttributePathAndMatchSkipUnvisitedSubtrees(size: Int) {
		let unused = JSONValue.array(Array(repeating: ["unused": [1, 2, 3]], count: size))
		let roles = JSONValue.array([["name": "admin"], unused])
		let evaluator = ExprEvaluator(vars: ["profiles": [["roles": roles], unused]])
		let count = Locked(0)
		ExprValue.$attributeConversionCount.withValue(count) {
			#expect(evaluator.evaluate(["in": [["var": "profiles/0/roles"], ["value": ["name": "admin"]]]]) == true)
		}
		#expect(count.withLock { $0 } == 3)
	}

	@Test(.enabled(if: countsConversions), arguments: [10, 10_000]) func nestedAttributeEqualityStopsAtFirstUnequalLeaf(size: Int) {
		let values = JSONValue.array([0] + Array(repeating: 2, count: size - 1))
		let literal = ExprValue.array([1] + Array(repeating: 2, count: size - 1))
		let evaluator = ExprEvaluator(vars: ["profile": ["values": values]])
		let count = Locked(0)
		ExprValue.$attributeConversionCount.withValue(count) {
			#expect(evaluator.evaluate(["eq": [["var": "profile"], ["value": ["values": literal]]]]) == .null)
		}
		#expect(count.withLock { $0 } == 3)
	}

	@Test(.enabled(if: countsConversions), arguments: [10, 10_000])
	func attributeOnTheRightStopsAtFirstUnequalLeaf(size: Int) {
		let values = JSONValue.array([0] + Array(repeating: 2, count: size - 1))
		let literal = ExprValue.array([1] + Array(repeating: 2, count: size - 1))
		let evaluator = ExprEvaluator(vars: ["profile": ["values": values]])
		let count = Locked(0)
		ExprValue.$attributeConversionCount.withValue(count) {
			#expect(evaluator.evaluate(["eq": [["value": ["values": literal]], ["var": "profile"]]]) == .null)
		}
		#expect(count.withLock { $0 } == 3)
	}

	@Test(.enabled(if: countsConversions), arguments: [10, 10_000])
	func attributeObjectOnTheRightConvertsOnlyVisitedValues(size: Int) {
		let keys = (0..<size).map { "k\($0)" }
		let attribute = JSONValue.object(Dictionary(uniqueKeysWithValues: keys.map { ($0, JSONValue.int(0)) }))
		let literal = ExprValue.object(Dictionary(uniqueKeysWithValues: keys.map { ($0, ExprValue.int(1)) }))
		let evaluator = ExprEvaluator(vars: ["o": attribute])
		let count = Locked(0)
		ExprValue.$attributeConversionCount.withValue(count) {
			#expect(evaluator.evaluate(["eq": [["value": literal], ["var": "o"]]]) == .null)
		}
		#expect(count.withLock { $0 } == 2)
	}

	@Test(.enabled(if: countsConversions)) func attributeObjectMembershipDoesNotConvertValues() {
		let evaluator = ExprEvaluator(vars: ["profile": ["roles": ["admin", "guest"], "extra": [1, 2, 3]]])
		let count = Locked(0)
		ExprValue.$attributeConversionCount.withValue(count) {
			#expect(evaluator.evaluate(["in": [["var": "profile"], ["value": "roles"]]]) == true)
		}
		#expect(count.withLock { $0 } == 1)
	}

	@Test func attributeObjectMembershipChecksTheKey() {
		let evaluator = ExprEvaluator(vars: ["profile": ["roles": ["admin"]], "empty": [:]])
		#expect(evaluator.evaluate(["in": [["var": "profile"], ["value": "roles"]]]) == true)
		#expect(evaluator.evaluate(["in": [["var": "profile"], ["value": "missing"]]]) == false)
		#expect(evaluator.evaluate(["in": [["var": "empty"], ["value": "roles"]]]) == false)
	}

	@Test func nestedAttributeStringsCompareByCodeUnits() {
		let evaluator = ExprEvaluator(vars: ["names": ["caf\u{E9}"]])
		#expect(evaluator.evaluate(["eq": [["var": "names"], ["value": ["cafe\u{301}"]]]]) == .null)
		#expect(evaluator.evaluate(["eq": [["var": "names"], ["value": ["caf\u{E9}"]]]]) == true)
	}

	@Test func attributeCollectionEqualityChecksSizesAndKeys() {
		let evaluator = ExprEvaluator(vars: ["roles": ["a", "b"], "o": ["x": 1, "y": 2], "p": ["x": 1]])
		#expect(evaluator.evaluate(["eq": [["var": "roles"], ["value": ["a"]]]]) == .null)
		#expect(evaluator.evaluate(["eq": [["value": ["a"]], ["var": "roles"]]]) == .null)
		#expect(evaluator.evaluate(["eq": [["value": ["a", "b", "c"]], ["var": "roles"]]]) == .null)
		#expect(evaluator.evaluate(["eq": [["var": "roles"], ["value": ["a", "b"]]]]) == true)
		#expect(evaluator.evaluate(["eq": [["value": ["x": 1, "y": 2]], ["var": "o"]]]) == true)
		#expect(evaluator.evaluate(["eq": [["value": ["x": 2, "y": 1]], ["var": "o"]]]) == .null)
		#expect(evaluator.evaluate(["eq": [["value": ["x": 1, "z": 2]], ["var": "o"]]]) == .null)
		#expect(evaluator.evaluate(["eq": [["var": "p"], ["value": ["x": 1, "y": 2]]]]) == .null)
		#expect(evaluator.evaluate(["eq": [["value": ["x": 1, "y": 2]], ["var": "p"]]]) == .null)
		#expect(evaluator.evaluate(["eq": [["var": "o"], ["var": "p"]]]) == .null)
		#expect(evaluator.evaluate(["eq": [["var": "o"], ["var": "o"]]]) == true)
	}

	@Test func attributeCollectionsAreTruthy() {
		let vars: [String: JSONValue] = ["roles": ["a"], "o": ["x": 1], "empty": [], "none": [:]]
		let evaluator = ExprEvaluator(vars: vars)
		for name in vars.keys {
			#expect(evaluator.evaluate(["not": ["var": .string(name)]]) == false, "\(name)")
			#expect(JsonExpr.evaluateBoolean([["var": .string(name)]], vars: vars), "\(name)")
		}
	}

	@Test func attributeCollectionsCompareAndConvert() {
		let evaluator = ExprEvaluator(vars: ["d": [1, 2, 3], "f": ["x": 3]])
		#expect(evaluator.extractVar("d") != [1, 2])
		#expect(evaluator.extractVar("d") != [1, 2, 4])
		#expect(evaluator.extractVar("f") != ["x": 4])
		#expect(evaluator.extractVar("f") != ["y": 3])
		#expect(evaluator.extractVar("d") == .attributeArray([1, 2, 3]))
		#expect(evaluator.extractVar("f") == .attributeObject(["x": 3]))
		#expect(evaluator.extractVar("d").arrayValue == nil)
	}

	@Test(.enabled(if: countsConversions)) func attributeConversionCounterIncludesVisitedElements() {
		let evaluator = ExprEvaluator(vars: ["roles": ["admin", "guest", "owner"]])
		let count = Locked(0)
		ExprValue.$attributeConversionCount.withValue(count) {
			#expect(evaluator.evaluate(["in": [["var": "roles"], ["value": "missing"]]]) == false)
		}
		#expect(count.withLock { $0 } == 4)
	}

	@Test func compareNull() {
		let evaluator = ExprEvaluator(vars: [:])

		#expect(evaluator.compare(.null, .null) == 0)

		#expect(evaluator.compare(.null, 0) == nil)
		#expect(evaluator.compare(.null, 1) == nil)
		#expect(evaluator.compare(.null, true) == nil)
		#expect(evaluator.compare(.null, false) == nil)
		#expect(evaluator.compare(.null, "") == nil)
		#expect(evaluator.compare(.null, "abc") == nil)
		#expect(evaluator.compare(.null, [:]) == nil)
		#expect(evaluator.compare(.null, []) == nil)
	}

	@Test func compareObjects() {
		let evaluator = ExprEvaluator(vars: [:])

		#expect(evaluator.compare([:], 0) == nil)
		#expect(evaluator.compare([:], 1) == nil)
		#expect(evaluator.compare([:], true) == nil)
		#expect(evaluator.compare([:], false) == nil)
		#expect(evaluator.compare([:], "") == nil)
		#expect(evaluator.compare([:], "abc") == nil)
		#expect(evaluator.compare([:], [:]) == 0)
		#expect(evaluator.compare(["a": 1], ["a": 1]) == 0)
		#expect(evaluator.compare(["a": 1], ["b": 2]) == nil)
		#expect(evaluator.compare([:], []) == nil)

		#expect(evaluator.compare([], 0) == nil)
		#expect(evaluator.compare([], 1) == nil)
		#expect(evaluator.compare([], true) == nil)
		#expect(evaluator.compare([], false) == nil)
		#expect(evaluator.compare([], "") == nil)
		#expect(evaluator.compare([], "abc") == nil)
		#expect(evaluator.compare([], [:]) == nil)
		#expect(evaluator.compare([], []) == 0)
		#expect(evaluator.compare([1, 2], [1, 2]) == 0)
		#expect(evaluator.compare([1, 2], [3, 4]) == nil)
	}

	@Test func compareBooleans() {
		let evaluator = ExprEvaluator(vars: [:])

		#expect(evaluator.compare(false, 0) == 0)
		#expect(evaluator.compare(false, 1) == -1)
		#expect(evaluator.compare(false, true) == -1)
		#expect(evaluator.compare(false, false) == 0)
		#expect(evaluator.compare(false, "") == 0)
		#expect(evaluator.compare(false, "abc") == -1)
		#expect(evaluator.compare(false, [:]) == -1)
		#expect(evaluator.compare(false, []) == -1)

		#expect(evaluator.compare(true, 0) == 1)
		#expect(evaluator.compare(true, 1) == 0)
		#expect(evaluator.compare(true, true) == 0)
		#expect(evaluator.compare(true, false) == 1)
		#expect(evaluator.compare(true, "") == 1)
		#expect(evaluator.compare(true, "abc") == 0)
		#expect(evaluator.compare(true, [:]) == 0)
		#expect(evaluator.compare(true, []) == 0)
	}

	@Test func compareNumbers() {
		let evaluator = ExprEvaluator(vars: [:])

		#expect(evaluator.compare(0, 0) == 0)
		#expect(evaluator.compare(0, 1) == -1)
		#expect(evaluator.compare(0, true) == -1)
		#expect(evaluator.compare(0, false) == 0)
		#expect(evaluator.compare(0, "") == nil)
		#expect(evaluator.compare(0, "abc") == nil)
		#expect(evaluator.compare(0, [:]) == nil)
		#expect(evaluator.compare(0, []) == nil)

		#expect(evaluator.compare(1, 0) == 1)
		#expect(evaluator.compare(1, 1) == 0)
		#expect(evaluator.compare(1, true) == 0)
		#expect(evaluator.compare(1, false) == 1)
		#expect(evaluator.compare(1, "") == nil)
		#expect(evaluator.compare(1, "abc") == nil)
		#expect(evaluator.compare(1, [:]) == nil)
		#expect(evaluator.compare(1, []) == nil)

		#expect(evaluator.compare(1.0, 1) == 0)
		#expect(evaluator.compare(1.5, 1) == 1)
		#expect(evaluator.compare(2.0, 1) == 1)
		#expect(evaluator.compare(3.0, 1) == 1)

		#expect(evaluator.compare(1, 1.0) == 0)
		#expect(evaluator.compare(1, 1.5) == -1)
		#expect(evaluator.compare(1, 2.0) == -1)
		#expect(evaluator.compare(1, 3.0) == -1)

		#expect(evaluator.compare(9_007_199_254_740_991, 9_007_199_254_740_991) == 0)
		#expect(evaluator.compare(0, 9_007_199_254_740_991) == -1)
		#expect(evaluator.compare(9_007_199_254_740_991, 0) == 1)

		#expect(evaluator.compare(9007199254740991.0, 9007199254740991.0) == 0)
		#expect(evaluator.compare(0.0, 9007199254740991.0) == -1)
		#expect(evaluator.compare(9007199254740991.0, 0.0) == 1)
	}

	@Test func compareStrings() {
		let evaluator = ExprEvaluator(vars: [:])

		#expect(evaluator.compare("", "") == 0)
		#expect(evaluator.compare("abc", "abc") == 0)
		#expect(evaluator.compare("0", 0) == 0)
		#expect(evaluator.compare("1", 1) == 0)
		#expect(evaluator.compare("true", true) == 0)
		#expect(evaluator.compare("false", false) == 0)
		#expect(evaluator.compare("", [:]) == nil)
		#expect(evaluator.compare("abc", [:]) == nil)
		#expect(evaluator.compare("", []) == nil)
		#expect(evaluator.compare("abc", []) == nil)

		#expect(evaluator.compare("abc", "bcd") == -1)
		#expect(evaluator.compare("bcd", "abc") == 1)
		#expect(evaluator.compare("0", "1") == -1)
		#expect(evaluator.compare("1", "0") == 1)
		#expect(evaluator.compare("9", "100") == 1)
		#expect(evaluator.compare("100", "9") == -1)
	}
}
