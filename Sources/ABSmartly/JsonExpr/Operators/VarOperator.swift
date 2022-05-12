final class VarOperator: Operator {
	func evaluate(_ evaluator: Evaluator, _ arg: JSON) -> JSON {
		let path = arg.type == .dictionary ? JSON(arg["path"]) : arg
		if let path = path.string {
			return evaluator.extractVar(path)
		}
		return JSON.null
	}

}
