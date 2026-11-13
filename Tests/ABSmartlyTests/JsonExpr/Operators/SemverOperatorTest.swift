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
