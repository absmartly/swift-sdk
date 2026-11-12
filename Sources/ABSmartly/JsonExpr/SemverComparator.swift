import Foundation

// Semantic version ordering for the semver_* operators, matching the JavaScript SDK: a leading
// "v"/"V" and build metadata are ignored, missing core parts count as 0, numeric identifiers compare
// numerically (leading zeros ignored) and rank below alphanumeric ones, and a release ranks above
// its pre-releases. Parsing is as permissive as the JavaScript SDK's, so a non-numeric core part
// ("1.x") is compared as an alphanumeric identifier rather than rejected.
enum SemverComparator {
	// -1, 0 or 1, or nil when either side does not convert to a string or has an empty version core
	// (for example "", "v", "+build" or "-beta").
	static func compare(_ evaluator: Evaluator, _ lhs: JSON, _ rhs: JSON) -> Int? {
		guard let l = evaluator.stringConvert(lhs).string, let r = evaluator.stringConvert(rhs).string else {
			return nil
		}
		return compare(l, r)
	}

	static func compare(_ lhs: String, _ rhs: String) -> Int? {
		guard let l = parse(lhs), let r = parse(rhs) else {
			return nil
		}

		for i in 0..<max(l.parts.count, r.parts.count) {
			let result = compareIdentifiers(
				i < l.parts.count ? l.parts[i] : "0", i < r.parts.count ? r.parts[i] : "0")
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

	private static func parse(_ version: String) -> (parts: [String], preRelease: String)? {
		var v = Substring(version)
		if v.hasPrefix("v") || v.hasPrefix("V") {
			v = v.dropFirst()
		}
		if let plus = v.firstIndex(of: "+") {
			v = v[..<plus]
		}
		if v.isEmpty {
			return nil
		}

		let core: Substring
		let preRelease: Substring
		if let dash = v.firstIndex(of: "-") {
			core = v[..<dash]
			preRelease = v[v.index(after: dash)...]
		} else {
			core = v
			preRelease = ""
		}
		if core.isEmpty {
			return nil
		}
		return (split(String(core)), String(preRelease))
	}

	// Keeps empty components, so "1..0" has three parts.
	private static func split(_ s: String) -> [String] {
		return s.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
	}

	private static func isNumeric(_ s: String) -> Bool {
		return !s.isEmpty && s.utf8.allSatisfy { $0 >= 0x30 && $0 <= 0x39 }
	}

	private static func stripLeadingZeros(_ s: String) -> String {
		let stripped = s.drop(while: { $0 == "0" })
		return stripped.isEmpty ? "0" : String(stripped)
	}

	// UTF-16 code unit order, like JavaScript string comparison.
	private static func compareCodeUnits(_ a: String, _ b: String) -> Int {
		if a == b { return 0 }
		return a.utf16.lexicographicallyPrecedes(b.utf16) ? -1 : 1
	}

	private static func compareIdentifiers(_ a: String, _ b: String) -> Int {
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
