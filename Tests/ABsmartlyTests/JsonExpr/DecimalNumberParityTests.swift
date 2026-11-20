import Foundation
import Testing

@testable import ABsmartly

// Numbers JSONSerialization parses as decimals (more digits than a double holds, or an integer
// outside the 64-bit ranges) inside audiences and assignment rules. 1.5.0 kept the NSDecimalNumber,
// so two such numbers equal as doubles stay distinct inside arrays and objects, and truthiness is
// Foundation's `int64Value`. The Linux rows were measured by running 1.5.0 (swift-sdk main, Linux);
// the oracle rows recompute 1.5.0's answer from Foundation on whichever platform runs the test.
@Suite struct DecimalNumberParityTests {
	static let high = "0.1234567890123456789"
	static let low = "0.1234567890123456788"

	private static func audience(_ filter: String, _ attributes: [String: JSONValue] = [:]) -> Bool? {
		AudienceMatcher.evaluate(AudienceMatcher.parseAudience("{\"filter\":\(filter)}"), attributes)
	}

	// 1.5.0's evaluator formatter.
	private static let formatter: NumberFormatter = {
		let formatter = NumberFormatter()
		formatter.numberStyle = .decimal
		formatter.maximumFractionDigits = 15
		formatter.minimumIntegerDigits = 1
		formatter.decimalSeparator = "."
		formatter.groupingSize = 0
		return formatter
	}()

	private static func foundation(_ text: String) throws -> Any {
		try JSONSerialization.jsonObject(with: Data(text.utf8), options: [.fragmentsAllowed])
	}

	// MARK: Nested equality

	// Whether 1.5.0 found [high] equal to [low]: its Foundation collections compared.
	private static func nestedEqual() throws -> Bool {
		let expected = try #require(try foundation("[\(high)]") as? NSArray)
			.isEqual(to: try #require(try foundation("[\(low)]") as? [Any]))
		#if os(Linux)
			#expect(!expected)
		#endif
		return expected
	}

	@Test func nestedDecimalsKeepTheirPrecision() throws {
		let expected = try Self.nestedEqual()
		for (l, r) in [("[\(Self.high)]", "[\(Self.low)]"), ("{\"n\":\(Self.high)}", "{\"n\":\(Self.low)}")] {
			#expect(Self.audience("[{\"eq\":[{\"value\":\(l)},{\"value\":\(r)}]}]") == expected, "\(l) vs \(r)")
			#expect(Self.audience("[{\"eq\":[{\"value\":\(l)},{\"value\":\(l)}]}]") == true, "\(l)")
			#expect(ExprEvaluator.deepEquals(try ExprValue(parsing: l), try ExprValue(parsing: r)) == expected)
		}
		#expect(Self.audience("[{\"in\":[{\"value\":[[\(Self.high)]]},{\"value\":[\(Self.low)]}]}]") == expected)
	}

	// An attribute is a double, so it does not equal a decimal literal that rounds to it.
	@Test func doubleAttributeAgainstNestedDecimalLiteral() throws {
		let expected = try #require(try Self.foundation("[\(Self.high)]") as? NSArray)
			.isEqual(to: [NSNumber(value: 0.1234567890123456789)])
		#if os(Linux)
			#expect(!expected)
		#endif
		let attributes: [String: JSONValue] = ["a": [.double(0.1234567890123456789)]]
		#expect(Self.audience("[{\"eq\":[{\"var\":\"a\"},{\"value\":[\(Self.high)]}]}]", attributes) == expected)
		#expect(Self.audience("[{\"eq\":[{\"var\":\"a\"},{\"value\":[0.1]}]}]", ["a": [0.1]]) == true)
	}

	@Test func strictAudienceOnNestedDecimalsServesControl() throws {
		let expected = try Self.nestedEqual()
		let audience = "{\"filter\":[{\"eq\":[{\"value\":[\(Self.high)]},{\"value\":[\(Self.low)]}]}]}"
		let data = ContextAssignmentRulesTests.contextData(
			ContextAssignmentRulesTests.experimentJSON(
				rules: nil, split: [0, 0, 1], audience: audience, audienceStrict: true))
		let env = ContextEnv()
		let context = env.directContext(data: data, units: [.sessionID: "unit-1"])

		#expect(context.treatment(for: "exp") == (expected ? 2 : 0))
		#expect(env.log.exposures.first?.audienceMismatch == !expected)
	}

	@Test func ruleOnNestedDecimalsDoesNotMatch() throws {
		let expected = try Self.nestedEqual()
		let conditions = { (l: String, r: String) in "{\"eq\":[{\"value\":\(l)},{\"value\":\(r)}]}" }
		for (l, r) in [("[\(Self.high)]", "[\(Self.low)]"), ("{\"n\":\(Self.high)}", "{\"n\":\(Self.low)}")] {
			let data = ContextAssignmentRulesTests.contextData(
				ContextAssignmentRulesTests.experimentJSON(
					rules: ContextAssignmentRulesTests.rules(
						"{\"type\":\"assign\",\"variant\":2,\"conditions\":\(conditions(l, r))}"),
					split: [1, 0, 0]))
			let context = ContextEnv().directContext(data: data, units: [.sessionID: "unit-1"])
			#expect(context.treatment(for: "exp") == (expected ? 2 : 0), "\(l) vs \(r)")

			let rules = AudienceMatcher.parseRules(
				ContextAssignmentRulesTests.rules(
					"{\"type\":\"assign\",\"variant\":2,\"conditions\":\(conditions(l, l))}"))
			#expect(
				rules.flatMap { AudienceMatcher.evaluateRules($0, environmentName: nil, attributes: [:]) }
					== .assign(variant: 2))
		}
	}

