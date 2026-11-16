import Foundation
import XCTest

@testable import ABSmartly

final class SemverOperatorTest: XCTestCase {
	let evaluator = ExprEvaluator(operators: JsonExpr.operators, vars: [:])

	// Vectors from the JavaScript SDK's versionCompare() tests.
	func testCompare() {
		let cases: [(JSON, JSON, Int?)] = [
			("1.0.0", "1.0.0", 0),
			("0.0.0", "0.0.0", 0),
			("999.999.999", "999.999.999", 0),
			("2.0.0", "1.0.0", 1),
			("1.0.0", "2.0.0", -1),
			("1.2.0", "1.1.0", 1),
			("1.1.0", "1.2.0", -1),
			("1.0.2", "1.0.1", 1),
			("1.0.1", "1.0.2", -1),
			("1.10.0", "1.9.0", 1),
			("1.9.0", "1.10.0", -1),
			("10.0.0", "9.0.0", 1),
			("1.2", "1.2.0", 0),
			("1", "1.0.0", 0),
			("1.2.0", "1.2", 0),
			("1.0.0", "1", 0),
			("1.02.0", "1.2.0", 0),
			("1.002.030", "1.2.30", 0),
			("01.0.0", "1.0.0", 0),
			("1.02.0", "1.3.0", -1),
			("1.0.0", "1.0.0-alpha", 1),
			("1.0.0-alpha", "1.0.0", -1),
			("1.0.0-alpha", "1.0.0-alpha", 0),
			("1.0.0-alpha", "1.0.0-beta", -1),
			("1.0.0-beta", "1.0.0-alpha", 1),
			("1.0.0-alpha.1", "1.0.0-alpha.2", -1),
			("1.0.0-alpha.2", "1.0.0-alpha.1", 1),
			("1.0.0-1", "1.0.0-2", -1),
			("1.0.0-2", "1.0.0-1", 1),
			("1.0.0-1", "1.0.0-alpha", -1),
			("1.0.0-alpha", "1.0.0-1", 1),
			("1.0.0-alpha", "1.0.0-alpha.1", -1),
			("1.0.0-alpha.1", "1.0.0-alpha", 1),
			("v1.0.0", "1.0.0", 0),
			("V1.0.0", "1.0.0", 0),
			("v1.0.0", "V1.0.0", 0),
			(JSON.null, "1.0.0", nil),
			("1.0.0", JSON.null, nil),
			(JSON.null, JSON.null, nil),
			(1, "1.0.0", 0),
			("1.0.0", 1, 0),
			(true, "true", 0),
			(JSON([String: Any]()), "1.0.0", nil),
			("1.0.0", JSON([String: Any]()), nil),
			(JSON([Any]()), "1.0.0", nil),
			("1.0.0+build1", "1.0.0+build2", 0),
			("1.0.0+build1", "1.0.0", 0),
			("1.0.0-alpha+build1", "1.0.0-alpha+build2", 0),
			("1.0.0-alpha+build1", "1.0.0-beta", -1),
			("1.0.0-alpha+build1", "1.0.0", -1),
			("", "1.0.0", nil),
			("1.0.0", "", nil),
			("", "", nil),
			("v", "1.0.0", nil),
			("V", "1.0.0", nil),
			("+build", "1.0.0", nil),
			("v+build", "1.0.0", nil),
			("1.0.0", "v", nil),
		]
		for (lhs, rhs, expected) in cases {
			XCTAssertEqual(expected, SemverComparator.compare(evaluator, lhs, rhs), "\(lhs) vs \(rhs)")
		}
	}

	func testEmptyPreReleaseIsARelease() {
		XCTAssertEqual(0, SemverComparator.compare("1.0.0-", "1.0.0"))
		XCTAssertNil(SemverComparator.compare("-beta", "1.0.0"))
		// An empty core part is alphanumeric, so it ranks above any number.
		XCTAssertEqual(1, SemverComparator.compare("1..0", "1.0.0"))
	}

	// Strings compare by UTF-16 code unit identity and order, like JavaScript's === and <, not by
	// Swift's canonical equivalence: a precomposed "é" (U+00E9) sorts after "e" + U+0301.
	func testComparesUtf16CodeUnitsNotCanonicalEquivalence() {
		let composed = "1.0.0-\u{00E9}"
		let decomposed = "1.0.0-e\u{0301}"
		XCTAssertEqual(1, SemverComparator.compare(composed, decomposed))
		XCTAssertEqual(-1, SemverComparator.compare(decomposed, composed))
		XCTAssertEqual(0, SemverComparator.compare(composed, composed))
		XCTAssertEqual(0, SemverComparator.compare(decomposed, decomposed))
		XCTAssertEqual(1, SemverComparator.compare("1.\u{00E9}", "1.e\u{0301}"))

		// A separator followed by a combining mark still separates, as JavaScript splits on code units.
		XCTAssertEqual(-1, SemverComparator.compare("1.0.0-\u{0301}", "1.0.0"))
		XCTAssertEqual(0, SemverComparator.compare("1.0.0+\u{0301}", "1.0.0"))
		XCTAssertEqual(0, SemverComparator.compare("v\u{0301}1", "\u{0301}1"))
		XCTAssertEqual(1, SemverComparator.compare("1.\u{0301}", "1.0"))
		XCTAssertEqual(-1, SemverComparator.compare("2.\u{0301}", "10"))

		let jsonExpr = JsonExpr()
		let vars: [String: JSON] = ["app_version": JSON(composed)]
		XCTAssertFalse(
			jsonExpr.evaluateBooleanExpr(["semver_eq": [["var": "app_version"], ["value": decomposed]]], vars: vars))
		XCTAssertTrue(
			jsonExpr.evaluateBooleanExpr(["semver_gt": [["var": "app_version"], ["value": decomposed]]], vars: vars))
	}

