final class SemverGreaterThanOperator: BinaryOperator {
	override func binary(_ evaluator: Evaluator, _ lhs: JSON, _ rhs: JSON) -> JSON {
		if let result = SemverComparator.compare(evaluator, lhs, rhs) {
			return JSON(result > 0)
		}
		return JSON.null
	}
}
