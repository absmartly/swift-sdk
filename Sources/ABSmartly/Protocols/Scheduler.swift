import Foundation

// sourcery: AutoMockable
public protocol ScheduledHandle {
	func cancel()
	func isCancelled() -> Bool
}

// sourcery: AutoMockable
public protocol Scheduler {
	typealias Work = () -> Void

	func schedule(after: TimeInterval, execute: @escaping Work) -> ScheduledHandle
	func scheduleWithFixedDelay(after: TimeInterval, repeating: TimeInterval, execute: @escaping Work)
		-> ScheduledHandle
}
