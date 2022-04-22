import Foundation

public class ExperimentVariant: Codable, Equatable {
	public let name: String?
	public let config: String?

	init(_ name: String, _ config: String) {
		self.name = name
		self.config = config
	}

	public static func == (lhs: ExperimentVariant, rhs: ExperimentVariant) -> Bool {
		return lhs.name == rhs.name && lhs.config == rhs.config
	}
}