	// A number is converted like JavaScript's x.toFixed(15) with trailing zeros stripped: the exact
	// binary value rounded half up, plain digits below 1e21 and the shortest exponential form above.
	func testNumberConversionMatchesJavaScript() {
		let cases: [(Double, String)] = [
			(1.2, "1.2"),
			(1, "1"),
			(0, "0"),
			(-0.0, "0"),
			(-1.5, "-1.5"),
			(0.1 + 0.2, "0.3"),
			(123.456, "123.456000000000003"),
			(0.000001, "0.000001"),
			(5e-16, "0.000000000000001"),
			(1e-20, "0"),
			(-1e-20, "-0"),
			(1.0000000000000002, "1"),
			(pow(2, -16), "0.000015258789063"),
			(-pow(2, -16), "-0.000015258789063"),
			(3 * pow(2, -16), "0.000045776367188"),
			(9_007_199_254_740_994, "9007199254740994"),
			(1.2345678901234568e20, "123456789012345683968"),
			(1e21, "1e+21"),
			(1.2345e22, "1.2345e+22"),
			// JavaScript's trailing-zero strip also eats the exponent's zeros.
			(1e100, "1e+1"),
			(.leastNonzeroMagnitude, "0"),
			(.greatestFiniteMagnitude, "1.7976931348623157e+308"),
			(.infinity, "Infinity"),
			(-.infinity, "-Infinity"),
		]
		for (value, expected) in cases {
			XCTAssertEqual(expected, SemverComparator.jsNumberString(value), "\(value)")
		}

		XCTAssertEqual(0, SemverComparator.compare(evaluator, JSON(123.456), "123.456000000000003"))
		XCTAssertEqual(0, SemverComparator.compare(evaluator, JSON(1.2), "1.2"))
		XCTAssertEqual(0, SemverComparator.compare(evaluator, JSON(1e21), "1e+21"))
	}

	// The conversion does not depend on the locale, unlike the evaluator's number formatter, which
	// gives Eastern Arabic digits under ar_EG.
	func testNumberConversionIsLocaleIndependent() {
		for identifier in ["ar_EG", "fa_IR", "de_DE"] {
			let localised = ExprEvaluator(operators: JsonExpr.operators, vars: [:])
			localised.formatter.locale = Locale(identifier: identifier)
			XCTAssertEqual(0, SemverComparator.compare(localised, JSON(1.2), "1.2"), identifier)
			XCTAssertEqual(1, SemverComparator.compare(localised, JSON(1.25), "1.2.9"), identifier)
		}
	}

	func testOperators() {
		let jsonExpr = JsonExpr()
		let vars: [String: JSON] = ["app_version": "1.4.2"]
		func eval(_ op: String, _ version: String) -> Bool {
			return jsonExpr.evaluateBooleanExpr([op: [["var": "app_version"], ["value": version]]], vars: vars)
		}

		XCTAssertTrue(eval("semver_eq", "v1.4.2"))
		XCTAssertFalse(eval("semver_eq", "1.4.3"))
		XCTAssertTrue(eval("semver_gt", "1.4.2-beta"))
		XCTAssertFalse(eval("semver_gt", "1.4.2"))
		XCTAssertTrue(eval("semver_gte", "1.4.2"))
		XCTAssertFalse(eval("semver_gte", "1.10"))
		XCTAssertTrue(eval("semver_lt", "1.10"))
		XCTAssertFalse(eval("semver_lt", "1.4.2"))
		XCTAssertTrue(eval("semver_lte", "1.4.2+build"))
		XCTAssertFalse(eval("semver_lte", "1.4.1"))

		// An unparseable side yields null, which is not a match for any operator.
		for op in ["semver_eq", "semver_gt", "semver_gte", "semver_lt", "semver_lte"] {
			XCTAssertFalse(eval(op, ""), op)
			XCTAssertEqual(JSON.null, jsonExpr.evaluateExpr([op: [["var": "missing"], ["value": "1.0.0"]]], vars: vars))
		}
	}
}
