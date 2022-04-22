import Foundation

// sourcery: AutoMockable
public protocol VariableParser {
	func parse(experimentName: String, config: String) -> [String: JSON]?
}
