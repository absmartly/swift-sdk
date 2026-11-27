import Foundation

/// One `switchbackClusters` entry: a linked unit type and the attribute path holding its cluster value.
public struct SwitchbackCluster: Codable, Equatable {
	public let unitType: String
	/// The attribute path; nil when the payload's value is not a string, which makes the cluster map
	/// unreadable.
	public let attributePath: String?

	public init(unitType: String, attributePath: String?) {
		self.unitType = unitType
		self.attributePath = attributePath
	}

	public static func == (lhs: SwitchbackCluster, rhs: SwitchbackCluster) -> Bool {
		return SwitchbackServing.sameKey(lhs.unitType, rhs.unitType)
			&& SwitchbackServing.sameKey(lhs.attributePath, rhs.attributePath)
	}

}

// Carries raw context bytes to `Experiment.init(from:)` through `JSONDecoder.userInfo`: cluster
// objects need their JSON key order, and only the new switchback fields need last-wins duplicate keys.
// Existing experiment fields stay on the caller's decoder path. The bytes are scanned once per payload.
final class SwitchbackClusterOrder {
	static let userInfoKey = CodingUserInfoKey(rawValue: "com.absmartly.switchbackClusterOrder")!

	private let json: Data
	private let lock = NSLock()
	private var scanned: [String: OrderedJSONScanner.Fields]?

	#if DEBUG
	// Payload scans since the last reset, for the one-scan-per-decode test.
	static var scanCount = 0
	#endif

	init(json: Data) {
		self.json = json
	}

	// Whether the bytes can hold a switchback field at all. A payload without one keeps the plain
	// decode path and is never scanned. An escaped key spelling is kept on the scanned path.
	static func mayHaveSwitchbackFields(_ json: Data) -> Bool {
		for needle in ["switchback", "randomizationType", "\\u"] {
			if json.range(of: Data(needle.utf8)) != nil {
				return true
			}
		}
		return false
	}

	// Nil when the bytes were not scanned there (not a top-level experiment or holdout, or unreadable).
	func fields(at codingPath: [CodingKey]) -> OrderedJSONScanner.Fields? {
		lock.lock()
		defer { lock.unlock() }
		if scanned == nil {
			#if DEBUG
			SwitchbackClusterOrder.scanCount += 1
			#endif
			scanned = OrderedJSONScanner.switchbackFields(Array(json))
		}
		return scanned?[Self.pathKey(codingPath)]
	}

	func clusters(at codingPath: [CodingKey]) -> OrderedJSONScanner.Clusters? {
		return fields(at: codingPath)?.clusters
	}

	static func pathKey(_ codingPath: [CodingKey]) -> String {
		return codingPath.map { $0.intValue.map { "#\($0)" } ?? $0.stringValue }.joined(separator: "/")
	}
}

// A minimal JSON reader for top-level `experiments` and `holdouts`: records ordered cluster entries
// and raw values of only the new switchback fields. Duplicate keys resolve as in java-sdk (a
// LinkedHashMap) and javascript-sdk (an object): a repeated field takes its last value, and a repeated
// unit type keeps its first position and takes its last value. Anything it cannot read gives no record,
// so the decoder fallback is retained. An unpaired surrogate escape reads as U+FFFD.
struct OrderedJSONScanner {
	struct Fields {
		var clusters: Clusters?
		var values: [String: Data] = [:]
	}

	private static let valueFields: Set<String> = [
		"randomizationType", "switchbackStartAt", "switchbackPeriodMs",
		"switchbackCarryoverDurationMs", "switchbackBurnInDurationMs", "switchbackBurnOutDurationMs",
		"switchbackDesignType", "switchbackEstimand", "switchbackClusterValues",
	]
	enum Clusters: Equatable {
		// Each unit type with its attribute path; nil for a path that is not a JSON string.
		case object([(unitType: String, path: String?)])
		case notAnObject
		case arrayRepresentation(Data)

