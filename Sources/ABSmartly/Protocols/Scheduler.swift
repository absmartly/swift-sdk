import Foundation

// sourcery: AutoMockable
public protocol ScheduledHandle {
	func wait()
	func cancel()
	func isCancelled() -> Bool
}

// sourcery: AutoMockable
public protocol Scheduler {
	typealias Work = () -> Void

	func schedule(after: TimeInterval, execute: @escaping Work) -> ScheduledHandle
}
