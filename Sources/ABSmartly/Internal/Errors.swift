import Foundation

class NetworkError: Error {
	let statusCode: Int
	let description: String

	init(_ code: Int, _ desc: String) {
		self.statusCode = code
		self.description = desc
	}
}

extension NetworkError: LocalizedError {
	public var errorDescription: String? {
		return description
	}
}

class ABSmartlyError: Error {
	let errorMessage: String

	init(_ errorMessage: String) {
		self.errorMessage = errorMessage
	}
}

extension ABSmartlyError: LocalizedError {
	public var errorDescription: String? {
		return errorMessage
	}
}
