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

extension Error {
	/// `localizedDescription`, except on Linux with Swift 6.0 and 6.1, whose Foundation crashes when
	/// bridging a class-based error such as `ABSmartlyError` to `NSError`
	/// (https://github.com/swiftlang/swift-corelibs-foundation/issues/5221). There it reads
	/// `LocalizedError.errorDescription` directly, which is what `localizedDescription` returns.
	var safeLocalizedDescription: String {
		#if os(Linux) && compiler(>=6.0) && !compiler(>=6.2)
			if !(self is NSError) && Mirror(reflecting: self).displayStyle == .class {
				return (self as? LocalizedError)?.errorDescription ?? String(describing: self)
			}
		#endif
		return localizedDescription
	}
}
