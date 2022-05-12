import Foundation

class OrCombinator: BooleanCombinator {
	override func combine(_ evaluator: Evaluator, _ args: JSON) -> JSON {
		for (_, arg): (String, JSON) in args {
			if evaluator.booleanConvert(evaluator.evaluate(arg)).boolValue {
				return JSON(true)
			}
		}
		return JSON(args.isEmpty)
	}
}