		static func == (lhs: Clusters, rhs: Clusters) -> Bool {
			switch (lhs, rhs) {
			case (.notAnObject, .notAnObject): return true
			case (.arrayRepresentation(let a), .arrayRepresentation(let b)): return a == b
			case (.object(let a), .object(let b)):
				return a.map { $0.unitType } == b.map { $0.unitType } && a.map { $0.path } == b.map { $0.path }
			default: return false
			}
		}
	}

	private let bytes: [UInt8]
	private var i = 0
	private var result: [String: Fields] = [:]

	static func switchbackFields(_ bytes: [UInt8]) -> [String: Fields] {
		var scanner = OrderedJSONScanner(bytes: bytes)
		guard scanner.scanRoot() else { return [:] }
		return scanner.result
	}

	private init(bytes: [UInt8]) {
		self.bytes = bytes
	}

	private mutating func scanRoot() -> Bool {
		// A UTF-8 byte order mark, which JSONSerialization accepts.
		if bytes.starts(with: [0xEF, 0xBB, 0xBF]) {
			i = 3
		}
		skipWhitespace()
		guard peek() == UInt8(ascii: "{") else { return false }
		var seen: Set<String> = []
		var ambiguous: Set<String> = []
		let ok = scanObject { scanner, key in
			if key == "experiments" || key == "holdouts" {
				if !seen.insert(key).inserted { ambiguous.insert(key) }
				return scanner.scanExperiments(key)
			}
			return scanner.skipValue()
		}
		// Foundation's duplicate-root choice varies by platform. Never overlay metadata from a
		// different occurrence onto the experiments the caller's decoder chose.
		for field in ambiguous {
			result = result.filter { !$0.key.hasPrefix(field + "/") }
		}
		return ok
	}

	private mutating func scanExperiments(_ field: String) -> Bool {
		skipWhitespace()
		guard peek() == UInt8(ascii: "[") else { return skipValue() }
		var index = 0
		return scanArray { scanner in
			defer { index += 1 }
			scanner.skipWhitespace()
			guard scanner.peek() == UInt8(ascii: "{") else { return scanner.skipValue() }
			return scanner.scanObject { scanner, key in
				scanner.skipWhitespace()
				let path = "\(field)/#\(index)"
				if Self.valueFields.contains(key) {
					let start = scanner.i
					guard scanner.skipValue() else { return false }
					scanner.result[path, default: Fields()].values[key] = Data(scanner.bytes[start..<scanner.i])
					return true
				}
				guard key == "switchbackClusters" else { return scanner.skipValue() }
				guard scanner.peek() == UInt8(ascii: "{") else {
					let start = scanner.i
					let isArray = scanner.peek() == UInt8(ascii: "[")
					guard scanner.skipValue() else { return false }
					scanner.result[path, default: Fields()].clusters = isArray
						? .arrayRepresentation(Data(scanner.bytes[start..<scanner.i])) : .notAnObject
					return true
				}
				var entries: [(unitType: String, path: String?)] = []
				let ok = scanner.scanObject { scanner, unitType in
					scanner.skipWhitespace()
					var path: String?
					if scanner.peek() == UInt8(ascii: "\"") {
						path = scanner.readString()
						guard path != nil else { return false }
					} else {
						guard scanner.skipValue() else { return false }
					}
					if let existing = entries.firstIndex(where: { SwitchbackServing.sameKey($0.unitType, unitType) }) {
						entries[existing].path = path
					} else {
						entries.append((unitType, path))
					}
					return true
				}
				scanner.result[path, default: Fields()].clusters = .object(entries)
				return ok
			}
		}
	}

	private func peek() -> UInt8? {
		return i < bytes.count ? bytes[i] : nil
	}

	private mutating func skipWhitespace() {
		while let c = peek(), c == 0x20 || c == 0x0A || c == 0x0D || c == 0x09 {
			i += 1
		}
	}

	private mutating func consume(_ c: UInt8) -> Bool {
		skipWhitespace()
		guard peek() == c else { return false }
		i += 1
		return true
	}

