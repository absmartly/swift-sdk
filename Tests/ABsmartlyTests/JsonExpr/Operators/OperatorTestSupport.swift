@testable import ABsmartly

// 1.x's OperatorTest base class gave each operator a mock evaluator whose `evaluate` returned its
// argument unchanged, so operands were plain values. In 2.0 operands are expressions, so each is
// wrapped in `{"value": x}` to evaluate to itself.

/// `{op: {"value": arg}}`, a unary operator applied to a literal.
func unary(_ op: String, _ arg: JSONValue) -> JSONValue {
	[op: ["value": arg]]
}

/// `{op: [{"value": a}, {"value": b}, ...]}`, an operator applied to literals.
func apply(_ op: String, _ args: [JSONValue]) -> JSONValue {
	[op: .array(args.map { ["value": $0] })]
}

/// Evaluates an expression with no variables.
func eval(_ expr: JSONValue, vars: [String: JSONValue] = [:]) -> JSONValue {
	JsonExpr.evaluate(expr, vars: vars)
}

/// `JSON.boolValue` in 1.x: true only for a boolean true.
extension JSONValue {
	var isTrue: Bool { self == .bool(true) }
}
