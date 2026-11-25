import Foundation
import Testing

@testable import ABsmartly

@Suite struct NestedIntegerEqualityTests {
	@Test func distinctLargeIntegersRemainUnequal() throws {
		let low: ExprValue = .int(9_007_199_254_740_992)
		let high: ExprValue = .int(9_007_199_254_740_993)
		let pairs: [(ExprValue, ExprValue)] = [
			(ExprValue.array([high]), .array([low])),
			(.object(["id": high]), .object(["id": low])),
		]
		for (lhs, rhs) in pairs {
			#expect(!ExprEvaluator.deepEquals(lhs, rhs))
			let expression: ExprValue = ["eq": [["var": "ids"], ["value": rhs]]]
			#expect(!JsonExpr.evaluateBoolean(expression, vars: ["ids": lhs.jsonValue]))
		}
		#expect(ExprEvaluator.deepEquals(.array([high]), .array([high])))
	}

	// Expected values come from JSONSerialization-parsed arrays, which is what 1.5.0 compared.
	@Test func numericLeavesMatchFoundationCollections() throws {
		let literals = [
			"true", "false", "0", "1", "1.0", "9007199254740992", "9007199254740993", "9223372036854775807",
		]
		func parsed(_ literal: String) throws -> NSArray {
			try #require(try JSONSerialization.jsonObject(with: Data("[\(literal)]".utf8)) as? NSArray)
		}
		for l in literals {
			for r in literals {
				let expected = try parsed(l).isEqual(to: try parsed(r) as! [Any])
				let lhs = try ExprValue(parsing: "[\(l)]")
				let rhs = try ExprValue(parsing: "[\(r)]")
				#expect(ExprEvaluator.deepEquals(lhs, rhs) == expected, "\(l) vs \(r)")
				#expect(
					ExprEvaluator.deepEquals(.object(["n": lhs[0]!]), .object(["n": rhs[0]!])) == expected,
					"\(l) vs \(r)")
			}
		}
	}
}
