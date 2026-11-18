import Testing

@testable import ABsmartly

@Suite struct BinaryOperatorNullSafetyTests {
	@Test func equalsNullNull() {
		#expect(eval(apply("eq", [.null, .null])) == .null)
	}

	@Test func equalsNullVsNumber() {
		let result = eval(apply("eq", [.null, 1]))
		#expect(!result.isTrue)
		#expect(result == .null)
	}

	@Test func equalsNumberVsNull() {
		let result = eval(apply("eq", [1, .null]))
		#expect(!result.isTrue)
		#expect(result == .null)
	}

	@Test func greaterThanNullNull() {
		#expect(!eval(apply("gt", [.null, .null])).isTrue)
	}

	@Test func lessThanNullNull() {
		#expect(!eval(apply("lt", [.null, .null])).isTrue)
	}

	@Test func greaterThanOrEqualNullNull() {
		#expect(eval(apply("gte", [.null, .null])) == .null)
	}

	@Test func lessThanOrEqualNullNull() {
		#expect(eval(apply("lte", [.null, .null])) == .null)
	}

	@Test func matchWithNullLhsDoesNotCrash() {
		#expect(eval(apply("match", [.null, "abc"])) == .null)
	}

	@Test func matchWithNullRhsDoesNotCrash() {
		#expect(eval(apply("match", ["abc", .null])) == .null)
	}

	@Test func inWithNullHaystack() {
		#expect(eval(apply("in", ["abc", .null])) == .null)
	}

	@Test func binaryOperatorNotEnoughArgs() {
		#expect(eval(apply("eq", [1])) == .null)
		#expect(eval(["eq": .null]) == .null)
	}
}