	// MARK: Truthiness

	// 1.5.0's booleanConvert: `int64Value != 0` of the parsed number. A decimal beyond Int64 converts
	// to 0 on Linux, so 2^64 is false; one with a fraction truncates, so 0.99999999999999999999 is too.
	static let truthinessTable: [(literal: String, linux: Bool)] = [
		("18446744073709551616", false),
		("36893488147419103232", false),
		("-18446744073709551616", false),
		("0.99999999999999999999", false),
		("12345678901234567890123", true),
		("100000000000000000000.5", true),
		("18446744073709551615", true),
		("1e20", true),
		("0.5", false),
		("1.5", true),
	]

	@Test(arguments: truthinessTable)
	func truthiness(_ row: (literal: String, linux: Bool)) throws {
		let number = try #require(try Self.foundation(row.literal) as? NSNumber)
		let expected = number.int64Value != 0
		#if os(Linux)
			#expect(expected == row.linux, "\(row.literal)")
		#endif

		#expect(Self.audience("[{\"value\":\(row.literal)}]") == expected, "\(row.literal)")
		#expect(Self.audience("[{\"not\":{\"value\":\(row.literal)}}]") == !expected, "\(row.literal)")

		let rules = AudienceMatcher.parseRules(
			ContextAssignmentRulesTests.rules(
				"{\"type\":\"assign\",\"variant\":1,\"conditions\":{\"value\":\(row.literal)}}"))
		let action = rules.flatMap { AudienceMatcher.evaluateRules($0, environmentName: nil, attributes: [:]) }
		#expect(action == (expected ? .assign(variant: 1) : nil), "\(row.literal)")
	}

	// MARK: Unchanged conversions

	// Comparisons and strings read a decimal through Foundation's `doubleValue`, as 1.5.0 did (on
	// Linux that can be an ulp away from the nearest double).
	@Test func decimalsConvertThroughTheirDouble() throws {
		let evaluator = ExprEvaluator(vars: [:])
		let high = try ExprValue(parsing: Self.high)
		let double = try #require(try Self.foundation(Self.high) as? NSNumber).doubleValue
		#expect(evaluator.compare(high, try ExprValue(parsing: Self.low)) == 0)
		#expect(evaluator.compare(high, .double(double)) == 0)
		#expect(evaluator.compare(high, .double(double.nextUp)) == -1)
		// 1.5.0 formatted the parsed NSNumber itself.
		for literal in [Self.high, "18446744073709551616", "-18446744073709551616", "12345678901234567890123"] {
			let number = try #require(try Self.foundation(literal) as? NSNumber)
			#expect(evaluator.stringConvert(try ExprValue(parsing: literal)) == Self.formatter.string(from: number), "\(literal)")
		}
		#if os(Linux)
			#expect(evaluator.stringConvert(high) == "0.123456789012346")
			#expect(evaluator.stringConvert(try ExprValue(parsing: "18446744073709551616")) == "18446744073709552000")
		#endif
		#expect(high.jsonValue == .double(double))
		#expect(high.jsonValue == (try JSONValue(parsing: Self.high)))
		#expect(high == (try ExprValue(parsing: Self.high)))
		#expect(high != (try ExprValue(parsing: Self.low)))
		#expect(high != .double(double))
	}
}
