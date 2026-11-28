import Foundation

// Which unit serves a switchback experiment and under which cluster key. Port of java-sdk
// internal/SwitchbackServing.java (the Collector's ContextAPI.switchbackServing, R33):
//
// - The sources are the experiment's switchbackClusters entries in their declared order.
// - No context unit of a linked type: the experiment does not apply (absent).
// - Otherwise each linked unit, in source order, reads the attribute at its source's path, normalised
//   by `clusterKey(_:)`. The first unit yielding a value is the serving unit and the value is the
//   cluster key; units yielding no value are skipped.
// - Ineligible, served under the first linked unit: no unit yields a value, two units yield different
//   values, or an allow-list is set and lacks the key.
// - Eligible otherwise.
// - A missing, empty or unreadable cluster map takes the Collector's legacy path instead (`legacy`).
struct SwitchbackServing {
	enum Status {
		case absent
		case ineligible
		case eligible
	}

	let status: Status
	// The serving unit's type when eligible, the first linked unit's type when ineligible, nil when absent.
	let unitType: String?
	// The raw normalised cluster key when eligible; never hashed.
	let clusterKey: String?

	// A context has at most one unit per type, so the source loop alone orders the units.
	static func resolve(
		sources: [(unitType: String, path: SwitchbackAttributePath)], allowedValues: [String]?,
		hasUnit: (String) -> Bool, read: (SwitchbackAttributePath) -> JSON?
	) -> SwitchbackServing {
		var first: String?
		var serving: String?
		var key: String?
		var disagreement = false
		for source in sources where hasUnit(source.unitType) {
			if first == nil {
				first = source.unitType
			}
			guard let value = clusterKey(read(source.path)) else { continue }
			if let key = key {
				disagreement = disagreement || !sameKey(key, value)
			} else {
				key = value
				serving = source.unitType
			}
		}

		guard let firstUnitType = first else {
			return SwitchbackServing(status: .absent, unitType: nil, clusterKey: nil)
		}
		guard let clusterKey = key, !disagreement, allowed(allowedValues, clusterKey) else {
			return SwitchbackServing(status: .ineligible, unitType: firstUnitType, clusterKey: nil)
		}
		return SwitchbackServing(status: .eligible, unitType: serving, clusterKey: clusterKey)
	}

	// The Collector's compatibility path for a missing, empty or unreadable cluster map: the declared
	// unitType only identifies an ineligible control (never an assignment or a cluster); without a unit
	// of that type the experiment does not apply.
	static func legacy(unitType: String?, hasUnit: (String) -> Bool) -> SwitchbackServing {
		if let unitType = unitType, hasUnit(unitType) {
			return SwitchbackServing(status: .ineligible, unitType: unitType, clusterKey: nil)
		}
		return SwitchbackServing(status: .absent, unitType: nil, clusterKey: nil)
	}

	// A nil or empty allow-list admits every value, as in the Collector.
	static func allowed(_ allowedValues: [String]?, _ key: String) -> Bool {
		guard let allowedValues = allowedValues, !allowedValues.isEmpty else { return true }
		return allowedValues.contains { sameKey($0, key) }
	}

	// Cluster keys compare by their UTF-16 code units, as Java's String.equals and JavaScript's ===
	// do. Swift's String == treats canonically equivalent strings (a composed and a decomposed "é")
	// as equal, which the Collector does not.
	static func sameKey(_ a: String, _ b: String) -> Bool {
		return a.utf16.elementsEqual(b.utf16)
	}

	static func sameKey(_ a: String?, _ b: String?) -> Bool {
		switch (a, b) {
		case (.none, .none): return true
		case (.some(let a), .some(let b)): return sameKey(a, b)
		default: return false
		}
	}

	static func sameKeys(_ a: [String]?, _ b: [String]?) -> Bool {
		switch (a, b) {
		case (.none, .none): return true
		case (.some(let a), .some(let b)):
			return a.count == b.count && zip(a, b).allSatisfy { sameKey($0, $1) }
		default: return false
		}
	}

	// The cluster key an attribute value yields, as java-sdk's SwitchbackClusterKeys.normalize (the
	// Collector's rule): a non-empty string as-is and an integer as its base-10 text. A float never
	// keys a cluster, even a whole one: 3.0, 123456789.0 and -0.0 give none, while the integer 3 gives
	// "3". Booleans, null, empty strings, objects and arrays give none too.
	//
	// The decision uses the number's storage type, never its value: JSONSerialization,
	// JSON(parseJSON:) and JSON(data:) keep a "3.0" token as a double and a "3" token as an integer,
	// on Linux and Apple. An NSDecimalNumber reports "d" and gives none, like Java's BigDecimal.
	static func clusterKey(_ value: JSON?) -> String? {
		guard let value = value else { return nil }
		switch value.type {
		case .string:
			let string = value.stringValue
			return string.isEmpty ? nil : string
		case .number:
			guard let number = value.object as? NSNumber, isIntegerStorage(number) else { return nil }
			return number.stringValue
		default:
			return nil
		}
	}

	// An integer NSNumber (Objective-C type encoding c, s, i, l, q or an unsigned one). A floating-point
	// one is f or d. CFNumberIsFloatType is not available on Linux; objCType is, on every platform.
	static func isIntegerStorage(_ number: NSNumber) -> Bool {
		switch String(cString: number.objCType) {
		case "c", "s", "i", "l", "q", "C", "S", "I", "L", "Q": return true
		default: return false
		}
	}
}