	// Calls `member` with each key, positioned at its value, which `member` must read.
	private mutating func scanObject(_ member: (inout OrderedJSONScanner, String) -> Bool) -> Bool {
		guard consume(UInt8(ascii: "{")) else { return false }
		if consume(UInt8(ascii: "}")) {
			return true
		}
		while true {
			skipWhitespace()
			guard let key = readString(), consume(UInt8(ascii: ":")), member(&self, key) else { return false }
			if consume(UInt8(ascii: ",")) {
				continue
			}
			return consume(UInt8(ascii: "}"))
		}
	}

	private mutating func scanArray(_ element: (inout OrderedJSONScanner) -> Bool) -> Bool {
		guard consume(UInt8(ascii: "[")) else { return false }
		if consume(UInt8(ascii: "]")) {
			return true
		}
		while true {
			guard element(&self) else { return false }
			if consume(UInt8(ascii: ",")) {
				continue
			}
			return consume(UInt8(ascii: "]"))
		}
	}

	private mutating func skipValue() -> Bool {
		skipWhitespace()
		guard let c = peek() else { return false }
		switch c {
		case UInt8(ascii: "{"):
			return scanObject { scanner, _ in scanner.skipValue() }
		case UInt8(ascii: "["):
			return scanArray { scanner in scanner.skipValue() }
		case UInt8(ascii: "\""):
			return readString() != nil
		default:
			// A number or literal: everything up to the next delimiter.
			let start = i
			while let c = peek(), c != UInt8(ascii: ","), c != UInt8(ascii: "}"), c != UInt8(ascii: "]"),
				c != 0x20, c != 0x0A, c != 0x0D, c != 0x09
			{
				i += 1
			}
			return i > start
		}
	}

	// Reads a string at the cursor, decoding its escapes.
	private mutating func readString() -> String? {
		guard peek() == UInt8(ascii: "\"") else { return nil }
		i += 1
		var utf8: [UInt8] = []
		var utf16: [UInt16] = []
		func flushUTF16() -> Bool {
			guard !utf16.isEmpty else { return true }
			var decoded = ""
			// An unpaired surrogate reads as U+FFFD, so a payload the decoder accepts is still scanned.
			for scalar in Unicode.Scalar.decode(utf16) {
				decoded.unicodeScalars.append(scalar ?? "\u{FFFD}")
			}
			utf8.append(contentsOf: decoded.utf8)
			utf16 = []
			return true
		}
		while let c = peek() {
			i += 1
			if c == UInt8(ascii: "\"") {
				guard flushUTF16() else { return nil }
				return String(decoding: utf8, as: UTF8.self)
			}
			if c != UInt8(ascii: "\\") {
				guard flushUTF16() else { return nil }
				utf8.append(c)
				continue
			}
			guard let e = peek() else { return nil }
			i += 1
			if e == UInt8(ascii: "u") {
				guard i + 4 <= bytes.count, let unit = UInt16(String(decoding: bytes[i..<(i + 4)], as: UTF8.self), radix: 16)
				else { return nil }
				i += 4
				utf16.append(unit)
				continue
			}
			guard flushUTF16() else { return nil }
			switch e {
			case UInt8(ascii: "\""), UInt8(ascii: "\\"), UInt8(ascii: "/"): utf8.append(e)
			case UInt8(ascii: "b"): utf8.append(0x08)
			case UInt8(ascii: "f"): utf8.append(0x0C)
			case UInt8(ascii: "n"): utf8.append(0x0A)
			case UInt8(ascii: "r"): utf8.append(0x0D)
			case UInt8(ascii: "t"): utf8.append(0x09)
			default: return nil
			}
		}
		return nil
	}
}

private extension Unicode.Scalar {
	// Decodes UTF-16 code units; nil for each unpaired surrogate.
	static func decode(_ units: [UInt16]) -> [Unicode.Scalar?] {
		var result: [Unicode.Scalar?] = []
		var iterator = units.makeIterator()
		var decoder = UTF16()
		while true {
			switch decoder.decode(&iterator) {
			case .scalarValue(let scalar): result.append(scalar)
			case .emptyInput: return result
			case .error: result.append(nil)
			}
		}
	}
}
