final class EqualsOperator: BinaryOperator {
	override func evaluate(_ evaluator: Evaluator, _ args: JSON) -> JSON {
		if args.type == .array {
			let lhs = evaluator.evaluate(args[0])
			let rhs = evaluator.evaluate(args[1])
			return binary(evaluator, lhs, rhs)
		}
		return JSON.null
	}

	override func binary(_ evaluator: Evaluator, _ lhs: JSON, _ rhs: JSON) -> JSON {
		if let result = evaluator.compare(lhs, rhs) {
			return JSON(result == 0)
		}
		return JSON.null
	}
}
