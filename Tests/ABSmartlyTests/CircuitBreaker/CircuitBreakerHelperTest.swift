import CircuitBreaker
import Foundation
import PromiseKit
import XCTest

@testable import ABSmartly

final class CircuitBreakerHandlerTest: XCTestCase {
	private var errorInOpenState: Int = 0
	private var errorInCall: Int = 0
	private var successCount: Int = 0

	var helper: CircuitBreakerHelper! = nil

	func testPromises() async {
		let expectation = XCTestExpectation()
		print("Linha 1")
		var promise = Promise<String> { seal in
			print("external promise executed 1")
			var prom = Promise<String> { seal2 in
				print("internal promise executed 1")
				usleep(useconds_t(2000 * 1000))
				print("internal promise executed 2")
				seal2.fulfill("Test Result")
			}
			print("external promise executed 2")
			//expectation.fulfill()
			prom.get { s in
				usleep(useconds_t(3000 * 1000))
				print("external promise get executed")
				seal.fulfill(s)
			}
		}
		print("Linha 2")
		promise = promise.then { result -> Promise<String> in
			print(result)
			return Promise<String> { seal3 in
				seal3.fulfill("Test Result 2")
				expectation.fulfill()
			}
		}
		print("Linha 3")
		promise.done { response in
			print("finalizou o promise: " + response)
		}

		print("Linha 4")

		wait(for: [expectation], timeout: 8.0)
		print("terminou a classe")
	}

	func testCircuitBreakerTimeout() async {
		let expectation = XCTestExpectation()

		var resilienceConfig = ResilienceConfig(localCache: MemoryCache())
		resilienceConfig.timeoutInMilliseconds = 1000

		var mockHandler = ContextEventHandlerMock()

		helper = CircuitBreakerHelper(resilienceConfig: resilienceConfig, handler: mockHandler)
		print("Linha 1")
		let (promise, resolver) = Promise<Void>.pending()

		promise.done { data in
			print("main promise")
		}

		print("Linha 2")
		let (fallbackPromise, fallBackResolver) = Promise<BreakerError?>.pending()

		print("Linha 3")
		fallbackPromise.done { data in
			XCTAssertEqual("A timeout occurred.", data!.reason)
			print("gravando no cache")
			expectation.fulfill()
		}

		var promise2 = helper.decorate(promise: promise, fallBackResolver: fallBackResolver)

		promise2.done { data in
			print("promise2 finished")

		}
		wait(for: [expectation], timeout: 8.0)
	}

	func testCircuitBreakerError() async {
		let expectation = XCTestExpectation()

		var resilienceConfig = ResilienceConfig(localCache: MemoryCache())

		var mockHandler = ContextEventHandlerMock()

		helper = CircuitBreakerHelper(resilienceConfig: resilienceConfig, handler: mockHandler)
		print("Linha 1")
		let (promise, resolver) = Promise<Void>.pending()

		promise.done { data in
			print("main promise")
			expectation.fulfill()
		}

		print("Linha 2")
		let (fallbackPromise, fallBackResolver) = Promise<BreakerError?>.pending()

		print("Linha 3")
		fallbackPromise.done { data in
			XCTAssertEqual("General Error", data!.reason)
			print("gravando no cache")
			expectation.fulfill()
		}

		var promise2 = helper.decorate(promise: promise, fallBackResolver: fallBackResolver)

		promise2.done { data in
			print("promise2 finished")
		}

		resolver.reject(ABSmartlyError("General Error"))
		wait(for: [expectation], timeout: 8.0)
	}

	func testCircuitBreakerFullProcess() async {
		let expectation = XCTestExpectation()

		var resilienceConfig = ResilienceConfig(localCache: MemoryCache())
		resilienceConfig.backoffPeriodInMilliseconds = 1000

		var mockHandler = ContextEventHandlerMock()

		helper = CircuitBreakerHelper(resilienceConfig: resilienceConfig, handler: mockHandler)

		var errorInOpenState: Int = 0
		var errorInCall: Int = 0
		var successCount: Int = 0

		for (index) in 1...300 {
			let (promise, resolver) = Promise<Void>.pending()
			let (fallbackPromise, fallBackResolver) = Promise<BreakerError?>.pending()
			let event = PublishEvent()
			event.publishedAt = Int64(index)
			fallbackPromise.done { err in
				if err != nil {
					if err == .fastFail {
						errorInOpenState = errorInOpenState + 1
						usleep(useconds_t(Int.random(in: 0..<40) * 1000))

					} else {
						errorInCall = errorInCall + 1
					}
				} else {
					successCount = successCount + 1
				}
			}

			var promise2 = helper.decorate(promise: promise, fallBackResolver: fallBackResolver)

			usleep(useconds_t(Int.random(in: 0..<200) * 1000))

			if index > 100 && index < 200 {
				resolver.reject(ABSmartlyError("General Error"))
			} else {
				resolver.fulfill(())
			}

		}

		usleep(useconds_t(2000 * 1000))

		print("errorInOpenState: \(errorInOpenState)")
		print("errorInCall: \(errorInCall)")
		print("successCount: \(successCount)")
		XCTAssertEqual(1, mockHandler.flushCacheCallsCount)
		XCTAssertTrue(errorInOpenState > 0)
		XCTAssertTrue(errorInCall > 0)
		XCTAssertTrue(successCount > 0)
		XCTAssertTrue(errorInOpenState > errorInCall)
		XCTAssertEqual(errorInOpenState + errorInCall + successCount, 300)

	}

}
