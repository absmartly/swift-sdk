import Foundation

enum MatchOperator {
	// Matching gives up after this long, e.g. on exponential backtracking from `^(a|aa)+$`.
	private static let matchTimeout: TimeInterval = 0.1

	static func match(_ evaluator: ExprEvaluator, _ lhs: ExprValue, _ rhs: ExprValue) -> ExprValue {
		guard let text = evaluator.stringConvert(lhs), let pattern = evaluator.stringConvert(rhs) else {
			return .null
		}
		if pattern.isEmpty {
			return .bool(true)
		}
		let regex: NSRegularExpression
		do {
			regex = try NSRegularExpression(pattern: pattern, options: [])
		} catch {
			Log.error("Failed to compile regex pattern.", detail: "'\(pattern)': \(error.safeDescription)")
			return .null
		}
		return firstMatch(regex, in: text, pattern: pattern)
	}

	/// Like `firstMatch(in:range:)`, but returns null once matching runs past `matchTimeout`.
	/// `.reportProgress` makes the regex engine call back periodically while it backtracks.
	private static func firstMatch(_ regex: NSRegularExpression, in string: String, pattern: String) -> ExprValue {
		let deadline = ProcessInfo.processInfo.systemUptime + matchTimeout
		var matched = false
		var timedOut = false
		let range = NSRange(string.startIndex..., in: string)
		regex.enumerateMatches(in: string, options: [.reportProgress], range: range) { result, _, stop in
			if result != nil {
				matched = true
				stop.pointee = true
			} else if ProcessInfo.processInfo.systemUptime > deadline {
				timedOut = true
				stop.pointee = true
			}
		}
		if timedOut {
			Log.error("Regex pattern timed out after \(matchTimeout)s.", detail: "'\(pattern)'")
			return .null
		}
		return .bool(matched)
	}
}
