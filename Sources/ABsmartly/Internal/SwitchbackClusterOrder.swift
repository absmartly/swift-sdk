import Foundation

// Carries the raw context data bytes to `Experiment.init(from:)` through `JSONDecoder.userInfo`, so a
// `switchbackClusters` object can be read in its JSON key order: a keyed decoding container's
// `allKeys` has no defined order. The bytes are only scanned when an experiment has a cluster map
// with more than one entry, once per payload.
final class SwitchbackClusterOrder: Sendable {
	static let userInfoKey = CodingUserInfoKey(rawValue: "com.absmartly.switchbackClusterOrder")!

	#if DEBUG
		@TaskLocal static var scanWorkCount: Locked<Int>?
	#endif

	private let json: Data
	private let scanned = Locked<[String: [String]]?>(nil)

	init(json: Data) {
		self.json = json
	}

	// The keys of the `switchbackClusters` object of the experiment at `codingPath`, in JSON order and
	// without duplicates; nil when the bytes have no such object.
	func keys(at codingPath: [CodingKey]) -> [String]? {
		scanned.withLock { scanned in
			if scanned == nil {
				#if DEBUG
					Self.scanWorkCount?.withLock { $0 += 1 }
				#endif
				scanned = OrderedJSONScanner.switchbackClusterKeys(Array(json))
			}
			return scanned?[Self.pathKey(codingPath)]
		}
	}

	static func pathKey(_ codingPath: [CodingKey]) -> String {
		return codingPath.map { $0.intValue.map { "#\($0)" } ?? $0.stringValue }.joined(separator: "/")
	}
}

// A minimal JSON reader that records, for every object in the top-level `experiments` and `holdouts`
// arrays, the key order of its `switchbackClusters` object. Anything it cannot read gives no entry,
// so the experiment's order stays unknown. A cluster key holding an unpaired surrogate escape reads as
// U+FFFD here; where the decoder keeps it otherwise, the keys do not match and that switchback serves
// only control.
struct OrderedJSONScanner {
	private let bytes: [UInt8]
	private var i = 0
	private var result: [String: [String]] = [:]

	static func switchbackClusterKeys(_ bytes: [UInt8]) -> [String: [String]] {
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
		return scanObject { scanner, key in
			if key == "experiments" || key == "holdouts" {
				return scanner.scanExperiments(key)
			}
			return scanner.skipValue()
		}
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
				if key == "switchbackClusters" && scanner.peek() == UInt8(ascii: "{") {
					var keys: [String] = []
					let ok = scanner.scanObject { scanner, clusterKey in
						if !keys.contains(clusterKey) {
							keys.append(clusterKey)
						}
						return scanner.skipValue()
					}
					// A later duplicate `switchbackClusters` replaces an earlier one, as in the decoder.
					scanner.result["\(field)/#\(index)"] = keys
					return ok
				}
				return scanner.skipValue()
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
				guard i + 4 <= bytes.count,
					let unit = UInt16(String(decoding: bytes[i..<(i + 4)], as: UTF8.self), radix: 16)
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

extension Unicode.Scalar {
	// Decodes UTF-16 code units; nil for each unpaired surrogate.
	fileprivate static func decode(_ units: [UInt16]) -> [Unicode.Scalar?] {
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
