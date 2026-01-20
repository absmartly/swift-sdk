import Foundation

final class MatchOperator: BinaryOperator {
	private static let maxPatternLength = 1000
	private static let maxInputLength = 10000

	override func binary(_ evaluator: Evaluator, _ lhs: JSON, _ rhs: JSON) -> JSON {
		let text = evaluator.stringConvert(lhs)
		if text.type != .null {
			let pattern = evaluator.stringConvert(rhs)
			if pattern.type != .null {
				let regex = pattern.stringValue
				if regex.isEmpty {
					return JSON(true)
				}

				guard regex.count <= Self.maxPatternLength else {
					return JSON.null
				}

				let string = text.stringValue
				guard string.count <= Self.maxInputLength else {
					return JSON.null
				}

				if let matcher = try? NSRegularExpression(pattern: regex) {
					let range = NSRange(string.startIndex..., in: string)
					if matcher.firstMatch(in: string, range: range) != nil {
						return JSON(true)
					}
					return JSON(false)
				}
			}
		}
		return JSON.null
	}
}
