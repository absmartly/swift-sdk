import Foundation

public struct Application: Codable, Equatable {
	public let name: String?

	init(_ name: String) {
		self.name = name
	}
}
