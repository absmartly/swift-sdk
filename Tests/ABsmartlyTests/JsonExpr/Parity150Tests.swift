import Foundation
import Testing

@testable import ABsmartly

// Not ported from 1.x: edge tables pinning 2.0 to 1.5.0's answers (which follow the javascript-sdk
// reference semantics). Every expected value below was measured by running 1.5.0 itself
// (swift-sdk at 1.5.0, Linux) on the same input.
//
// Two of these inputs differed before 2.0's `JSONValue(parsing:)` was switched from `JSONDecoder`
// to `JSONSerialization` (the parser 1.5.0 uses through SwiftyJSON) and `assign.variant` was read
// as a double like 1.5.0:
// - `-0.0`, `-0e0` and `-1e-400` decoded as the integer 0, so they stringified as "0" (1.5.0:
//   "-0") and `{"match": [{"value": -0.0}, "^-"]}` was false (1.5.0: true).
// - an `assign` variant of 9223372036854775807 was in range as an Int64 (1.5.0 reads it as the
//   double 2^63, out of range: -1), and 9007199254740993 was kept exact (1.5.0: 9007199254740992).
//
// Known remaining difference, not pinned: an unsigned integer literal from 2^63 to 2^64-1
// (9223372036854775808, 12345678901234567890, 18446744073709551615). On Linux 1.5.0 compares it
// as the positive double, but its *string* form wraps to a negative Int64 ("-9223372036854775808",
// "-6101065172474983726", "-1": swift-corelibs-foundation's NumberFormatter formats a UInt64
// NSNumber as signed), so `match`/`in`/string `eq` see a negative number. 2.0 stores the double and
// formats it ("9223372036854776000"). JSONValue's cases cannot hold "positive number, negative
// text" without a new case, so this is left for both lines to fix together.

// MARK: - Assignment rule `assign.variant`

@Suite struct AssignVariantParityTests {
	enum Outcome: Equatable, CustomStringConvertible {
		/// The rule is applied with this variant (out of bounds when not in 0..<variants).
		case selected(Int)
		/// The rule is skipped (not an integer), so the next rule decides.
		case skipped
		/// The whole `assignmentRules` string does not parse, so no rule applies.
		case unparseable

		var description: String {
			switch self {
			case .selected(let v): return "selected(\(v))"
			case .skipped: return "skipped"
			case .unparseable: return "unparseable"
			}
		}
	}

	// Int(exactly:) of the double, else -1 (out of bounds), as 1.5.0 computes it, so 32-bit
	// watchOS gets its own answer for values beyond Int32.
	private static func outOfRangeOr(_ d: Double) -> Outcome {
		.selected(Int(exactly: d) ?? -1)
	}

	static let table: [(literal: String, outcome: Outcome)] = [
		("1", .selected(1)),
		("1.0", .selected(1)),
		("1e0", .selected(1)),
		("1E0", .selected(1)),
		("2.0", .selected(2)),
		("0", .selected(0)),
		("-0", .selected(0)),
		("-0.0", .selected(0)),
		("1e-400", .selected(0)),
		("-1e-400", .selected(0)),
		("0.99999999999999999", .selected(1)),
		("-1", .selected(-1)),
		("1.5", .skipped),
		("1e-9", .skipped),
		("4.9e-324", .skipped),
		("1.0000000000000002", .skipped),
		("2147483648", outOfRangeOr(2147483648)),
		("4294967297", outOfRangeOr(4294967297)),
		("-2147483649", outOfRangeOr(-2147483649)),
		("9007199254740993", outOfRangeOr(9007199254740992)),
		("9007199254740992.5", outOfRangeOr(9007199254740992)),
		("9223372036854775807", .selected(-1)),
		("9223372036854775808", .selected(-1)),
		("-9223372036854775809", outOfRangeOr(-9223372036854775808)),
		("18446744073709551616", .selected(-1)),
		("1e20", .selected(-1)),
		("99999999999999999999", .selected(-1)),
		("1e300", .selected(-1)),
		// 1e400 overflows a double. 1.5.0's SwiftyJSON (JSONSerialization) rejects the whole
		// document, so the experiment has no rules; 2.0 parses with the same JSONSerialization and
		// does the same (JSONDecoder, which 2.0 used before, rejected it as well).
		("1e400", .unparseable),
		("-1e400", negativeOverflowOutcome),
	]

	#if canImport(Darwin)
		// Apple Foundation accepts -1e400 as -Infinity; the non-finite variant is skipped.
		static let negativeOverflowOutcome: Outcome = .skipped
	#else
		static let negativeOverflowOutcome: Outcome = .unparseable
	#endif

	@Test(arguments: table)
	func parse(_ literal: String, _ outcome: Outcome) {
		let rules = AudienceMatcher.parseRules("{\"rules\":[{\"type\":\"assign\",\"variant\":\(literal)}]}")
		let actual: Outcome
		switch rules.map({ AudienceMatcher.evaluateRules($0, environmentName: nil, attributes: [:]) }) {
		case nil: actual = .unparseable
		case .some(nil): actual = .skipped
		case .some(.assign(let variant)?): actual = .selected(variant)
		case .some(.split?): Issue.record("unexpected split"); return
		}
		#expect(actual == outcome, "\(literal)")
	}

