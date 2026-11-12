import Foundation

public class AudienceMatcher {
	let jsonExpr = JsonExpr()

	public func evaluate(_ audience: String, _ attributes: [String: JSON]) -> Bool? {
		let json = JSON(parseJSON: audience)
		let filter = json["filter"]

		// No filter (e.g. "null" or "{}") means the experiment has no audience.
		guard filter.exists() else {
			return nil
		}

		switch filter.type {
		case .dictionary, .array:
			return jsonExpr.evaluateBooleanExpr(filter, vars: attributes)
		default:
			let truncated = audience.count > 100 ? "\(audience.prefix(100))..." : audience
			Logger.error("Audience filter has invalid type: \(filter.type), expected dictionary or array. Audience: '\(truncated)'")
			return nil
		}
	}
}

// The action of the first matching assignment rule: a fixed variant, or a split (fractions summing
// to 1, one per variant) to hash the unit over.
enum RuleAction: Equatable {
	case assign(variant: Int)
	case split([Double])
}

extension AudienceMatcher {
	/// Parses an assignment rules JSON string (`{"rules": [...]}`). Returns nil when it is not valid
	/// JSON or has no `rules` array.
	func parseRules(_ assignmentRules: String) -> [JSON]? {
		return JSON(parseJSON: assignmentRules)["rules"].array
	}

	/// The action of the first rule that matches, in order. A rule is skipped when it is not an
	/// object, its type is unknown, an `assign` variant is not an integer, a `split` has invalid
	/// percentages, its `environments` is not an array or is a non-empty array without
	/// `environmentName`, or its `conditions` are not an object or do not evaluate to true. A rule
	/// without conditions always matches. Variant bounds are the caller's responsibility.
	func evaluateRules(
		_ rules: [JSON], environmentName: String?, attributes: [String: JSON]
	) -> RuleAction? {
		for rule in rules {
			guard rule.type == .dictionary, let action = AudienceMatcher.parseRuleAction(rule) else {
				continue
			}

			let environments = rule["environments"]
			if environments.exists() && environments.type != .null {
				guard let envs = environments.array else { continue }
				if !envs.isEmpty {
					guard let environmentName = environmentName,
						envs.contains(where: { $0.string == environmentName })
					else { continue }
				}
			}

			let conditions = rule["conditions"]
			if !conditions.exists() || conditions.type == .null {
				return action
			}
			guard conditions.type == .dictionary else { continue }

			if jsonExpr.evaluateBooleanExpr(conditions, vars: attributes) {
				return action
			}
		}
		return nil
	}

	private static func parseRuleAction(_ rule: JSON) -> RuleAction? {
		switch rule["type"].string {
		case "assign":
			// Like JavaScript's Number.isInteger. An integral value outside Int's range is kept as
			// out of bounds rather than skipped, as it is in the JavaScript SDK.
			let variant = rule["variant"]
			guard variant.type == .number, let d = variant.double, d.isFinite, d.rounded() == d else { return nil }
			return .assign(variant: abs(d) < 9_007_199_254_740_992 ? Int(d) : -1)
		case "split":
			return parseSplitPercentages(rule["percentages"]).map { .split($0) }
		default:
			return nil
		}
	}

	// Same check the backend applies to an experiment's own split: the gap from 100, rounded to two
	// decimals like JavaScript's toFixed(2), must be at most 0.01. toFixed rounds the exact binary
	// value half up, so the rounded gap exceeds 0.01 exactly when the gap is at least 0.015 — that
	// is, greater than the double nearest 0.015, which lies just below it. An infinite gap fails too.
	static func parseSplitPercentages(_ percentages: JSON) -> [Double]? {
		guard let string = percentages.string else { return nil }

		var values: [Double] = []
		var total = 0.0
		for part in string.split(separator: "/", omittingEmptySubsequences: false) {
			let value = parseFloat(part)
			if value.isNaN || value < 0 {
				return nil
			}
			values.append(value)
			total += value
		}

		if abs(100 - total) > 0.015 {
			return nil
		}
		return values.map { $0 / 100 }
	}

	// JavaScript parseFloat: leading whitespace is skipped and the longest decimal prefix is parsed,
	// so "50abc" is 50 and "abc" is NaN.
	static func parseFloat<S: StringProtocol>(_ s: S) -> Double {
		let chars = Array(s.unicodeScalars)
		var i = 0
		while i < chars.count && chars[i].properties.isWhitespace {
			i += 1
		}

		let start = i
		if i < chars.count && (chars[i] == "+" || chars[i] == "-") {
			i += 1
		}
		let isDigit = { (c: Unicode.Scalar) in c >= "0" && c <= "9" }

		if String(String.UnicodeScalarView(chars[i...])).hasPrefix("Infinity") {
			return start < chars.count && chars[start] == "-" ? -.infinity : .infinity
		}

		var digits = false
		while i < chars.count && isDigit(chars[i]) {
			i += 1
			digits = true
		}
		if i < chars.count && chars[i] == "." {
			i += 1
			while i < chars.count && isDigit(chars[i]) {
				i += 1
				digits = true
			}
		}
		if !digits {
			return .nan
		}

		var end = i
		if i < chars.count && (chars[i] == "e" || chars[i] == "E") {
			var j = i + 1
			if j < chars.count && (chars[j] == "+" || chars[j] == "-") {
				j += 1
			}
			let expStart = j
			while j < chars.count && isDigit(chars[j]) {
				j += 1
			}
			if j > expStart {
				end = j
			}
		}

		var number = String(String.UnicodeScalarView(chars[start..<end]))
		// Swift's Double(_:) rejects a trailing "." ("5.") that JavaScript accepts.
		if number.hasSuffix(".") || number.contains(".e") || number.contains(".E") {
			number = number.replacingOccurrences(of: ".", with: ".0")
		}
		return Double(number) ?? .nan
	}
}
