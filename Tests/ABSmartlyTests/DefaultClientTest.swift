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

	func testThrowsWithMissingEndpoint() {
		let clientConfig = ClientConfig(
			apiKey: "test", application: "test_app", endpoint: "", environment: "test")
		XCTAssertThrowsError(try DefaultClient(config: clientConfig, httpClient: HTTPClientMock())) { error in
			XCTAssertEqual(error.localizedDescription, "Missing Endpoint configuration")
		}
	}

	func testThrowsWithMissingApiKey() {
		let clientConfig = ClientConfig(
			apiKey: "", application: "test_app", endpoint: "https://test.absmartly.io/v1", environment: "test")
		XCTAssertThrowsError(try DefaultClient(config: clientConfig, httpClient: HTTPClientMock())) { error in
			XCTAssertEqual(error.localizedDescription, "Missing APIKey configuration")
		}
	}

	func testThrowsWithMissingApplication() {
		let clientConfig = ClientConfig(
			apiKey: "test", application: "", endpoint: "https://test.absmartly.io/v1", environment: "test")
		XCTAssertThrowsError(try DefaultClient(config: clientConfig, httpClient: HTTPClientMock())) { error in
			XCTAssertEqual(error.localizedDescription, "Missing Application configuration")
		}
	}

	func testThrowsWithMissingEnvironment() {
		let clientConfig = ClientConfig(
			apiKey: "test", application: "test_app", endpoint: "https://test.absmartly.io/v1", environment: "")
		XCTAssertThrowsError(try DefaultClient(config: clientConfig, httpClient: HTTPClientMock())) { error in
			XCTAssertEqual(error.localizedDescription, "Missing Environment configuration")
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

		let path = TestResources.path(forResource: "context", ofType: "json")
		do {
			let data = try Foundation.Data(contentsOf: URL(fileURLWithPath: path), options: .mappedIfSafe)
			let response = DefaultHTTPResponse(
				status: 200, statusMessage: "OK", contentType: "application/json; charset=utf-8", content: data)
			resolver.fulfill(response)
		} catch {
			XCTFail(error.localizedDescription)
		}
	}

	func testGetContextDataRejectsOnHttpError() {
		guard let client = client, let httpClient = httpClient else { return }

		let (promise, resolver) = Promise<Response>.pending()
		httpClient.getUrlQueryHeadersReturnValue = promise

		let expectation = XCTestExpectation()

		let result = client.getContextData()

		result.done { _ in
			XCTFail("Expected rejection")
		}.catch { error in
			XCTAssertTrue(error is ABSmartlyHTTPError)
			let httpError = error as! ABSmartlyHTTPError
			XCTAssertEqual(500, httpError.statusCode)
			expectation.fulfill()
		}

		let response = DefaultHTTPResponse(
			status: 500, statusMessage: "Internal Server Error", contentType: "text/plain", content: Data())
		resolver.fulfill(response)

		wait(for: [expectation], timeout: 1.0)
	}

	func testGetContextDataRejectsOnNetworkError() {
		guard let client = client, let httpClient = httpClient else { return }

		let (promise, resolver) = Promise<Response>.pending()
		httpClient.getUrlQueryHeadersReturnValue = promise

		let expectation = XCTestExpectation()

		let result = client.getContextData()

		result.done { _ in
			XCTFail("Expected rejection")
		}.catch { error in
			XCTAssertTrue(error is ABSmartlyError)
			expectation.fulfill()
		}

		resolver.reject(ABSmartlyError("Connection refused"))

		wait(for: [expectation], timeout: 1.0)
	}

	func testGetContextDataRejectsOnMalformedResponse() {
		guard let client = client, let httpClient = httpClient else { return }

		let (promise, resolver) = Promise<Response>.pending()
		httpClient.getUrlQueryHeadersReturnValue = promise

		let expectation = XCTestExpectation()

		let result = client.getContextData()

		result.done { _ in
			XCTFail("Expected rejection")
		}.catch { error in
			XCTAssertTrue(error is DecodingError)
			expectation.fulfill()
		}

		let malformedData = "not valid json".data(using: .utf8)!
		let response = DefaultHTTPResponse(
			status: 200, statusMessage: "OK", contentType: "application/json", content: malformedData)
		resolver.fulfill(response)

		wait(for: [expectation], timeout: 1.0)
	}

	func testPublishCallsEndpoint() {
		guard let client = client, let httpClient = httpClient else { return }

		let (promise, resolver) = Promise<Response>.pending()
		httpClient.putUrlQueryHeadersBodyReturnValue = promise

		let expectation = XCTestExpectation()

		let event = PublishEvent()
		event.hashed = true
		event.units = [Unit(type: "session_id", uid: "abc123")]
		event.publishedAt = 1_620_000_000_000

		let result = client.publish(event: event)

		result.done {
			expectation.fulfill()
		}.catch { error in
			XCTFail(error.localizedDescription)
		}

		XCTAssertEqual(1, httpClient.putUrlQueryHeadersBodyCallsCount)
		XCTAssertEqual("https://test.absmartly.io/v1/context", httpClient.putUrlQueryHeadersBodyReceivedArguments?.url)
		XCTAssertNil(httpClient.putUrlQueryHeadersBodyReceivedArguments?.query)

		let headers = httpClient.putUrlQueryHeadersBodyReceivedArguments?.headers
		XCTAssertNotNil(headers)
		XCTAssertEqual("application/json; charset=utf-8", headers?["Content-Type"])
		XCTAssertEqual("test", headers?["X-API-Key"])
		XCTAssertEqual("test", headers?["X-Environment"])
		XCTAssertEqual("test_app", headers?["X-Application"])
		XCTAssertEqual("absmartly-swift-sdk", headers?["X-Agent"])

		XCTAssertNotNil(httpClient.putUrlQueryHeadersBodyReceivedArguments?.body)

		let response = DefaultHTTPResponse(
			status: 200, statusMessage: "OK", contentType: "application/json", content: Data())
		resolver.fulfill(response)

		wait(for: [expectation], timeout: 1.0)
	}

	func testPublishSendsCorrectBody() {
		guard let client = client, let httpClient = httpClient else { return }

		let (promise, resolver) = Promise<Response>.pending()
		httpClient.putUrlQueryHeadersBodyReturnValue = promise

		let expectation = XCTestExpectation()

		let event = PublishEvent()
		event.hashed = true
		event.units = [Unit(type: "session_id", uid: "abc123")]
		event.publishedAt = 1_620_000_000_000
		event.exposures = [
			Exposure(1, "exp_test", "session_id", 1, 1_620_000_000_000, true, true, false, false, false, false)
		]
		event.goals = [
			GoalAchievement("goal1", achievedAt: 1_620_000_000_000, properties: ["amount": 100])
		]

		let result = client.publish(event: event)

		result.done {
			expectation.fulfill()
		}.catch { error in
			XCTFail(error.localizedDescription)
		}

		let body = httpClient.putUrlQueryHeadersBodyReceivedArguments?.body
		XCTAssertNotNil(body)

		if let body = body, let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any] {
			XCTAssertEqual(true, json["hashed"] as? Bool)
			XCTAssertEqual(1_620_000_000_000, json["publishedAt"] as? Int64)
			XCTAssertNotNil(json["units"])
			XCTAssertNotNil(json["exposures"])
			XCTAssertNotNil(json["goals"])
		}

		let response = DefaultHTTPResponse(
			status: 200, statusMessage: "OK", contentType: "application/json", content: Data())
		resolver.fulfill(response)

		wait(for: [expectation], timeout: 1.0)
	}

	func testPublishOmitsEmptyArrays() {
		guard let client = client, let httpClient = httpClient else { return }

		let (promise, resolver) = Promise<Response>.pending()
		httpClient.putUrlQueryHeadersBodyReturnValue = promise

		let expectation = XCTestExpectation()

		let event = PublishEvent()
		event.hashed = true
		event.units = [Unit(type: "session_id", uid: "abc123")]
		event.publishedAt = 1_620_000_000_000

		let result = client.publish(event: event)

		result.done {
			expectation.fulfill()
		}.catch { error in
			XCTFail(error.localizedDescription)
		}

		let body = httpClient.putUrlQueryHeadersBodyReceivedArguments?.body
		XCTAssertNotNil(body)

		if let body = body, let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any] {
			XCTAssertNil(json["exposures"])
			XCTAssertNil(json["goals"])
			XCTAssertNil(json["attributes"])
		}

		let response = DefaultHTTPResponse(
			status: 200, statusMessage: "OK", contentType: "application/json", content: Data())
		resolver.fulfill(response)

		wait(for: [expectation], timeout: 1.0)
	}

	func testPublishRejectsOnHttpError() {
		guard let client = client, let httpClient = httpClient else { return }

		let (promise, resolver) = Promise<Response>.pending()
		httpClient.putUrlQueryHeadersBodyReturnValue = promise

		let expectation = XCTestExpectation()

		let event = PublishEvent()
		event.hashed = true
		event.units = [Unit(type: "session_id", uid: "abc123")]
		event.publishedAt = 1_620_000_000_000

		let result = client.publish(event: event)

		result.done {
			XCTFail("Expected rejection")
		}.catch { error in
			XCTAssertTrue(error is ABSmartlyHTTPError)
			let httpError = error as! ABSmartlyHTTPError
			XCTAssertEqual(500, httpError.statusCode)
			expectation.fulfill()
		}

		let response = DefaultHTTPResponse(
			status: 500, statusMessage: "Internal Server Error", contentType: "text/plain", content: Data())
		resolver.fulfill(response)

		wait(for: [expectation], timeout: 1.0)
	}

	func testPublishRejectsOnNetworkError() {
		guard let client = client, let httpClient = httpClient else { return }

		let (promise, resolver) = Promise<Response>.pending()
		httpClient.putUrlQueryHeadersBodyReturnValue = promise

		let expectation = XCTestExpectation()

		let event = PublishEvent()
		event.hashed = true
		event.units = [Unit(type: "session_id", uid: "abc123")]
		event.publishedAt = 1_620_000_000_000

		let result = client.publish(event: event)

		result.done {
			XCTFail("Expected rejection")
		}.catch { error in
			XCTAssertTrue(error is ABSmartlyError)
			expectation.fulfill()
		}

		resolver.reject(ABSmartlyError("Connection refused"))

		wait(for: [expectation], timeout: 1.0)
	}

	func testPublishRejectsOnClientError() {
		guard let client = client, let httpClient = httpClient else { return }

		let (promise, resolver) = Promise<Response>.pending()
		httpClient.putUrlQueryHeadersBodyReturnValue = promise

		let expectation = XCTestExpectation()

		let event = PublishEvent()
		event.hashed = true
		event.units = [Unit(type: "session_id", uid: "abc123")]
		event.publishedAt = 1_620_000_000_000

		let result = client.publish(event: event)

		result.done {
			XCTFail("Expected rejection")
		}.catch { error in
			XCTAssertTrue(error is ABSmartlyHTTPError)
			let httpError = error as! ABSmartlyHTTPError
			XCTAssertEqual(400, httpError.statusCode)
			expectation.fulfill()
		}

		let response = DefaultHTTPResponse(
			status: 400, statusMessage: "Bad Request", contentType: "text/plain", content: Data())
		resolver.fulfill(response)

		wait(for: [expectation], timeout: 1.0)
	}

	func testPublishSetsApplicationVersionHeader() throws {
		let httpMock = HTTPClientMock()
		let clientConfig = ClientConfig(
			apiKey: "test", application: "test_app", endpoint: "https://test.absmartly.io/v1",
			environment: "test",
			applicationVersion: "1.2.3")
		let versionClient = try DefaultClient(config: clientConfig, httpClient: httpMock)

		let (promise, resolver) = Promise<Response>.pending()
		httpMock.putUrlQueryHeadersBodyReturnValue = promise

		let expectation = XCTestExpectation()

		let event = PublishEvent()
		event.hashed = true
		event.units = [Unit(type: "session_id", uid: "abc123")]
		event.publishedAt = 1_620_000_000_000

		let result = versionClient.publish(event: event)

		result.done {
			expectation.fulfill()
		}.catch { error in
			XCTFail(error.localizedDescription)
		}

		let headers = httpMock.putUrlQueryHeadersBodyReceivedArguments?.headers
		XCTAssertEqual("1.2.3", headers?["X-Application-Version"])

		let response = DefaultHTTPResponse(
			status: 200, statusMessage: "OK", contentType: "application/json", content: Data())
		resolver.fulfill(response)

		wait(for: [expectation], timeout: 1.0)
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

	func testGetContextDataSetsCorrectQueryParameters() {
		guard let client = client, let httpClient = httpClient else { return }

		let (promise, _) = Promise<Response>.pending()
		httpClient.getUrlQueryHeadersReturnValue = promise

		_ = client.getContextData()

		let query = httpClient.getUrlQueryHeadersReceivedArguments?.query
		XCTAssertEqual("test_app", query?["application"])
		XCTAssertEqual("test", query?["environment"])
		XCTAssertEqual(2, query?.count)
	}

	func testGetContextDataDoesNotSendHeaders() {
		guard let client = client, let httpClient = httpClient else { return }

		let (promise, _) = Promise<Response>.pending()
		httpClient.getUrlQueryHeadersReturnValue = promise

		_ = client.getContextData()

		XCTAssertNil(httpClient.getUrlQueryHeadersReceivedArguments?.headers)
	}

	func testConstructorAcceptsValidConfig() throws {
		let clientConfig = ClientConfig(
			apiKey: "my-key", application: "my-app", endpoint: "https://example.com/v1", environment: "production")
		let validClient = try DefaultClient(config: clientConfig, httpClient: HTTPClientMock())
		XCTAssertNotNil(validClient)
	}

	func testMultipleGetContextDataCalls() {
		guard let client = client, let httpClient = httpClient else { return }

		let (promise1, _) = Promise<Response>.pending()
		let (promise2, _) = Promise<Response>.pending()

		httpClient.getUrlQueryHeadersReturnValue = promise1
		_ = client.getContextData()

		httpClient.getUrlQueryHeadersReturnValue = promise2
		_ = client.getContextData()

		XCTAssertEqual(2, httpClient.getUrlQueryHeadersCallsCount)
	}

	func testMultiplePublishCalls() {
		guard let client = client, let httpClient = httpClient else { return }

		let (promise1, _) = Promise<Response>.pending()
		let (promise2, _) = Promise<Response>.pending()

		let event1 = PublishEvent()
		event1.hashed = true
		event1.units = [Unit(type: "session_id", uid: "abc123")]
		event1.publishedAt = 1_620_000_000_000

		let event2 = PublishEvent()
		event2.hashed = true
		event2.units = [Unit(type: "user_id", uid: "user456")]
		event2.publishedAt = 1_620_000_001_000

		httpClient.putUrlQueryHeadersBodyReturnValue = promise1
		_ = client.publish(event: event1)

		httpClient.putUrlQueryHeadersBodyReturnValue = promise2
		_ = client.publish(event: event2)

		XCTAssertEqual(2, httpClient.putUrlQueryHeadersBodyCallsCount)
	}

	func testGetContextDataRejectsOn404() {
		guard let client = client, let httpClient = httpClient else { return }

		let (promise, resolver) = Promise<Response>.pending()
		httpClient.getUrlQueryHeadersReturnValue = promise

		let expectation = XCTestExpectation()

		let result = client.getContextData()

		result.done { _ in
			XCTFail("Expected rejection")
		}.catch { error in
			XCTAssertTrue(error is ABSmartlyHTTPError)
			let httpError = error as! ABSmartlyHTTPError
			XCTAssertEqual(404, httpError.statusCode)
			expectation.fulfill()
		}

		let response = DefaultHTTPResponse(
			status: 404, statusMessage: "Not Found", contentType: "text/plain", content: Data())
		resolver.fulfill(response)

		wait(for: [expectation], timeout: 1.0)
	}

	func testPublishRejectsOn401() {
		guard let client = client, let httpClient = httpClient else { return }

		let (promise, resolver) = Promise<Response>.pending()
		httpClient.putUrlQueryHeadersBodyReturnValue = promise

		let expectation = XCTestExpectation()

		let event = PublishEvent()
		event.hashed = true
		event.units = [Unit(type: "session_id", uid: "abc123")]
		event.publishedAt = 1_620_000_000_000

		let result = client.publish(event: event)

		result.done {
			XCTFail("Expected rejection")
		}.catch { error in
			XCTAssertTrue(error is ABSmartlyHTTPError)
			let httpError = error as! ABSmartlyHTTPError
			XCTAssertEqual(401, httpError.statusCode)
			expectation.fulfill()
		}

		let response = DefaultHTTPResponse(
			status: 401, statusMessage: "Unauthorized", contentType: "text/plain", content: Data())
		resolver.fulfill(response)

		wait(for: [expectation], timeout: 1.0)
	}
}
