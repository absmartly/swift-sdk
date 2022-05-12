import Foundation

final class NullOperator: UnaryOperator {
	override func unary(_ evaluator: Evaluator, _ arg: JSON) -> JSON {
		return JSON(arg.type == .null)
	}
}
