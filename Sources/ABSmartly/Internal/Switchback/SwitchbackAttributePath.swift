import Foundation

// A switchback cluster attribute path, resolved like the Collector's SwitchbackAttributePath (port of
// java-sdk internal/SwitchbackAttributePath.java): "/" separates segments, a segment wrapped in ' or "
// is a literal key, and an unquoted segment that Guava Ints.tryParse accepts (ASCII digits, optional
// leading '-') indexes an array and nothing else. Every other segment reads an object key. A path is
// malformed, and its experiment unservable, when a quote is left unterminated or the path contains a
// '.' anywhere, quoted or not (dotted paths are not a nesting syntax; nesting is written with '/').
struct SwitchbackAttributePath {
	private let keys: [String]
	// Parallel to keys; nil where the segment is an object key.
	private let indices: [Int?]

	// Nil for an unsupported path: malformed (see above), empty, or an array index that is negative,
	// first, last, or directly after another index. Analysis cannot read those.
	static func parseSupported(_ path: String?) -> SwitchbackAttributePath? {
		guard let path = path, let parsed = parse(path) else { return nil }
		let n = parsed.keys.count
		if n == 0 {
			return nil
		}
		for (i, index) in parsed.indices.enumerated() {
			if let index = index, index < 0 || i == 0 || i == n - 1 || parsed.indices[i - 1] != nil {
				return nil
			}
		}
		return parsed
	}

	// The attribute name the path starts at; a supported path always starts at a key segment.
	var rootKey: String {
		return keys[0]
	}

	// Resolves the whole path in `attributes`, the first segment naming an attribute.
	func resolve(_ attributes: [String: JSON]) -> JSON? {
		guard let root = attributes[keys[0]] else { return nil }
		return resolveAttribute(root)
	}

	// Resolves the path below rootKey in an attribute's value.
	func resolveAttribute(_ rootValue: JSON) -> JSON? {
		var current = rootValue
		for i in 1..<keys.count {
			guard let next = Self.step(current, keys[i], indices[i]) else { return nil }
			current = next
		}
		return current
	}

	private static func step(_ current: JSON, _ key: String, _ index: Int?) -> JSON? {
		if let index = index {
			guard current.type == .array, let array = current.array else { return nil }
			return index >= 0 && index < array.count ? array[index] : nil
		}
		guard current.type == .dictionary else { return nil }
		return current.dictionary?.first { SwitchbackServing.sameKey($0.key, key) }?.value
	}

	// Nil when the path is malformed. Scans Unicode scalars, so a quote followed by a combining mark is
	// still a quote.
	private static func parse(_ path: String) -> SwitchbackAttributePath? {
		let scalars = Array(path.unicodeScalars)
		if scalars.contains(".") {
			return nil
		}
		var keys: [String] = []
		var indices: [Int?] = []
		var i = 0
		while i < scalars.count {
			let first = scalars[i]
			if first == "/" {
				i += 1
				continue
			}
			if first == "'" || first == "\"" {
				guard let end = scalars[(i + 1)...].firstIndex(of: first) else { return nil }
				keys.append(string(scalars[(i + 1)..<end]))
				indices.append(nil)
				i = end + 1
			} else {
				let stop = scalars[i...].firstIndex(of: "/") ?? scalars.count
				let key = string(scalars[i..<stop])
				keys.append(key)
				indices.append(tryParseInt(key))
				i = stop
			}
		}
		return SwitchbackAttributePath(keys: keys, indices: indices)
	}

	private static func string(_ scalars: ArraySlice<Unicode.Scalar>) -> String {
		var view = String.UnicodeScalarView()
		view.append(contentsOf: scalars)
		return String(view)
	}

	// Guava Ints.tryParse(String): optional '-', then one or more ASCII digits, within Int32 range;
	// otherwise nil. "+1" and non-ASCII digits are not numbers; "-0" is 0.
	static func tryParseInt(_ s: String) -> Int? {
		let scalars = Array(s.unicodeScalars)
		let negative = scalars.first == "-"
		var i = negative ? 1 : 0
		if i == scalars.count {
			return nil
		}
		var magnitude: Int64 = 0
		while i < scalars.count {
			let c = scalars[i].value
			if c < 0x30 || c > 0x39 {
				return nil
			}
			magnitude = magnitude * 10 + Int64(c - 0x30)
			if magnitude > (Int64(1) << 31) {
				return nil
			}
			i += 1
		}
		let value = negative ? -magnitude : magnitude
		return value > Int64(Int32.max) ? nil : Int(value)
	}
}
