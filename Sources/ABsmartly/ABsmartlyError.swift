import Foundation

/// Every error the SDK reports, thrown by its `async` APIs and delivered as `.error` events.
///
/// `localizedDescription`/`errorDescription` are the 1.x messages, which the cross-SDK tests match.
/// Later 2.x releases may add cases, so a `switch` over this type should have a `default` case.
public enum ABsmartlyError: Error, Sendable, Hashable {
	/// A required configuration value is missing; the message names it.
	case invalidConfiguration(String)
	/// A read or publish before the context finished loading.
	case notReady
	/// The context is closing.
	case closing
	/// The context is closed.
	case closed
	/// `setUnit` with a UID that is empty or only whitespace.
	case blankUnitUID(unitType: String)
	/// `setUnit` with a UID different from the one already set for that unit type.
	case unitAlreadySet(unitType: String)
	/// The collector answered with a status outside 200–299.
	case httpStatus(code: Int, message: String)
	/// The request failed before a response was received.
	case transport(String)
	/// A response, context data or JSON text could not be decoded.
	case decoding(String)
	/// The operation was cancelled.
	case cancelled
}

extension ABsmartlyError: LocalizedError {
	public var errorDescription: String? {
		switch self {
		case .invalidConfiguration(let message): return message
		case .notReady: return "ABsmartly Context is not yet ready."
		case .closing: return "ABsmartly Context is finalizing."
		case .closed: return "ABsmartly Context is finalized."
		case .blankUnitUID(let unitType): return "Unit '\(unitType)' UID must not be blank."
		case .unitAlreadySet(let unitType): return "Unit '\(unitType)' UID already set."
		case .httpStatus(_, let message): return message
		case .transport(let message): return message
		case .decoding(let message): return message
		case .cancelled: return "The operation was cancelled."
		}
	}
}

extension ABsmartlyError: CustomStringConvertible {
	public var description: String { errorDescription ?? "ABsmartlyError" }
}

extension ABsmartlyError {
	/// Wraps any error thrown by a transport or decoder.
	static func wrapping(_ error: any Error) -> ABsmartlyError {
		switch error {
		case let error as ABsmartlyError: return error
		case is CancellationError: return .cancelled
		case is DecodingError: return .decoding(error.safeDescription)
		default:
			if let urlError = error as? URLError, urlError.code == .cancelled {
				return .cancelled
			}
			return .transport(error.safeDescription)
		}
	}
}

extension Error {
	/// `localizedDescription`, except for class-based non-`NSError` errors on Linux with Swift 6.0
	/// and 6.1, where reading it crashes
	/// (https://github.com/swiftlang/swift-corelibs-foundation/issues/5221). There it reads
	/// `LocalizedError.errorDescription` directly, which is what `localizedDescription` returns.
	var safeDescription: String {
		#if os(Linux) && !compiler(>=6.2)
			// The dynamic-type test behaves like `self is NSError`, which Swift 6.0 on Linux flags as
			// "always true" (an error under -warnings-as-errors) although it is false at runtime for
			// non-NSError errors.
			if !(type(of: self) is NSError.Type) && Mirror(reflecting: self).displayStyle == .class {
				return (self as? LocalizedError)?.errorDescription ?? String(describing: self)
			}
		#endif
		return localizedDescription
	}
}
