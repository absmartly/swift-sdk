class BooleanCombinator: Operator {
	func evaluate(_ evaluator: Evaluator, _ args: JSON) -> JSON {
		if args.type == .array {
			return combine(evaluator, args)
		}

		return JSON.null
	}

	func combine(_ evaluator: Evaluator, _ args: JSON) -> JSON {
		return JSON.null
	}
}
