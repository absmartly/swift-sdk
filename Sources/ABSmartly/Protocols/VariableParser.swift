import Foundation

/// Parses a variant's JSON config. A context can call `parse` from more than one thread at once
/// (for example while its initial load and a refresh complete together), so implementations must be
/// safe to call concurrently. `DefaultVariableParser` is.
// sourcery: AutoMockable
public protocol VariableParser {
	func parse(experimentName: String, config: String) -> [String: JSON]?
}