	// End to end on exp_test_abc (3 variants, hashed treatment 2). The first rule's variant is the
	// literal; the second rule assigns `next`. A selected in-range variant is served, a skipped rule
	// hands over to the second rule, and an out-of-bounds variant (or rules that do not parse) falls
	// back to the hashed treatment, 2.
	@Test(arguments: [
		("1.0", 0, 1), ("1e0", 0, 1), ("-0", 1, 0), ("-0.0", 1, 0), ("1.5", 1, 1), ("1e-9", 1, 1),
		("2147483648", 1, 2), ("4294967297", 1, 2), ("1e20", 1, 2), ("99999999999999999999", 1, 2),
		("9223372036854775807", 1, 2), ("1e400", 1, 2),
	])
	func treatment(_ literal: String, _ next: Int, _ expected: Int) {
		var data = Fixtures.contextData()
		let index = data.experiments.firstIndex { $0.name == "exp_test_abc" }!
		data.experiments[index].assignmentRules =
			"{\"rules\":[{\"type\":\"assign\",\"variant\":\(literal)},{\"type\":\"assign\",\"variant\":\(next)}]}"
		let context = Harness().context(data: data)
		#expect(context.treatment(for: "exp_test_abc") == expected, "\(literal)")
	}
}

// MARK: - Split percentages

@Suite struct SplitPercentagesParityTests {
	static let table: [(String, [Double]?)] = [
		// parseFloat reads the longest numeric prefix.
		("20abc/80", [0.2, 0.8]),
		("50/50abc/0", [0.5, 0.5, 0]),
		("abc/100", nil),
		("0x10/90", nil),
		("5./95", [0.05, 0.95]),
		(".5/99.5", [0.005, 0.995]),
		("50e0/50", [0.5, 0.5]),
		("1e2/0", [1, 0]),
		("+50/50", [0.5, 0.5]),
		("50 /50", [0.5, 0.5]),
		("-0/100", [-0.0, 1]),
		("100/1e-400", [1, 0]),
		("Infinity/0", nil),
		("1e400/0", nil),
		("50/50/", nil),
		("", nil),
		("100", [1]),
		// ECMAScript WhiteSpace and LineTerminator are skipped, including U+FEFF; U+0085, U+180E,
		// U+200B and U+001E are not.
		("\u{FEFF}20/80", [0.2, 0.8]),
		("20/\u{FEFF}80", [0.2, 0.8]),
		(" 50/50", [0.5, 0.5]),
		("\u{00A0}50/\u{205F}50", [0.5, 0.5]),
		("\u{2028}50/50", [0.5, 0.5]),
		("\u{3000}50/50", [0.5, 0.5]),
		("\u{0085}20/80", nil),
		("\u{180E}50/50", nil),
		("\u{200B}50/50", nil),
		("\u{001E}50/50", nil),
		// The total must be within 0.01 of 100 after toFixed(2) rounding.
		("100.014/0/0", [1.00014, 0, 0]),
		("100.0149999/0", [1.000149999, 0]),
		("100.015/0/0", nil),
		("50/50.014", [0.5, 0.50014]),
		("50/50.015", nil),
		("99.985/0", nil),
		("33.33/33.33/33.34", [0.3333, 0.3333, 33.34 / 100]),
	]

	@Test(arguments: table)
	func parse(_ percentages: String, _ expected: [Double]?) {
		let escaped = percentages.unicodeScalars.map { $0.isASCII && $0.value >= 0x20 ? String($0) : "\\u{\(String($0.value, radix: 16))}" }.joined()
		#expect(AudienceMatcher.parseSplitPercentages(.string(percentages)) == expected, "\(escaped)")
	}
}

// MARK: - Semver

@Suite struct SemverParityTests {
	@Test func vectors() {
		let evaluator = ExprEvaluator(vars: [:])
		let cases: [(JSONValue, JSONValue, Int?)] = [
			(.double(1e-7), "0.0000001", 0),
			(.double(1e-7), "0", 1),
			(.double(1e21), "1e+21", 0),
			(.double(1e20), "100000000000000000000", 0),
			(.double(-0.0), "0", 0),
			(.double(1.5), "1.5.0", 0),
			// U+0661 (Arabic-Indic one) is not an ASCII digit, so the identifier is alphanumeric and
			// compares by code unit: U+0661 > "a".
			("1.0.0-\u{0661}", "1.0.0-a", 1),
			// UTF-16 order, not scalar order: U+FF41 and U+E000 sort above the surrogate pair of U+1F600.
			("1.0.0-\u{FF41}", "1.0.0-\u{1F600}", 1),
			("1.0.0-\u{E000}", "1.0.0-\u{1F600}", 1),
		]
		for (lhs, rhs, expected) in cases {
			#expect(SemverComparator.compare(evaluator, lhs, rhs) == expected, "\(lhs) vs \(rhs)")
		}
		#expect(SemverComparator.jsNumberString(-0.0) == "0")
	}

