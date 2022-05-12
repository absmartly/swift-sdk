import Foundation

final class MatchOperator: BinaryOperator {
	override func binary(_ evaluator: Evaluator, _ lhs: JSON, _ rhs: JSON) -> JSON {
		let text = evaluator.stringConvert(lhs)
		if text.type != .null {
			let pattern = evaluator.stringConvert(rhs)
			if pattern.type != .null {
				let regex = pattern.stringValue
				if regex.isEmpty {
					return JSON(true)
				}

				if let matcher = try? NSRegularExpression(pattern: regex) {
					let string = text.stringValue
					if let _ = matcher.firstMatch(in: string, range: NSRange(location: 0, length: string.count)) {
						return JSON(true)
					}
					return JSON(false)
				}
			}
		}
		return JSON.null
	}
}
