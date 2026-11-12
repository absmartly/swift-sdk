import Foundation

// On Linux, Foundation in Swift 6.0 and 6.1 crashes when `localizedDescription` (or `as NSError`)
// bridges a class-based error that is not an NSError
// (https://github.com/swiftlang/swift-corelibs-foundation/issues/5221). So on Linux the SDK's
// errors are NSError subclasses, with the domain and code Swift would have given them, and apps
// can format them as usual. Apple platforms keep the plain classes.
#if os(Linux)
	class ABSmartlyHTTPError: NSError {
		let statusCode: Int
		let statusMessage: String

		init(_ code: Int, _ desc: String) {
			self.statusCode = code
			self.statusMessage = desc
			super.init(
				domain: "ABSmartly.ABSmartlyHTTPError", code: 1,
				userInfo: [NSLocalizedDescriptionKey: desc])
		}

		required init?(coder: NSCoder) {
			return nil
		}
	}
#else
	class ABSmartlyHTTPError: Error {
		let statusCode: Int
		let statusMessage: String

		init(_ code: Int, _ desc: String) {
			self.statusCode = code
			self.statusMessage = desc
		}
	}
#endif

extension ABSmartlyHTTPError: LocalizedError {
	public var errorDescription: String? {
		return statusMessage
	}
}

#if os(Linux)
	public class ABSmartlyError: NSError {
		public let errorMessage: String

		public init(_ errorMessage: String) {
			self.errorMessage = errorMessage
			super.init(
				domain: "ABSmartly.ABSmartlyError", code: 1,
				userInfo: [NSLocalizedDescriptionKey: errorMessage])
		}

		public required init?(coder: NSCoder) {
			return nil
		}
	}
#else
	public class ABSmartlyError: Error {
		public let errorMessage: String

		public init(_ errorMessage: String) {
			self.errorMessage = errorMessage
		}
	}
#endif

extension ABSmartlyError: LocalizedError {
	public var errorDescription: String? {
		return errorMessage
	}
}

#if os(Linux) && compiler(>=5.5)
	// NSError is @unchecked Sendable, and subclasses must restate it. Both classes are immutable.
	extension ABSmartlyHTTPError: @unchecked Sendable {}
	extension ABSmartlyError: @unchecked Sendable {}
#endif

extension Error {
	/// `localizedDescription`, except on Linux with Swift 6.0 and 6.1, where it avoids the crash
	/// described above for class-based errors that are not NSErrors (for example ones thrown by
	/// an app's own `ContextDataProvider`). There it reads `LocalizedError.errorDescription`
	/// directly, which is what `localizedDescription` returns.
	var safeLocalizedDescription: String {
		#if os(Linux) && compiler(>=6.0) && !compiler(>=6.2)
			if !(self is NSError) && Mirror(reflecting: self).displayStyle == .class {
				return (self as? LocalizedError)?.errorDescription ?? String(describing: self)
			}
		#endif
		return localizedDescription
	}
}
