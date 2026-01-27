import Foundation
import PromiseKit
import XCTest

@testable import ABSmartly

final class DefaultHTTPClientTest: XCTestCase {
	func testCreatable() throws {
		let config = DefaultHTTPClientConfig()
		config.retries = 4
		let httpClient = DefaultHTTPClient(config: config)
		_ = httpClient.close()
	}

	func testConnectionTimeout() throws {
		let config = DefaultHTTPClientConfig()
		config.connectionRequestTimeout = 0.001
		config.connectionResourceTimeout = 0.001
		config.retries = 0

		let httpClient = DefaultHTTPClient(config: config)

		let expectation = XCTestExpectation(description: "Request times out")

		_ = httpClient.get(url: "https://httpstat.us/200?sleep=5000", query: nil, headers: nil)
			.done { _ in
				XCTFail("Request should have timed out")
				expectation.fulfill()
			}
			.catch { error in
				XCTAssertTrue(error is URLError)
				if let urlError = error as? URLError {
					XCTAssertTrue(
						urlError.code == .timedOut || urlError.code == .networkConnectionLost || urlError.code == .notConnectedToInternet,
						"Expected timeout-related error, got: \(urlError.code)"
					)
				}
				expectation.fulfill()
			}

		wait(for: [expectation], timeout: 5.0)

		_ = httpClient.close()
	}

	func testReadTimeout() throws {
		let config = DefaultHTTPClientConfig()
		config.connectionResourceTimeout = 0.001
		config.retries = 0

		let httpClient = DefaultHTTPClient(config: config)

		let expectation = XCTestExpectation(description: "Read times out")

		_ = httpClient.get(url: "https://httpstat.us/200?sleep=10000", query: nil, headers: nil)
			.done { _ in
				XCTFail("Request should have timed out")
				expectation.fulfill()
			}
			.catch { error in
				XCTAssertNotNil(error)
				expectation.fulfill()
			}

		wait(for: [expectation], timeout: 5.0)

		_ = httpClient.close()
	}

	func testHTTPStatusCodes() throws {
		let config = DefaultHTTPClientConfig()
		config.retries = 0
		let httpClient = DefaultHTTPClient(config: config)

		let successExpectation = XCTestExpectation(description: "200 OK succeeds")

		_ = httpClient.get(url: "https://httpstat.us/200", query: nil, headers: nil)
			.done { response in
				XCTAssertEqual(200, response.status)
				successExpectation.fulfill()
			}
			.catch { _ in
				successExpectation.fulfill()
			}

		wait(for: [successExpectation], timeout: 10.0)

		_ = httpClient.close()
	}

	func testRetryOnTransientError() throws {
		let config = DefaultHTTPClientConfig()
		config.retries = 2
		config.retryInterval = 0.1
		let httpClient = DefaultHTTPClient(config: config)

		let expectation = XCTestExpectation(description: "Retry on 503")

		_ = httpClient.get(url: "https://httpstat.us/503", query: nil, headers: nil)
			.done { response in
				XCTAssertEqual(503, response.status)
				expectation.fulfill()
			}
			.catch { error in
				if let httpError = error as? ABSmartlyHTTPError {
					XCTAssertEqual(503, httpError.statusCode)
				}
				expectation.fulfill()
			}

		wait(for: [expectation], timeout: 15.0)

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

	func testGetRequest() throws {
		let config = DefaultHTTPClientConfig()
		config.retries = 0
		let httpClient = DefaultHTTPClient(config: config)

		let expectation = XCTestExpectation(description: "GET request completes")

		_ = httpClient.get(
			url: "https://httpstat.us/200",
			query: ["param1": "value1", "param2": "value2"],
			headers: ["Accept": "application/json"]
		)
		.done { response in
			XCTAssertEqual(200, response.status)
			expectation.fulfill()
		}
		.catch { _ in
			expectation.fulfill()
		}

		wait(for: [expectation], timeout: 10.0)

		_ = httpClient.close()
	}

	func testPostRequest() throws {
		let config = DefaultHTTPClientConfig()
		config.retries = 0
		let httpClient = DefaultHTTPClient(config: config)

		let expectation = XCTestExpectation(description: "POST request completes")

		let body = "{\"test\": \"data\"}".data(using: .utf8)

		_ = httpClient.post(
			url: "https://httpstat.us/200",
			query: nil,
			headers: ["Content-Type": "application/json"],
			body: body
		)
		.done { response in
			XCTAssertEqual(200, response.status)
			expectation.fulfill()
		}
		.catch { _ in
			expectation.fulfill()
		}

		wait(for: [expectation], timeout: 10.0)

		_ = httpClient.close()
	}

	func testPutRequest() throws {
		let config = DefaultHTTPClientConfig()
		config.retries = 0
		let httpClient = DefaultHTTPClient(config: config)

		let expectation = XCTestExpectation(description: "PUT request completes")

		let body = "{\"update\": \"data\"}".data(using: .utf8)

		_ = httpClient.put(
			url: "https://httpstat.us/200",
			query: nil,
			headers: ["Content-Type": "application/json"],
			body: body
		)
		.done { response in
			XCTAssertEqual(200, response.status)
			expectation.fulfill()
		}
		.catch { _ in
			expectation.fulfill()
		}

		wait(for: [expectation], timeout: 10.0)

		_ = httpClient.close()
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

		_ = httpClient.get(url: "https://httpstat.us/200", query: nil, headers: nil)
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
}
