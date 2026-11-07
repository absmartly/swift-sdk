import Foundation

class ABSmartlyHTTPError: Error {
	let statusCode: Int
	let description: String

	init(_ code: Int, _ desc: String) {
		self.statusCode = code
		self.description = desc
	}
}

extension ABSmartlyHTTPError: LocalizedError {
	public var errorDescription: String? {
		return description
	}
}

public class ABSmartlyError: Error {
	public let errorMessage: String

	public init(_ errorMessage: String) {
		self.errorMessage = errorMessage
	}
}

extension ABSmartlyError: LocalizedError {
	public var errorDescription: String? {
		return errorMessage
	}
}
