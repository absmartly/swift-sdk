import Testing

@testable import ABsmartly

// Ported from 1.x JsonExpr/Operators/AndCombinatorTest.swift and OrCombinatorTest.swift. 1.x counted
// the mock evaluator's `evaluate` and `booleanConvert` calls; here short-circuiting is checked by
// putting an `evaluationProbe` after the deciding item and asserting it was never evaluated.
@Suite struct AndCombinatorTests {
	@Test func combineTrue() {
		#expect(eval(apply("and", [true])).isTrue)
	}

	@Test func combineFalse() {
		#expect(!eval(apply("and", [false])).isTrue)
	}

	@Test func combineNull() {
		#expect(!eval(apply("and", [.null])).isTrue)
	}

	@Test func combineShortCircuit() {
		let marker = uniqueMarker()
		#expect(!eval(["and": [["value": true], ["value": false], evaluationProbe(marker)]]).isTrue)
		#expect(!wasEvaluated(marker))
	}

	@Test func combine() {
		#expect(eval(apply("and", [true, true])).isTrue)
		#expect(eval(apply("and", [true, true, true])).isTrue)

		#expect(!eval(apply("and", [true, false])).isTrue)
		#expect(!eval(apply("and", [false, true])).isTrue)
		#expect(!eval(apply("and", [false, false])).isTrue)
		#expect(!eval(apply("and", [false, false, false])).isTrue)
	}
}

@Suite struct OrCombinatorTests {
	@Test func combineTrue() {
		#expect(eval(apply("or", [true])).isTrue)
	}

	@Test func combineFalse() {
		#expect(!eval(apply("or", [false])).isTrue)
	}

	@Test func combineNull() {
		#expect(!eval(apply("or", [.null])).isTrue)
	}

	@Test func combineShortCircuit() {
		let marker = uniqueMarker()
		#expect(eval(["or": [["value": true], evaluationProbe(marker), ["value": true]]]).isTrue)
		#expect(!wasEvaluated(marker))
	}

	@Test func combine() {
		#expect(eval(apply("or", [true, true])).isTrue)
		#expect(eval(apply("or", [true, true, true])).isTrue)

		#expect(eval(apply("or", [true, false])).isTrue)
		#expect(eval(apply("or", [false, true])).isTrue)
		#expect(!eval(apply("or", [false, false])).isTrue)
		#expect(!eval(apply("or", [false, false, false])).isTrue)
	}
}
