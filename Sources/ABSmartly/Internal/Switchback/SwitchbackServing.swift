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

	// The cluster key an attribute value yields (the Collector's SwitchbackClusterKeys.normalize): a
	// non-empty string as-is and an integer as its base-10 text. Null, empty strings, booleans,
	// floating-point numbers (3.0 included), objects and arrays yield none. A JSON number is a float
	// when it was written with a fraction or exponent, or set from a Swift `Double` or `Float`.
	static func clusterKey(_ value: JSON?) -> String? {
		guard let value = value else { return nil }
		switch value.type {
		case .string:
			let string = value.stringValue
			return string.isEmpty ? nil : string
		case .number:
			guard let number = value.object as? NSNumber, !isFloatingPoint(number) else { return nil }
			return number.stringValue
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
