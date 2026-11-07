import Foundation

public class ContextConfig {
	private(set) var unitValues: [String: JSON] = [:]
	var units: [String: String] {
		return unitValues.mapValues { $0.string ?? $0.stringValue }
	}
	private(set) var attributes: [String: JSON] = [:]
	private(set) var overrides: [String: Int] = [:]
	private(set) var cassignments: [String: Int] = [:]
	public var eventLogger: ContextEventLogger?
	public var publishDelay: TimeInterval = 0.1
	public var refreshInterval: TimeInterval = 0

	public init() {
	}

	public func setUnit(unitType: String, uid: String) {
		unitValues[unitType] = JSON(uid)
	}

	/// Sets a unit whose UID is a number. Like the JavaScript SDK, the number is kept as a
	/// number and hashed as its value rounded to an integer (`toFixed(0)`).
	public func setUnit(unitType: String, uid: Int) {
		unitValues[unitType] = JSON(uid)
	}

	public func setUnit(unitType: String, uid: Double) {
		unitValues[unitType] = JSON(uid)
	}

	/// Sets a unit from a JSON value (string or number). Other values are rejected when the
	/// context is created, which logs an `error` event for them.
	public func setUnit(unitType: String, value: JSON) {
		unitValues[unitType] = value
	}

	public func setUnits(units: [String: String]) {
		for (unitType, uid) in units {
			setUnit(unitType: unitType, uid: uid)
		}
	}

	public func setAttribute(name: String, value: JSON) {
		attributes[name] = value
	}

	public func setAttributes(attributes: [String: JSON]) {
		for (name, value) in attributes {
			setAttribute(name: name, value: value)
		}
	}

	public func setOverride(experimentName: String, variant: Int) {
		overrides[experimentName] = variant
	}

	public func setOverrides(overrides: [String: Int]) {
		for (experimentName, variant) in overrides {
			setOverride(experimentName: experimentName, variant: variant)
		}
	}

	public func setCustomAssignment(experimentName: String, variant: Int) {
		cassignments[experimentName] = variant
	}

	public func setCustomAssignments(assignments: [String: Int]) {
		for (experimentName, variant) in assignments {
			setCustomAssignment(experimentName: experimentName, variant: variant)
		}
	}
}
