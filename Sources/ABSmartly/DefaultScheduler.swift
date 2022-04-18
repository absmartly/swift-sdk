import Foundation

public class DefaultScheduledHandle: ScheduledHandle {
	public func wait() {
		if handle != nil {
			handle!.wait()
		}
	}

	public func cancel() {
		if handle != nil {
			handle!.cancel()
		}
	}

	public func isCancelled() -> Bool {
		if handle != nil {
			return handle!.isCancelled
		}
		return false
	}

	public init(handle: DispatchWorkItem) {
		self.handle = handle
	}

	private let handle: DispatchWorkItem?
}

public class DefaultScheduler: Scheduler {
	public func schedule(after: TimeInterval, execute: @escaping Work) -> ScheduledHandle {
		let handle = DispatchWorkItem(block: execute)

		DispatchQueue.main.asyncAfter(deadline: .now() + after, execute: handle)

		return DefaultScheduledHandle(handle: handle)
	}
}
