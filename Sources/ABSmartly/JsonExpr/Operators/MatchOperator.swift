import Foundation

final class MatchOperator: BinaryOperator {
	// Matching gives up after this long, e.g. on exponential backtracking from `^(a|aa)+$`.
	private static let matchTimeout: TimeInterval = 0.1

	override func binary(_ evaluator: Evaluator, _ lhs: JSON, _ rhs: JSON) -> JSON {
		let text = evaluator.stringConvert(lhs)
		if text.type != .null {
			let pattern = evaluator.stringConvert(rhs)
			if pattern.type != .null {
				let regex = pattern.stringValue
				if regex.isEmpty {
					return JSON(true)
				}

				let string = text.stringValue

				do {
					let matcher = try NSRegularExpression(pattern: regex, options: [])
					return Self.firstMatch(matcher, in: string, pattern: regex)
				} catch {
					Logger.error("Failed to compile regex pattern '\(regex)': \(error.safeLocalizedDescription)")
					return JSON.null
				}
			}
		}
		return JSON.null
	}

	/// Like `firstMatch(in:range:)`, but returns null once matching runs past `matchTimeout`.
	/// `.reportProgress` makes the regex engine call back periodically while it backtracks.
	private static func firstMatch(_ matcher: NSRegularExpression, in string: String, pattern: String) -> JSON {
		let deadline = ProcessInfo.processInfo.systemUptime + matchTimeout
		var matched = false
		var timedOut = false
		let range = NSRange(string.startIndex..., in: string)
		matcher.enumerateMatches(in: string, options: [.reportProgress], range: range) { result, _, stop in
			if result != nil {
				matched = true
				stop.pointee = true
			} else if ProcessInfo.processInfo.systemUptime > deadline {
				timedOut = true
				stop.pointee = true
			}
		}
		if timedOut {
			Logger.error("Regex pattern '\(pattern)' timed out after \(matchTimeout)s")
			return JSON.null
		}
		return JSON(matched)
	}
}
