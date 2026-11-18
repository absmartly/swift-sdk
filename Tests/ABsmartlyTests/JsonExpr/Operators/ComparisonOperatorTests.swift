import Testing

@testable import ABsmartly

@Suite struct ComparisonOperatorTests {
	private func rightSkippedWhenLeftIsNull(_ op: String, _ marker: String) -> Bool {
		let result = eval([op: [["value": .null], evaluationProbe(marker)]])
		return result == .null && !wasEvaluated(marker)
	}

	@Test func equals() {
		#expect(eval(apply("eq", [0, 0])).isTrue)
		#expect(!eval(apply("eq", [1, 0])).isTrue)
		#expect(!eval(apply("eq", [0, 1])).isTrue)
		#expect(eval(apply("eq", [.null, .null])) == .null)
		#expect(rightSkippedWhenLeftIsNull("eq", uniqueMarker()))

		#expect(eval(apply("eq", [[1, 2], [1, 2]])).isTrue)
		#expect(eval(apply("eq", [[1, 2], [2, 3]])) == .null)
		#expect(eval(apply("eq", [["a": 1, "b": 2], ["a": 1, "b": 2]])).isTrue)
		#expect(eval(apply("eq", [["a": 1, "b": 2], ["a": 3, "b": 4]])) == .null)
	}

	@Test func greaterThan() {
		#expect(!eval(apply("gt", [0, 0])).isTrue)
		#expect(eval(apply("gt", [1, 0])).isTrue)
		#expect(!eval(apply("gt", [0, 1])).isTrue)
		#expect(eval(apply("gt", [.null, .null])) == .null)
		#expect(rightSkippedWhenLeftIsNull("gt", uniqueMarker()))
	}

	@Test func greaterThanOrEqual() {
		#expect(eval(apply("gte", [0, 0])).isTrue)
		#expect(eval(apply("gte", [1, 0])).isTrue)
		#expect(!eval(apply("gte", [0, 1])).isTrue)
		#expect(eval(apply("gte", [.null, .null])) == .null)
		#expect(rightSkippedWhenLeftIsNull("gte", uniqueMarker()))
	}

	@Test func lessThan() {
		#expect(!eval(apply("lt", [0, 0])).isTrue)
		#expect(!eval(apply("lt", [1, 0])).isTrue)
		#expect(eval(apply("lt", [0, 1])).isTrue)
		#expect(eval(apply("lt", [.null, .null])) == .null)
		#expect(rightSkippedWhenLeftIsNull("lt", uniqueMarker()))
	}

	@Test func lessThanOrEqual() {
		#expect(eval(apply("lte", [0, 0])).isTrue)
		#expect(!eval(apply("lte", [1, 0])).isTrue)
		#expect(eval(apply("lte", [0, 1])).isTrue)
		#expect(eval(apply("lte", [.null, .null])) == .null)
		#expect(rightSkippedWhenLeftIsNull("lte", uniqueMarker()))
	}
}
