import Foundation

final class JsonExpr {
	static let operators: [String: Operator] = [
		"and": AndCombinator(),
		"or": OrCombinator(),
		"value": ValueOperator(),
		"var": VarOperator(),
		"null": NullOperator(),
		"not": NotOperator(),
		"in": InOperator(),
		"match": MatchOperator(),
		"eq": EqualsOperator(),
		"gt": GreaterThanOperator(),
		"gte": GreaterThanOrEqualOperator(),
		"lt": LessThanOperator(),
		"lte": LessThanOrEqualOperator(),
	]

	public func evaluateBooleanExpr(_ expr: JSON, vars: [String: JSON]) -> Bool {
		let evaluator = ExprEvaluator(operators: JsonExpr.operators, vars: vars)
		return evaluator.booleanConvert(evaluator.evaluate(expr)).boolValue
	}

	public func evaluateExpr(_ expr: JSON, vars: [String: JSON]) -> JSON {
		let evaluator = ExprEvaluator(operators: JsonExpr.operators, vars: vars)
		return evaluator.evaluate(expr)
	}
}
