import Testing

@testable import ABsmartly

// Ported from 1.x JsonExpr/Operators/InOperatorTest.swift. 1.x also asserted the mock evaluator's
// `evaluate`, `stringConvert` and `compare` call counts and arguments (internals of 2.0's switch);
// the results are asserted unchanged, and an array haystack's early exit on the first match is
// checked by result only.
@Suite struct InOperatorTests {
	@Test func string() {
		#expect(eval(apply("in", ["abcdefghijk", "abc"])).isTrue)
		#expect(eval(apply("in", ["abcdefghijk", "def"])).isTrue)
		#expect(!eval(apply("in", ["abcdefghijk", "xxx"])).isTrue)
		#expect(eval(apply("in", ["abcdefghijk", .null])) == .null)
		#expect(eval(apply("in", [.null, "abc"])) == .null)
	}

	@Test func arrayEmpty() {
		#expect(!eval(apply("in", [[], 1])).isTrue)
		#expect(!eval(apply("in", [[], "1"])).isTrue)
		#expect(!eval(apply("in", [[], true])).isTrue)
		#expect(!eval(apply("in", [[], false])).isTrue)
		#expect(eval(apply("in", [[], .null])) == .null)
	}

	@Test func arrayCompares() {
		let haystack01: JSONValue = [0, 1]
		let haystack12: JSONValue = [1, 2]

		#expect(!eval(apply("in", [haystack01, 2])).isTrue)
		#expect(!eval(apply("in", [haystack12, 0])).isTrue)
		#expect(eval(apply("in", [haystack12, 1])).isTrue)
		#expect(eval(apply("in", [haystack12, 2])).isTrue)
	}

	@Test func object() {
		let haystackab: JSONValue = ["a": 1, "b": 2]
		let haystackbc: JSONValue = ["b": 2, "c": 3, "0": 100]

		#expect(!eval(apply("in", [haystackab, "c"])).isTrue)
		#expect(!eval(apply("in", [haystackbc, "a"])).isTrue)
		#expect(eval(apply("in", [haystackbc, "b"])).isTrue)
		#expect(eval(apply("in", [haystackbc, "c"])).isTrue)
		#expect(eval(apply("in", [haystackbc, 0])).isTrue)
	}
}
