import Foundation

public class Application: Codable, Equatable {
	public let name: String?

	init(_ name: String) {
		self.name = name
	}

	public static func == (lhs: Application, rhs: Application) -> Bool {
		return lhs.name == rhs.name
	}
}
