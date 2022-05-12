final class NotOperator: UnaryOperator {
	override func unary(_ evaluator: Evaluator, _ arg: JSON) -> JSON {
		if let result = evaluator.booleanConvert(arg).bool {
			return JSON(!result)
		}
		return JSON(true)
	}
}
