import Foundation
import PromiseKit
import XCTest

@testable import ABSmartly

final class DefaultClientTest: XCTestCase {
	var httpClient: HTTPClientMock?
	var client: DefaultClient?

	override func setUp() {
		httpClient = HTTPClientMock()
		do {
			let clientConfig = ClientConfig(
				apiKey: "test", application: "test_app", endpoint: "https://test.absmartly.io/v1", environment: "test")
			client = try DefaultClient(config: clientConfig, httpClient: httpClient!)
		} catch {
			XCTFail(error.localizedDescription)
		}
	}

	func testGetContextData() {
		guard let client = client, let httpClient = httpClient else { return }

		let (promise, resolver) = Promise<Response>.pending()
		httpClient.getUrlQueryHeadersReturnValue = promise

		let expectation = XCTestExpectation()

		let result = client.getContextData()
		XCTAssertNotNil(result)
		XCTAssertEqual(1, httpClient.getUrlQueryHeadersCallsCount)
		XCTAssertEqual("https://test.absmartly.io/v1/context", httpClient.getUrlQueryHeadersReceivedArguments?.url)
		XCTAssertEqual(
			["environment": "test", "application": "test_app"], httpClient.getUrlQueryHeadersReceivedArguments?.query)
		XCTAssertNil(httpClient.getUrlQueryHeadersReceivedArguments?.headers)

		result.done { data in
			expectation.fulfill()
		}.catch { error in
			XCTFail(error.localizedDescription)
		}

		let path = Bundle.module.path(forResource: "context", ofType: "json", inDirectory: "Resources")!
		do {
			let data = try Foundation.Data(contentsOf: URL(fileURLWithPath: path), options: .mappedIfSafe)
			let response = DefaultHTTPResponse(
				status: 200, statusMessage: "OK", contentType: "application/json; charset=utf-8", content: data)
			resolver.fulfill(response)
		} catch {
			XCTFail(error.localizedDescription)
		}
	}

	func testClose() {
		guard let client = client, let httpClient = httpClient else { return }

		let (promise, resolver) = Promise<Void>.pending()
		httpClient.closeReturnValue = promise

		let expectation = XCTestExpectation()

		let result = client.close()

		result.done { data in
			expectation.fulfill()
		}.catch { error in
			XCTFail(error.localizedDescription)
		}

		XCTAssertEqual(1, httpClient.closeCallsCount)
		resolver.fulfill(())
	}
}
