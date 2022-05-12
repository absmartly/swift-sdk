class UnaryOperator: Operator {
	func evaluate(_ evaluator: Evaluator, _ args: JSON) -> JSON {
		let arg = evaluator.evaluate(args)
		return unary(evaluator, arg)
	}

	func unary(_ evaluator: Evaluator, _ arg: JSON) -> JSON {
		return JSON.null
	}
}
