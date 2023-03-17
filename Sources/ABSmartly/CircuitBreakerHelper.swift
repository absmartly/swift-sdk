//
// Created by Hermes Waldemarin on 14/03/2023.
//

import CircuitBreaker
import Foundation
import PromiseKit

public class CircuitBreakerHelper {

	private var circuitBreaker: CircuitBreaker<Promise<Void>, Resolver<BreakerError?>>!
	private let scheduler: Scheduler = DefaultScheduler()
	private let timeoutLock = NSLock()
	private let flushLock = NSLock()
	private var flushInExecution = false
	private var timeout: ScheduledHandle?
	private var backoffPeriodInMilliseconds: Int?
	private var handler: ContextEventHandler?

	public init(resilienceConfig: ResilienceConfig, handler: ContextEventHandler) {
		self.backoffPeriodInMilliseconds = resilienceConfig.backoffPeriodInMilliseconds
		self.circuitBreaker = CircuitBreaker(
			name: "Circuit1",
			timeout: resilienceConfig.timeoutInMilliseconds,
			maxFailures: resilienceConfig.failureRateThreshold,
			command: callFunction,
			fallback: fallback)
		self.handler = handler
	}

	public func decorate(promise: Promise<Void>, fallBackResolver: Resolver<BreakerError?>) -> Promise<Void> {
		return Promise<Void> { seal in
			circuitBreaker.run(commandArgs: promise, fallbackArgs: fallBackResolver)
			seal.fulfill(())
		}
	}

	func callFunction(invocation: Invocation<Promise<Void>, Resolver<BreakerError?>>) {
		let promise = invocation.commandArgs
		let fallBackResolver = invocation.fallbackArgs

		promise.done { response in
			//print("helper: promise done")
			fallBackResolver.fulfill(nil)
			var state = self.circuitBreaker.breakerState
			invocation.notifySuccess()
			if (state == .halfopen) && !self.flushInExecution {
				self.flushInExecution = true
				DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
					self.timeoutLock.lock()
					defer { self.timeoutLock.unlock() }
					self.handler?.flushCache()
					self.flushInExecution = false
				}
			}

		}.catch { error in
			var key = ""
			var message = ""
			if error is LocalizedError {
				let localizedError = error as! LocalizedError
				key = localizedError._domain
				message = localizedError.errorDescription ?? ""
			} else {
				let nsError = error as! NSError
				key = error._domain
				nsError.code
				message = error.localizedDescription
			}

			invocation.notifyFailure(
				error: BreakerError(
					key: key,
					reason: message
				)
			)
		}
	}

	private func fallback(err: BreakerError, fallBackPromise: Resolver<BreakerError?>) {
		//print("helper: fallback")
		fallBackPromise.fulfill(err)
		if err == .fastFail {
			setTimeout()
		} else {
		}
	}

	private func clearTimeout() {
		if timeout != nil {
			timeoutLock.lock()
			defer { timeoutLock.unlock() }

			timeout?.cancel()
			timeout = nil
		}
	}

	private func setTimeout() {
		if timeout == nil {
			timeoutLock.lock()
			defer { timeoutLock.unlock() }

			if timeout == nil {
				timeout = scheduler.schedule(
					after: Double((backoffPeriodInMilliseconds! / 1000)),
					execute: { [self] in
						clearTimeout()
						if circuitBreaker.breakerState != State.closed {
							print("Resilience entering in half open state")
							circuitBreaker.forceHalfOpen()
						}

					})
			}
		}
	}
}
