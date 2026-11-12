import Foundation

final class MatchOperator: BinaryOperator {
	private static let maxPatternLength = 1000
	private static let maxInputLength = 10000
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

	/// True when a group that itself contains an unbounded quantifier (`+`, `*`, `{n,}`)
	/// is repeated again without bound, e.g. `(a+)+` or `(a*){2,}`. Quantifiers on separate sequential
	/// parts, like `^([A-Z]+)-[0-9]+$`, are safe and not flagged.
	private func hasNestedQuantifiers(_ pattern: String) -> Bool {
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
				// Only an open upper bound (`{n,}`) repeats without limit; finite bounds
				// such as `{2}` or `{1,3}` cannot backtrack catastrophically.
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
