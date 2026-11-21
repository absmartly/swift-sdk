import Foundation

enum MatchOperator {
	private static let maxPatternLength = 1000
	private static let maxInputLength = 10000
	// Matching gives up after this long, e.g. on exponential backtracking from `^(a|aa)+$`.
	private static let matchTimeout: TimeInterval = 0.1

	static func match(_ evaluator: ExprEvaluator, _ lhs: ExprValue, _ rhs: ExprValue) -> ExprValue {
		guard let text = evaluator.stringConvert(lhs), let pattern = evaluator.stringConvert(rhs) else {
			return .null
		}
		if pattern.isEmpty {
			return .bool(true)
		}
		guard pattern.count <= maxPatternLength else {
			Log.error("Regex pattern exceeds maximum length of \(maxPatternLength): '\(pattern.prefix(50))...'")
			return .null
		}
		guard text.count <= maxInputLength else {
			Log.error("Input string exceeds maximum length of \(maxInputLength)")
			return .null
		}
		if hasNestedQuantifiers(pattern) {
			Log.error("Regex pattern contains potentially catastrophic nested quantifiers: '\(pattern)'")
			return .null
		}

		let regex: NSRegularExpression
		do {
			regex = try NSRegularExpression(pattern: pattern, options: [])
		} catch {
			Log.error("Failed to compile regex pattern '\(pattern)': \(error.safeDescription)")
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
			Log.error("Regex pattern '\(pattern)' timed out after \(matchTimeout)s")
			return .null
		}
		return .bool(matched)
	}

	/// True when a group that itself contains an unbounded quantifier (`+`, `*`, `{n,}`) is repeated
	/// again without bound, e.g. `(a+)+` or `(a*){2,}`. Quantifiers on separate sequential parts, like
	/// `^([A-Z]+)-[0-9]+$`, are safe and not flagged.
	static func hasNestedQuantifiers(_ pattern: String) -> Bool {
		let chars = Array(pattern)
		var groupHasQuantifier: [Bool] = []
		var i = 0
		var inClass = false

		func isRepeatingQuantifier(at index: Int) -> Bool {
			guard index < chars.count else { return false }
			switch chars[index] {
			case "+", "*":
				return true
			case "{":
				var j = index + 1
				var body = ""
				while j < chars.count, chars[j] != "}" {
					body.append(chars[j])
					j += 1
				}
				guard j < chars.count else { return false }
				// Only an open upper bound (`{n,}`) repeats without limit.
				return body.hasSuffix(",")
			default:
				return false
			}
		}

		while i < chars.count {
			let c = chars[i]
			if c == "\\" {
				i += 2
				continue
			}
			if inClass {
				if c == "]" { inClass = false }
				i += 1
				continue
			}
			switch c {
			case "[":
				inClass = true
			case "(":
				groupHasQuantifier.append(false)
			case ")":
				if let inner = groupHasQuantifier.popLast() {
					if inner && isRepeatingQuantifier(at: i + 1) {
						return true
					}
					if inner || isRepeatingQuantifier(at: i + 1), !groupHasQuantifier.isEmpty {
						groupHasQuantifier[groupHasQuantifier.count - 1] = true
					}
				}
			default:
				if isRepeatingQuantifier(at: i), !groupHasQuantifier.isEmpty {
					groupHasQuantifier[groupHasQuantifier.count - 1] = true
				}
			}
			i += 1
		}
		return false
	}
}
