import Foundation

public final class ContextConfig {
	private(set) var units: [String: String] = [:]
	private(set) var attributes: [String: Any] = [:]
	private(set) var overrides: [String: Int] = [:]

	public var publishDelay: Int = 100

	public init() {

	}

	public func setUnit(unitType: String, uid: String) {
		units[unitType] = uid
	}

	public func setUnits(units: [String: String]) {
		units.forEach { setUnit(unitType: $0.key, uid: $0.value) }
	}

	public func setAttribute(name: String, value: Any) {
		attributes[name] = value
	}

	public func setAttribuets(attributes: [String: Any]) {
		attributes.forEach { setAttribute(name: $0.key, value: $0.value) }
	}

	public func setOverride(experimentName: String, variant: Int) {
		overrides[experimentName] = variant
	}

	public func setOverrides(overrides: [String: Int]) {
		overrides.forEach { setOverride(experimentName: $0.key, variant: $0.value) }
	}
}
