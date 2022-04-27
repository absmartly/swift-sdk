import Foundation

public class ContextConfig {
	private(set) var units: [String: String] = [:]
	private(set) var attributes: [String: JSON] = [:]
	private(set) var overrides: [String: Int] = [:]
	private(set) var cassignments: [String: Int] = [:]
	public var eventLogger: ContextEventLogger?
	public var publishDelay: TimeInterval = 0.1

	public init() {
	}

	public func setUnit(unitType: String, uid: String) {
		units[unitType] = uid
	}

	public func setUnits(units: [String: String]) {
		units.forEach { setUnit(unitType: $0.key, uid: $0.value) }
	}

	public func setAttribute(name: String, value: JSON) {
		attributes[name] = value
	}

	public func setAttributes(attributes: [String: JSON]) {
		attributes.forEach { setAttribute(name: $0.key, value: $0.value) }
	}

	public func setOverride(experimentName: String, variant: Int) {
		overrides[experimentName] = variant
	}

	public func setOverrides(overrides: [String: Int]) {
		overrides.forEach { setOverride(experimentName: $0.key, variant: $0.value) }
	}

	public func setCustomAssignment(experimentName: String, variant: Int) {
		cassignments[experimentName] = variant
	}

	public func setCustomAssignments(assignments: [String: Int]) {
		assignments.forEach { setCustomAssignment(experimentName: $0.key, variant: $0.value) }
	}
}
