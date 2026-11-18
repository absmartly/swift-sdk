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

	// As in v1.4.0, a request keeps its client alive until it settles: dropping the clients while a
	// request is retrying still settles DefaultClient's Promise (here with a connection error)
	// instead of leaving it pending forever.
	func testRequestSettlesAfterCallerDropsTheClient() throws {
		let config = DefaultHTTPClientConfig()
		config.retries = 2
		config.retryInterval = 0.2
		config.connectionRequestTimeout = 1.0
		let clientConfig = ClientConfig(
			apiKey: "k", application: "a", endpoint: "http://127.0.0.1:9", environment: "e")
		var client: DefaultClient? = try DefaultClient(
			config: clientConfig, httpClient: DefaultHTTPClient(config: config))

		let settled = XCTestExpectation(description: "request settles")
		_ = client!.getContextData().ensure { settled.fulfill() }
		client = nil

		wait(for: [settled], timeout: 10.0)
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
				if let urlError = error as? URLError {
					XCTAssertTrue([.badURL, .unsupportedURL].contains(urlError.code), "unexpected code \(urlError.code)")
				} else {
					XCTAssertNotNil(error)
				}
				expectation.fulfill()
			}

		wait(for: [expectation], timeout: 5.0)

		_ = httpClient.close()
	}

	// As in v1.4.0, close() resolves without invalidating the session: a later request still works.
	func testCloseKeepsTheSessionUsable() throws {
		let config = DefaultHTTPClientConfig()
		config.retries = 0
		let httpClient = DefaultHTTPClient(config: config)
		let server = try LocalHTTPServer()
		server.getResponseBody = "ok"
		try server.start()
		defer { server.stop() }

		let closePromise = httpClient.close()

		let expectation = XCTestExpectation(description: "Close completes")

		_ = closePromise.done {
			expectation.fulfill()
		}

		wait(for: [expectation], timeout: 5.0)

		let requestExpectation = XCTestExpectation(description: "Request after close succeeds")

		_ = httpClient.get(url: "http://127.0.0.1:\(server.port)/context", query: nil, headers: nil)
			.done { response in
				XCTAssertEqual(200, response.status)
				XCTAssertEqual("ok", String(data: response.content, encoding: .utf8))
				requestExpectation.fulfill()
			}
			.catch { error in
				XCTFail("request after close failed: \(error)")
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
