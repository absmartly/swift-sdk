import Foundation
import PromiseKit
import XCTest
import CircuitBreaker

@testable import ABSmartly

extension BreakerError {
	public static let encodingURLError = BreakerError(reason: "URL could not be created")
	public static let networkingError = BreakerError(reason: "There was an error, while sending the request")
	public static let jsonDecodingError = BreakerError(reason: "Could not decode result into JSON")
}

final class CircuitBreakerLibraryTest: XCTestCase {
	private let scheduler: Scheduler = DefaultScheduler();
	private let timeoutLock = NSLock()
	private var timeout: ScheduledHandle?
	private var errorInOpenState: Int = 0
	private var errorInCall: Int = 0
	private var successCount: Int = 0

	var breaker: CircuitBreaker<[Int], String>! = nil
	func testCircuitBreaker() async {
		breaker = CircuitBreaker(name: "Circuit1", command: myContextFunction, fallback: myFallback)

		let requestParam: String = "myRequestParams"


		for (index) in 1...300 {
			let randomInt = Int.random(in: 0..<200)

			//print("Active after \(randomInt)")
			breaker.run(commandArgs: [index, randomInt], fallbackArgs: "Something went wrong.")
		}

		print("errorInOpenState \(errorInOpenState)")
		print("errorInCall \(errorInCall)")
		print("successCount \(successCount)")
		XCTAssertTrue(errorInOpenState > 0)
		XCTAssertTrue(errorInCall > 0)
		XCTAssertTrue(successCount > 0)
		XCTAssertTrue(errorInOpenState > errorInCall)
		XCTAssertEqual(errorInOpenState + errorInCall + successCount, 300)

	}

	func myContextFunction(invocation: Invocation<([Int]), String>) {
		let requestParam = invocation.commandArgs[0]
		let randomInt = invocation.commandArgs[1]
		// Create HTTP request
		let ms = 1000
		usleep(useconds_t(randomInt * ms))
		if(requestParam > 100 && requestParam < 200){
			invocation.notifyFailure(error: .encodingURLError)
		} else {
			successCount = successCount + 1
			invocation.notifySuccess()
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
				print("setTimeout")
				timeout = scheduler.schedule(
						after: 4,
						execute: { [self] in
							clearTimeout();
							if(breaker.breakerState != State.closed){
								print("Entering in half open")
								breaker.forceHalfOpen()
							}

						})
			}
		}
	}

	func myFallback(err: BreakerError, msg: String) {
		if(err == .fastFail){
			let randomInt = Int.random(in: 0..<200)
			let ms = 1000
			usleep(useconds_t(randomInt * ms))
			errorInOpenState = errorInOpenState + 1
			setTimeout();
		} else {
			errorInCall = errorInCall + 1
			print("Error: \(err.reason)")
			print("Message: \(msg)")
		}

		//XCTFail(msg)
	}
}
