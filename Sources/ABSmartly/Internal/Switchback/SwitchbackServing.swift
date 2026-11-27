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
			if key == nil {
				key = value
				serving = source.unitType
			} else if key != value {
				disagreement = true
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
		return allowedValues.contains(key)
	}

	// The Collector normalizes the published JSON, not the attribute's in-memory NSNumber type.
	// Keep the released attribute encoder unchanged: it can write a whole Double as an integer (3.0
	// -> 3), and a large whole Decimal as an exponent. Only an integer token gives a numeric key;
	// fractions and exponents do not, even when mathematically whole. Encode the leaf exactly as
	// PublishEvent does, including for numbers reached through objects/arrays. Do not round-trip
	// through JSONSerialization/JSONDecoder: they can erase exponent syntax or lose large integers.
	static func clusterKey(_ value: JSON?) -> String? {
		guard let value = value else { return nil }
		switch value.type {
		case .string:
			let string = value.stringValue
			return string.isEmpty ? nil : string
		case .number:
			// The array permits top-level scalars on all supported JSONEncoder versions.
			guard let data = try? JSONEncoder().encode([value]),
				let encoded = String(data: data, encoding: .utf8)
			else { return nil }
			let token = encoded.dropFirst().dropLast()
			let digits = token.first == "-" ? token.dropFirst() : token[...]
			guard !digits.isEmpty, digits.utf8.allSatisfy({ $0 >= 48 && $0 <= 57 }) else { return nil }
			return token == "-0" ? "0" : String(token)
		default:
			return nil
		}
	}

	// `CFNumberIsFloatType` is not available on Linux; the Objective-C type encoding is, and tells a
	// floating-point NSNumber (`f`, `d`) from an integer one on every platform.
	static func isFloatingPoint(_ number: NSNumber) -> Bool {
		let type = String(cString: number.objCType)
		return type == "d" || type == "f"
	}
}
