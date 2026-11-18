import Foundation
import Testing
@testable import ABsmartly

@Suite struct NestedIntegerEqualityTests {
    @Test func distinctLargeIntegersRemainUnequal() throws {
        let low: JSONValue = .int(9_007_199_254_740_992)
        let high: JSONValue = .int(9_007_199_254_740_993)
        let pairs: [(JSONValue, JSONValue)] = [(JSONValue.array([high]), .array([low])),
                           (.object(["id": high]), .object(["id": low]))]
        for (lhs, rhs) in pairs {
            #expect(!ExprEvaluator.deepEquals(lhs, rhs))
            let expression: JSONValue = ["eq": [["var": "ids"], ["value": rhs]]]
            #expect(!JsonExpr.evaluateBoolean(expression, vars: ["ids": lhs]))
        }
        #expect(ExprEvaluator.deepEquals(.array([high]), .array([high])))
    }

    @Test func numericLeavesMatchFoundationCollections() {
        let values: [(JSONValue, NSNumber)] = [
            (.bool(true), NSNumber(value: true)), (.bool(false), NSNumber(value: false)),
            (.int(1), NSNumber(value: Int64(1))), (.double(1), NSNumber(value: 1.0)),
            (.int(9_007_199_254_740_993), NSNumber(value: Int64(9_007_199_254_740_993))),
            (.double(9_007_199_254_740_992), NSNumber(value: 9_007_199_254_740_992.0)),
            (.int(Int64.max), NSNumber(value: Int64.max))
        ]
        for (l, ln) in values {
            for (r, rn) in values {
                let expected = NSArray(object: ln).isEqual(to: [rn])
                #expect(ExprEvaluator.deepEquals(.array([l]), .array([r])) == expected)
                #expect(ExprEvaluator.deepEquals(.object(["n": l]), .object(["n": r])) == expected)
            }
        }
    }
}
