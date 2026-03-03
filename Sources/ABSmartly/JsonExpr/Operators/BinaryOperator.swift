class BinaryOperator: Operator {
	func evaluate(_ evaluator: Evaluator, _ args: JSON) -> JSON {
		if args.type == .array, args.count >= 2 {
			let lhs = evaluator.evaluate(args[0])
			let rhs = evaluator.evaluate(args[1])
			return binary(evaluator, lhs, rhs)
		}

		return JSON.null
	}

	func binary(_ evaluator: Evaluator, _ lhs: JSON, _ rhs: JSON) -> JSON {
		return JSON.null
	}
}
