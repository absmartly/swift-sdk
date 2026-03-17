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
					Logger.error("Regex pattern exceeds maximum length of \(Self.maxPatternLength): '\(regex.prefix(50))...'")
					return JSON.null
				}

				let string = text.stringValue
				guard string.count <= Self.maxInputLength else {
					Logger.error("Input string exceeds maximum length of \(Self.maxInputLength)")
					return JSON.null
				}

				if hasNestedQuantifiers(regex) {
					Logger.error("Regex pattern contains potentially catastrophic nested quantifiers: '\(regex)'")
					return JSON.null
				}

				do {
					let matcher = try NSRegularExpression(pattern: regex, options: [])
					let range = NSRange(string.startIndex..., in: string)
					return JSON(matcher.firstMatch(in: string, range: range) != nil)
				} catch {
					Logger.error("Failed to compile regex pattern '\(regex)': \(error.localizedDescription)")
					return JSON.null
				}
			}
		}
		return JSON.null
	}

	private func hasNestedQuantifiers(_ pattern: String) -> Bool {
		let dangerousPatterns = [
			"\\(.*[+*].*\\).*[+*]",
			"\\(.*[+*].*\\).*\\{",
			"\\{.*\\}.*[+*]",
			"\\{.*\\}.*\\{"
		]

		for dangerous in dangerousPatterns {
			if let _ = try? NSRegularExpression(pattern: dangerous, options: [])
				.firstMatch(in: pattern, range: NSRange(pattern.startIndex..., in: pattern)) {
				return true
			}
		}
		return false
	}
}
