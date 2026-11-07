import Foundation

public class DefaultScheduledHandle: ScheduledHandle {
	private var handle: DispatchSourceTimer?
	private var cancelled = false
	private let lock = NSLock()

	public func cancel() {
		lock.lock()
		defer { lock.unlock() }

		guard let timer = handle, !cancelled else { return }
		cancelled = true
		timer.cancel()
		handle = nil
	}

	public func isCancelled() -> Bool {
		lock.lock()
		defer { lock.unlock() }
		return cancelled
	}

	public init(handle: DispatchSourceTimer) {
		self.handle = handle
	}

	deinit {
		cancel()
	}
}

public class DefaultScheduler: Scheduler {
	private let timerQueue = DispatchQueue(label: "com.absmartly.scheduler", qos: .utility)

	public init() {}

	public func schedule(after: TimeInterval, execute: @escaping Work) -> ScheduledHandle {
		let timer = DispatchSource.makeTimerSource(queue: timerQueue)
		timer.setEventHandler(qos: .utility, handler: execute)
		timer.schedule(deadline: .now() + after, leeway: .milliseconds(5))
		timer.resume()

		return DefaultScheduledHandle(handle: timer)
	}

	public func scheduleWithFixedDelay(after: TimeInterval, repeating: TimeInterval, execute: @escaping Work)
		-> ScheduledHandle
	{
		let timer = DispatchSource.makeTimerSource(queue: timerQueue)
		timer.setEventHandler(qos: .utility, handler: execute)
		timer.schedule(deadline: .now() + after, repeating: repeating, leeway: .milliseconds(5))
		timer.resume()

		return DefaultScheduledHandle(handle: timer)
	}
}
