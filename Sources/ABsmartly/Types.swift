import Foundation

/// A unit type: the kind of identifier a UID is, such as a device or a user.
public struct UnitType: RawRepresentable, Hashable, Sendable, ExpressibleByStringLiteral, CustomStringConvertible {
	public let rawValue: String

	public init(rawValue: String) {
		self.rawValue = rawValue
	}

	public init(_ rawValue: String) {
		self.rawValue = rawValue
	}

	public init(stringLiteral value: String) {
		rawValue = value
	}

	public var description: String { rawValue }

	public static let deviceID: UnitType = "device_id"
	public static let userID: UnitType = "user_id"
	public static let sessionID: UnitType = "session_id"
}

/// Receives every event of the contexts it is configured for.
///
/// It is called outside the SDK's locks, so it may call back into the context. `exposure`, `goal`
/// and `error` arrive synchronously on the thread that caused them; `ready`, `refresh`, `publish`
/// and `close` arrive on the main thread on Apple platforms (as in 1.x, so a logger may touch UIKit)
/// and on the completing thread on Linux.
public struct EventLogger: Sendable {
	public let handle: @Sendable (Context, Context.Event) -> Void

	public init(_ handle: @escaping @Sendable (Context, Context.Event) -> Void) {
		self.handle = handle
	}

	/// A logger that calls `handle` for every event.
	public static func custom(_ handle: @escaping @Sendable (Context, Context.Event) -> Void) -> EventLogger {
		EventLogger(handle)
	}

	/// Writes every event to the unified logging system (subsystem `com.absmartly.sdk`, category
	/// `events`); errors at error level, the rest at debug level. Prints on Linux.
	public static let osLog = EventLogger { _, event in
		EventLog.write(event)
	}
}
