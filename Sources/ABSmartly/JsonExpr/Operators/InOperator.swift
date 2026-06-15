import Foundation

final class InOperator: BinaryOperator {
	override func binary(_ evaluator: Evaluator, _ haystack: JSON, _ needle: JSON) -> JSON {
		switch haystack.type {
		case .array:
			for (_, item): (String, JSON) in haystack {
				if evaluator.compare(item, needle) == 0 {
					return JSON(true)
				}
			}
			return JSON(false)
		case .string:
			let needleString = evaluator.stringConvert(needle)
			return JSON((needleString.type != .null) && haystack.stringValue.contains(needleString.stringValue))
		case .dictionary:
			let needleString = evaluator.stringConvert(needle)
			return JSON((needleString.type != .null) && haystack[needleString.stringValue].exists())
		default:
			break
		}
		return JSON.null
	}
}
