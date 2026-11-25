import Foundation

// Semantic version ordering for the semver_* operators, matching the JavaScript SDK: a leading
// "v"/"V" and build metadata are ignored, missing core parts count as 0, numeric identifiers compare
// numerically (leading zeros ignored) and rank below alphanumeric ones, and a release ranks above
// its pre-releases. Parsing is as permissive as the JavaScript SDK's, so a non-numeric core part
// ("1.x") is compared as an alphanumeric identifier rather than rejected.
//
// Versions are handled as UTF-16 code units, like JavaScript strings: identifiers are equal only
// when their code units are, and ordered by code unit, so canonically equivalent but differently
// encoded strings ("é" and "e" + U+0301) differ, and a separator followed by a combining mark still
// separates.
enum SemverComparator {
	private typealias Units = ArraySlice<UInt16>

	// -1, 0 or 1, or nil when either side does not convert to a string or has an empty version core
	// (for example "", "v", "+build" or "-beta").
	static func compare(_ evaluator: ExprEvaluator, _ lhs: ExprValue, _ rhs: ExprValue) -> Int? {
		guard let l = stringConvert(evaluator, lhs), let r = stringConvert(evaluator, rhs) else {
			return nil
		}
		return compare(l, r)
	}

	static func compare(_ lhs: String, _ rhs: String) -> Int? {
		guard let l = parse(Units(lhs.utf16)), let r = parse(Units(rhs.utf16)) else {
			return nil
		}

		for i in 0..<max(l.parts.count, r.parts.count) {
			let result = compareIdentifiers(
				i < l.parts.count ? l.parts[i] : zero, i < r.parts.count ? r.parts[i] : zero)
			if result != 0 {
				return result
			}
		}

		if l.preRelease.isEmpty && r.preRelease.isEmpty { return 0 }
		if l.preRelease.isEmpty { return 1 }
		if r.preRelease.isEmpty { return -1 }

		let lPre = split(l.preRelease)
		let rPre = split(r.preRelease)
		for i in 0..<max(lPre.count, rPre.count) {
			if i >= lPre.count { return -1 }
			if i >= rPre.count { return 1 }
			let result = compareIdentifiers(lPre[i], rPre[i])
			if result != 0 {
				return result
			}
		}
		return 0
	}

	// Numbers are converted locale-independently, like JavaScript's x.toFixed(15) with trailing
	// zeros stripped, rather than through the evaluator's NumberFormatter, which follows the locale.
	private static func stringConvert(_ evaluator: ExprEvaluator, _ x: ExprValue) -> String? {
		if let number = x.doubleValue {
			return jsNumberString(number)
		}
		return evaluator.stringConvert(x)
	}

	// JavaScript's x.toFixed(15).replace(/\.?0{0,15}$/, ""). Below 1e21 the exact binary value is
	// rounded half up to 15 decimals; from 1e21 the shortest round-trip exponential form is used.
	static func jsNumberString(_ x: Double) -> String {
		if x.isNaN { return "NaN" }

		var string: String
		if x.isInfinite {
			string = x < 0 ? "-Infinity" : "Infinity"
		} else if abs(x) >= 1e21 {
			// Swift's description is the shortest round-trip form, exponential at this magnitude
			// ("1e+21", "1.2345e+22"), as JavaScript's Number::toString.
			string = x.description
		} else {
			string = (x < 0 ? "-" : "") + fixed15(abs(x))
		}

		// The regex strips at most 15 trailing zeros, then a "." left at the end.
		var zeros = 0
		while zeros < 15, string.utf8.last == UInt8(ascii: "0") {
			string.removeLast()
			zeros += 1
		}
		if string.utf8.last == UInt8(ascii: ".") {
			string.removeLast()
		}
		return string
	}

	// Rounds a non-negative finite value below 1e21 to 15 decimals, half up on its exact binary value
	// as toFixed does (printf rounds ties to even). "%.1074f" prints the exact value, which never has
	// more fractional digits than that.
	private static func fixed15(_ x: Double) -> String {
		let exact = Array(String(format: "%.1074f", x).utf8)
		guard let dot = exact.firstIndex(of: UInt8(ascii: ".")) else { return String(format: "%.15f", x) }

		var digits = Array(exact[..<dot]) + Array(exact[(dot + 1)...(dot + 15)])
		if exact[dot + 16] >= UInt8(ascii: "5") {
			var i = digits.count - 1
			while i >= 0 && digits[i] == UInt8(ascii: "9") {
				digits[i] = UInt8(ascii: "0")
				i -= 1
			}
			if i >= 0 {
				digits[i] += 1
			} else {
				digits.insert(UInt8(ascii: "1"), at: 0)
			}
		}
		let integerCount = digits.count - 15
		return String(decoding: digits[..<integerCount], as: UTF8.self) + "."
			+ String(decoding: digits[integerCount...], as: UTF8.self)
	}

	private static let zero: Units = [0x30]

	private static func parse(_ version: Units) -> (parts: [Units], preRelease: Units)? {
		var v = version
		if let first = v.first, first == 0x76 || first == 0x56 {  // "v", "V"
			v = v.dropFirst()
		}
		if let plus = v.firstIndex(of: 0x2B) {  // "+"
			v = v[..<plus]
		}
		if v.isEmpty {
			return nil
		}

		let core: Units
		let preRelease: Units
		if let dash = v.firstIndex(of: 0x2D) {  // "-"
			core = v[..<dash]
			preRelease = v[(dash + 1)...]
		} else {
			core = v
			preRelease = []
		}
		if core.isEmpty {
			return nil
		}
		return (split(core), preRelease)
	}

	// Splits on "." keeping empty components, so "1..0" has three parts.
	private static func split(_ s: Units) -> [Units] {
		return s.split(separator: 0x2E, omittingEmptySubsequences: false)
	}

	// ASCII digits only, like JavaScript's /^\d+$/.
	private static func isNumeric(_ s: Units) -> Bool {
		return !s.isEmpty && s.allSatisfy { $0 >= 0x30 && $0 <= 0x39 }
	}

	private static func stripLeadingZeros(_ s: Units) -> Units {
		let stripped = s.drop(while: { $0 == 0x30 })
		return stripped.isEmpty ? zero : stripped
	}

	// Code unit identity and order, like JavaScript's === and <.
	private static func compareCodeUnits(_ a: Units, _ b: Units) -> Int {
		if a.elementsEqual(b) { return 0 }
		return a.lexicographicallyPrecedes(b) ? -1 : 1
	}

	private static func compareIdentifiers(_ a: Units, _ b: Units) -> Int {
		let aIsNum = isNumeric(a)
		let bIsNum = isNumeric(b)

		if aIsNum && bIsNum {
			let aNorm = stripLeadingZeros(a)
			let bNorm = stripLeadingZeros(b)
			if aNorm.count != bNorm.count {
				return aNorm.count > bNorm.count ? 1 : -1
			}
			return compareCodeUnits(aNorm, bNorm)
		}
		if aIsNum { return -1 }
		if bIsNum { return 1 }
		return compareCodeUnits(a, b)
	}
}
