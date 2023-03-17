import CircuitBreaker
import Foundation
import PromiseKit
import XCTest

@testable import ABSmartly

final class ResilientContextDataProviderTest: XCTestCase {

	var contextData: ContextData?

	func getContextDataOK() -> Promise<ContextData> {
		return Promise<ContextData> { seal in
			seal.fulfill(self.contextData!)
		}
	}

	func getContextData(source: String = "context") throws -> ContextData {
		let path = Bundle.module.path(forResource: source, ofType: "json", inDirectory: "Resources")!
		let data = try Foundation.Data(contentsOf: URL(fileURLWithPath: path), options: .mappedIfSafe)
		return try JSONDecoder().decode(ContextData.self, from: data)
	}

	func getContextDataError() -> Promise<ContextData> {
		let (promiseReturn, resolver) = Promise<ContextData>.pending()
		resolver.reject(ABSmartlyError("Error"))
		return promiseReturn
	}


	func testResilience() async throws {
		let expectation = XCTestExpectation()

		contextData = try getContextData()

		let mockClient = ClientMock()
		mockClient.getContextDataClosure = getContextDataOK
		let memoryCache = MemoryCache()
		let contextProvider = ResilientContextDataProvider(
				client: mockClient,
				localCache: memoryCache
		)

		var promise1 = contextProvider.getContextData();
		promise1.done { data in
			XCTAssertEqual(self.contextData!.experiments.count, data.experiments.count)
		}

		let mockClient2 = ClientMock()
		mockClient2.getContextDataClosure = getContextDataError
		let contextProvider2 = ResilientContextDataProvider(
				client: mockClient2,
				localCache: memoryCache
		)
		var promise2 = contextProvider2.getContextData();
		promise2.done { data in
			expectation.fulfill()
			XCTAssertEqual(self.contextData!.experiments.count, data.experiments.count)
		}

		wait(for: [expectation], timeout: 8.0)

	}

}
