import Testing

@testable import ABsmartly

// Ported from 1.x JsonExpr/Operators/NotOperatorTest.swift, NullOperatorTest.swift,
// ValueOperatorTest.swift and VarOperatorTest.swift. 1.x's mock evaluator returned "abc" for the
// path "a/b/c"; here the variables hold that value. "evaluate is not called" (value, var) is
// checked by passing an `evaluationProbe` as the argument.
@Suite struct NotOperatorTests {
	@Test func `false`() {
		#expect(eval(unary("not", false)).isTrue)
	}

	@Test func `true`() {
		#expect(!eval(unary("not", true)).isTrue)
	}

	@Test func null() {
		#expect(eval(unary("not", .null)).isTrue)
	}
}

@Suite struct NullOperatorTests {
	@Test func null() {
		#expect(eval(unary("null", .null)).isTrue)
	}

	@Test func notNull() {
		#expect(!eval(unary("null", true)).isTrue)
		#expect(!eval(unary("null", false)).isTrue)
		#expect(!eval(unary("null", 0)).isTrue)
	}
}

@Suite struct ValueOperatorTests {
	@Test func evaluate() {
		#expect(eval(["value": 0]) == 0)
		#expect(eval(["value": 1]) == 1)
		#expect(eval(["value": true]) == true)
		#expect(eval(["value": false]) == false)
		#expect(eval(["value": ""]) == "")
		#expect(eval(["value": [:]]) == [:])
		#expect(eval(["value": []]) == [])
		#expect(eval(["value": .null]) == .null)

		let marker = uniqueMarker()
		let probe = evaluationProbe(marker)
		#expect(eval(["value": probe]) == probe)
		#expect(!wasEvaluated(marker))
	}
}

@Suite struct VarOperatorTests {
	@Test func evaluate() {
		let vars: [String: JSONValue] = ["a": ["b": ["c": "abc"]]]
		#expect(eval(["var": "a/b/c"], vars: vars) == "abc")

		let marker = uniqueMarker()
		#expect(eval(["var": evaluationProbe(marker)], vars: vars) == .null)
		#expect(!wasEvaluated(marker))
	}
}
