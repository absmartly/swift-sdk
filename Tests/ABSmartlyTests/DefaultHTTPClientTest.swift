import Foundation
import PromiseKit
import XCTest

@testable import ABSmartly

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

private class MockURLProtocol: URLProtocol {
	static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

	override class func canInit(with request: URLRequest) -> Bool {
		return true
	}

	override class func canonicalRequest(for request: URLRequest) -> URLRequest {
		return request
	}

	override func startLoading() {
		guard let handler = MockURLProtocol.requestHandler else {
			client?.urlProtocol(self, didFailWithError: URLError(.unknown))
			return
		}

		do {
			let (response, data) = try handler(request)
			client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
			client?.urlProtocol(self, didLoad: data)
			client?.urlProtocolDidFinishLoading(self)
		} catch {
			client?.urlProtocol(self, didFailWithError: error)
		}
	}

	override func stopLoading() {}
}

final class DefaultHTTPClientTest: XCTestCase {
	func testCreatable() throws {
		let config = DefaultHTTPClientConfig()
		config.retries = 4
		let httpClient = DefaultHTTPClient(config: config)
		_ = httpClient.close()
	}

	func testURLSessionConfiguration() throws {
		let config = DefaultHTTPClientConfig()
		config.connectionRequestTimeout = 30.0
		config.connectionResourceTimeout = 60.0
		config.retries = 3
		config.retryInterval = 1.0

		let httpClient = DefaultHTTPClient(config: config)

		XCTAssertNotNil(httpClient)

		_ = httpClient.close()
	}

	func testDefaultHTTPResponse() throws {
		let response = DefaultHTTPResponse(
			status: 200,
			statusMessage: "OK",
			contentType: "application/json",
			content: "{\"key\": \"value\"}".data(using: .utf8)!
		)

		XCTAssertEqual(200, response.status)
		XCTAssertEqual("OK", response.statusMessage)
		XCTAssertEqual("application/json", response.contentType)
		XCTAssertNotNil(response.content)
	}

	func testBadURL() throws {
		let config = DefaultHTTPClientConfig()
		config.retries = 0
		let httpClient = DefaultHTTPClient(config: config)

		let expectation = XCTestExpectation(description: "Bad URL fails")

		_ = httpClient.get(url: "not-a-valid-url", query: nil, headers: nil)
			.done { _ in
				XCTFail("Request should have failed with bad URL")
				expectation.fulfill()
			}
			.catch { error in
				XCTAssertNotNil(error)
				expectation.fulfill()
			}

		wait(for: [expectation], timeout: 5.0)

		_ = httpClient.close()
	}

	func testCloseInvalidatesSession() throws {
		let config = DefaultHTTPClientConfig()
		let httpClient = DefaultHTTPClient(config: config)

		let closePromise = httpClient.close()

		let expectation = XCTestExpectation(description: "Close completes")

		_ = closePromise.done {
			expectation.fulfill()
		}

		wait(for: [expectation], timeout: 5.0)

		let requestExpectation = XCTestExpectation(description: "Request after close fails")

		_ = httpClient.get(url: "https://example.test/200", query: nil, headers: nil)
			.done { _ in
				XCTFail("Request should fail after close")
				requestExpectation.fulfill()
			}
			.catch { error in
				XCTAssertNotNil(error)
				requestExpectation.fulfill()
			}

		wait(for: [requestExpectation], timeout: 5.0)
	}

	func testRetryStaticMethod() throws {
		var attempts: UInt = 0
		let expectation = XCTestExpectation(description: "Retry completes")

		_ = DefaultHTTPClient.retry(times: 3, delay: 0.01) { attempt -> Promise<String> in
			attempts = attempt
			if attempt < 3 {
				return Promise(error: ABSmartlyError("transient"))
			}
			return Promise.value("success")
		}.done { value in
			XCTAssertEqual("success", value)
			XCTAssertEqual(3, attempts)
			expectation.fulfill()
		}.catch { _ in
			XCTFail("Should have succeeded after retries")
			expectation.fulfill()
		}

		wait(for: [expectation], timeout: 5.0)
	}
}
