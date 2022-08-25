import Foundation

public class DefaultScheduledHandle: ScheduledHandle {
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

	public init(handle: DispatchSourceTimer) {
		self.handle = handle
	}

	private let handle: DispatchSourceTimer?
}

public class DefaultScheduler: Scheduler {
	public init() {}

	public func schedule(after: TimeInterval, execute: @escaping Work) -> ScheduledHandle {
		let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.main)
		timer.setEventHandler(qos: .background, handler: execute)
		timer.schedule(deadline: .now() + after, leeway: .milliseconds(5))
		timer.resume()

		return DefaultScheduledHandle(handle: timer)
	}

	public func scheduleWithFixedDelay(after: TimeInterval, repeating: TimeInterval, execute: @escaping Work)
		-> ScheduledHandle
	{
		let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.main)
		timer.setEventHandler(
			qos: .background,
			handler: {
				timer.suspend()
				execute()
				timer.resume()
			})

		timer.schedule(deadline: .now() + after, repeating: repeating, leeway: .milliseconds(5))
		timer.resume()

		return DefaultScheduledHandle(handle: timer)
	}
}