	@Test func parsedNumberLiterals() throws {
		// Through parsed audience JSON, as the backend sends it.
		for (literal, version) in [("1e-7", "0.0000001"), ("1e21", "1e+21"), ("-0", "0"), ("-0.0", "0")] {
			let filter = try JSONValue(parsing: "{\"semver_eq\":[{\"value\":\(literal)},{\"value\":\"\(version)\"}]}")
			#expect(JsonExpr.evaluateBoolean(filter, vars: [:]), "\(literal)")
		}
	}
}

// MARK: - Parsed number literals

@Suite struct NumberLiteralParityTests {
	// What 1.5.0's evaluator did with each literal from parsed JSON: its string form, whether it
	// matches "^-", whether "x-0x" contains it, whether it is > 0, and semver_eq against "0".
	static let table: [(literal: String, string: String, negativeMatch: Bool, inString: Bool, gtZero: Bool, semverZero: Bool?)] = [
		("-0", "0", false, true, false, true),
		("-0.0", "-0", true, true, false, true),
		("-0e0", "-0", true, true, false, true),
		("-0.0e5", "-0", true, true, false, true),
		("0.0", "0", false, true, false, true),
		("-1e-400", "-0", true, true, false, true),
		("1e-400", "0", false, true, false, true),
		("-5e-324", "-0", true, true, false, nil),
		("4.9e-324", "0", false, true, true, true),
		("1.0", "1", false, false, true, false),
		("1e2", "100", false, false, true, false),
		("1E+3", "1000", false, false, true, false),
		("100.000", "100", false, false, true, false),
		("1.5", "1.5", false, false, true, false),
		("0.1", "0.1", false, false, true, false),
		("1e-7", "0.0000001", false, false, true, false),
		("2.5e-5", "0.000025", false, false, true, false),
		("1e18", "1000000000000000000", false, false, true, false),
		("1e19", "10000000000000000000", false, false, true, false),
		("123456789012345678", "123456789012345678", false, false, true, false),
		("9007199254740993", largeIntegerText, false, false, true, false),
		("9223372036854775807", "9223372036854775807", false, false, true, false),
	] + linuxOnlyRows

	#if canImport(Darwin)
		// Measured in the macOS CI lanes: Apple NumberFormatter rounds this NSNumber through Double.
		static let largeIntegerText = "9007199254740992"
	#else
		static let largeIntegerText = "9007199254740993"
	#endif

	// Int64.min and below: measured with 1.5.0 on Linux only, where JSONSerialization returns a
	// decimal for them. Apple Foundation may return an integer instead (not measured). 2.0 uses the
	// same parser as 1.5.0, so on each platform it matches 1.5.0 on that platform.
	#if os(Linux)
		static let linuxOnlyRows: [(literal: String, string: String, negativeMatch: Bool, inString: Bool, gtZero: Bool, semverZero: Bool?)] = [
			("-9223372036854775808", "-9223372036854776000", true, false, false, nil),
			("-9223372036854775809", "-9223372036854776000", true, false, false, nil),
		]
	#else
		static let linuxOnlyRows: [(literal: String, string: String, negativeMatch: Bool, inString: Bool, gtZero: Bool, semverZero: Bool?)] = []
	#endif

	@Test(arguments: table)
	func literal(
		_ row: (literal: String, string: String, negativeMatch: Bool, inString: Bool, gtZero: Bool, semverZero: Bool?)
	) throws {
		let value = try #require(try JSONValue(parsing: "[\(row.literal)]")[0])
		let evaluator = ExprEvaluator(vars: [:])
		func eval(_ text: String) throws -> JSONValue {
			JsonExpr.evaluate(try JSONValue(parsing: text), vars: [:])
		}
		let l = row.literal
		#expect(evaluator.stringConvert(value) == row.string, "\(l)")
		#expect(try eval("{\"match\":[{\"value\":\(l)},{\"value\":\"^-\"}]}") == .bool(row.negativeMatch), "\(l)")
		#expect(try eval("{\"in\":[{\"value\":\"x-0x\"},{\"value\":\(l)}]}") == .bool(row.inString), "\(l)")
		#expect(try eval("{\"gt\":[{\"value\":\(l)},{\"value\":0}]}") == .bool(row.gtZero), "\(l)")
		#expect(try eval("{\"semver_eq\":[{\"value\":\(l)},{\"value\":\"0\"}]}") == row.semverZero.map(JSONValue.bool) ?? .null, "\(l)")
	}

	@Test func negativeZeroKeepsItsSignOnlyWithAFractionOrExponent() throws {
		#expect(try JSONValue(parsing: "-0") == .int(0))
		guard case .double(let d) = try JSONValue(parsing: "-0.0") else {
			Issue.record("-0.0 is not a double")
			return
		}
		#expect(d == 0 && d.sign == .minus)
	}

	@Test func audienceMatchOnNegativeZero() {
		let audience = AudienceMatcher.parseAudience("{\"filter\":[{\"match\":[{\"value\":-0.0},{\"value\":\"^-\"}]}]}")
		#expect(AudienceMatcher.evaluate(audience, [:]) == true)
	}
}
