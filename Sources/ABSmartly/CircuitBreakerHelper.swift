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
	private var timeout: ScheduledHandle?
	private var backoffPeriodInMilliseconds: Int?

	public init(resilienceConfig: ResilienceConfig) {
		self.backoffPeriodInMilliseconds = resilienceConfig.backoffPeriodInMilliseconds
		self.circuitBreaker = CircuitBreaker(
			name: "Circuit1",
			timeout: resilienceConfig.timeoutInMilliseconds,
			maxFailures: resilienceConfig.failureRateThreshold,
			command: callFunction,
			fallback: fallback)
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
			invocation.notifySuccess()

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
			//print("helper: promise error: " + message)
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
							print("Entering in half open")
							circuitBreaker.forceHalfOpen()
						}

					})
			}
		}
	}
}
