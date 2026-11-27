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
			XCTFail(error.safeLocalizedDescription)
		}
	}

	func testClientConfigPropertiesAreSettable() throws {
		let clientConfig = ClientConfig()
		clientConfig.apiKey = "test"
		clientConfig.application = "test_app"
		clientConfig.endpoint = "https://test.absmartly.io/v1"
		clientConfig.environment = "test"
		clientConfig.applicationVersion = "2"

		XCTAssertEqual("test", clientConfig.apiKey)
		XCTAssertEqual("test_app", clientConfig.application)
		XCTAssertEqual("https://test.absmartly.io/v1", clientConfig.endpoint)
		XCTAssertEqual("test", clientConfig.environment)
		XCTAssertEqual("2", clientConfig.applicationVersion)
		XCTAssertNoThrow(try DefaultClient(config: clientConfig, httpClient: HTTPClientMock()))
	}

	func testGetApplicationAndEnvironmentReturnConfiguredNames() throws {
		let clientConfig = ClientConfig(
			apiKey: "test", application: "website", endpoint: "https://test.absmartly.io/v1",
			environment: "production")
		let client = try DefaultClient(config: clientConfig, httpClient: HTTPClientMock())

		XCTAssertEqual("website", client.getApplication())
		XCTAssertEqual("production", client.getEnvironment())

		// Captured at init, like the HTTP metadata: mutating the config afterwards does not change
		// the names audiences evaluate against, so evaluation stays consistent with context fetches.
		clientConfig.application = "mobile"
		clientConfig.environment = "staging"
		XCTAssertEqual("website", client.getApplication())
		XCTAssertEqual("production", client.getEnvironment())
	}

	func testThrowsWithMissingEndpoint() {
		let clientConfig = ClientConfig(
			apiKey: "test", application: "test_app", endpoint: "", environment: "test")
		XCTAssertThrowsError(try DefaultClient(config: clientConfig, httpClient: HTTPClientMock())) { error in
			XCTAssertEqual(error.safeLocalizedDescription, "Missing Endpoint configuration")
		}
	}

	func testThrowsWithMissingApiKey() {
		let clientConfig = ClientConfig(
			apiKey: "", application: "test_app", endpoint: "https://test.absmartly.io/v1", environment: "test")
		XCTAssertThrowsError(try DefaultClient(config: clientConfig, httpClient: HTTPClientMock())) { error in
			XCTAssertEqual(error.safeLocalizedDescription, "Missing APIKey configuration")
		}
	}

	func testThrowsWithMissingApplication() {
		let clientConfig = ClientConfig(
			apiKey: "test", application: "", endpoint: "https://test.absmartly.io/v1", environment: "test")
		XCTAssertThrowsError(try DefaultClient(config: clientConfig, httpClient: HTTPClientMock())) { error in
			XCTAssertEqual(error.safeLocalizedDescription, "Missing Application configuration")
		}
	}

	func testThrowsWithMissingEnvironment() {
		let clientConfig = ClientConfig(
			apiKey: "test", application: "test_app", endpoint: "https://test.absmartly.io/v1", environment: "")
		XCTAssertThrowsError(try DefaultClient(config: clientConfig, httpClient: HTTPClientMock())) { error in
			XCTAssertEqual(error.safeLocalizedDescription, "Missing Environment configuration")
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
		XCTAssertNotNil(httpClient.getUrlQueryHeadersReceivedArguments?.headers)

		result.done { data in
			expectation.fulfill()
		}.catch { error in
			XCTFail(error.safeLocalizedDescription)
		}

		let path = TestResources.path(forResource: "context", ofType: "json")
		do {
			let data = try Foundation.Data(contentsOf: URL(fileURLWithPath: path), options: .mappedIfSafe)
			let response = DefaultHTTPResponse(
				status: 200, statusMessage: "OK", contentType: "application/json; charset=utf-8", content: data)
			resolver.fulfill(response)
		} catch {
			XCTFail(error.safeLocalizedDescription)
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
			XCTFail(error.safeLocalizedDescription)
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
		XCTAssertEqual("absmartly-swift-sdk/\(SDKVersion.version)", headers?["X-Agent"])

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
			XCTFail(error.safeLocalizedDescription)
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
			XCTFail(error.safeLocalizedDescription)
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
			applicationVersion: "1002003")
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
			XCTFail(error.safeLocalizedDescription)
		}

		let headers = httpMock.putUrlQueryHeadersBodyReceivedArguments?.headers
		XCTAssertEqual("1002003", headers?["X-Application-Version"])

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
			XCTFail(error.safeLocalizedDescription)
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

	// Cross-SDK scenario 320: the context GET carries the same SDK headers as the publish PUT
	// (as javascript-sdk sends on every request), including X-Agent absmartly-<lang>-sdk/<semver>.
	func testGetContextDataSendsSameHeadersAsPublish() throws {
		let httpMock = HTTPClientMock()
		let clientConfig = ClientConfig(
			apiKey: "test-key",
			application: "website",
			endpoint: "https://test.absmartly.io/v1",
			environment: "production",
			applicationVersion: "1004")
		let headerClient = try DefaultClient(config: clientConfig, httpClient: httpMock)

		let (getPromise, _) = Promise<Response>.pending()
		httpMock.getUrlQueryHeadersReturnValue = getPromise
		let (putPromise, _) = Promise<Response>.pending()
		httpMock.putUrlQueryHeadersBodyReturnValue = putPromise

		_ = headerClient.getContextData()
		_ = headerClient.publish(event: PublishEvent())

		XCTAssertEqual(1, httpMock.getUrlQueryHeadersCallsCount)
		XCTAssertEqual(
			["application": "website", "environment": "production"],
			httpMock.getUrlQueryHeadersReceivedArguments?.query)

		let headers = try XCTUnwrap(httpMock.getUrlQueryHeadersReceivedArguments?.headers)
		XCTAssertEqual("application/json; charset=utf-8", headers["Content-Type"])
		XCTAssertEqual("test-key", headers["X-API-Key"])
		XCTAssertEqual("production", headers["X-Environment"])
		XCTAssertEqual("website", headers["X-Application"])
		XCTAssertEqual("1004", headers["X-Application-Version"])
		let agent = try XCTUnwrap(headers["X-Agent"])
		XCTAssertNotNil(
			agent.range(
				of: "^absmartly-[a-z0-9]+-sdk/[0-9]+\\.[0-9]+\\.[0-9]+([-+][0-9A-Za-z.+-]*)?$",
				options: .regularExpression),
			agent)
		XCTAssertEqual(httpMock.putUrlQueryHeadersBodyReceivedArguments?.headers, headers)
	}

	// The collector binds X-Application-Version as a Long and rejects anything else with HTTP 400, so
	// only the wire value is normalised (like the Java SDK): trimmed, 1–18 ASCII digits pass, anything
	// else is sent as "0". Both the context GET and the publish PUT carry the normalised value.
	func testApplicationVersionHeaderIsNormalisedOnGetAndPut() throws {
		let cases: [(String, String)] = [
			("1004", "1004"),
			(" 1004 ", "1004"),
			("\t1004\n", "1004"),
			("0", "0"),
			("007", "007"),
			("1.2.3", "0"),
			("2.4.1", "0"),
			("", "0"),
			("   ", "0"),
			("-1", "0"),
			("+1", "0"),
			("1e3", "0"),
			("\u{0661}\u{0662}", "0"),
			("\u{FF11}\u{FF12}", "0"),
			(String(repeating: "9", count: 18), String(repeating: "9", count: 18)),
			(String(repeating: "9", count: 19), "0"),
		]

		for (configured, expected) in cases {
			let httpMock = HTTPClientMock()
			let clientConfig = ClientConfig(
				apiKey: "test-key", application: "website", endpoint: "https://test.absmartly.io/v1",
				environment: "production", applicationVersion: configured)
			let headerClient = try DefaultClient(config: clientConfig, httpClient: httpMock)

			let (getPromise, _) = Promise<Response>.pending()
			httpMock.getUrlQueryHeadersReturnValue = getPromise
			let (putPromise, _) = Promise<Response>.pending()
			httpMock.putUrlQueryHeadersBodyReturnValue = putPromise

			_ = headerClient.getContextData()
			_ = headerClient.publish(event: PublishEvent())

			XCTAssertEqual(
				expected, httpMock.getUrlQueryHeadersReceivedArguments?.headers?["X-Application-Version"],
				"GET for \(configured.debugDescription)")
			XCTAssertEqual(
				expected, httpMock.putUrlQueryHeadersBodyReceivedArguments?.headers?["X-Application-Version"],
				"PUT for \(configured.debugDescription)")
			XCTAssertEqual(configured, clientConfig.applicationVersion)
		}
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

	func testSDKVersionMatchesPodspec() throws {
		let root = ((#filePath as NSString).deletingLastPathComponent as NSString)
			.deletingLastPathComponent as NSString
		let podspec = try String(
			contentsOfFile: (root.deletingLastPathComponent as NSString).appendingPathComponent(
				"ABSmartlySwiftSDK.podspec"), encoding: .utf8)
		XCTAssertTrue(podspec.contains("spec.version = '\(SDKVersion.version)'"))
		XCTAssertEqual("absmartly-swift-sdk/\(SDKVersion.version)", SDKVersion.agent)
	}

	// The client decodes through ContextData.decode(from:), so a switchback's cluster map keeps its JSON
	// key order (a plain JSONDecoder cannot see it and drops a multi-entry map).
	func testGetContextDataKeepsSwitchbackClusterOrder() throws {
		let (promise, resolver) = Promise<Response>.pending()
		httpClient!.getUrlQueryHeadersReturnValue = promise
		let result = client!.getContextData()
		let payload = SB.json([
			SB.switchback(arms: 2, periodMs: SB.hour, clusters: [("z_type", "a"), ("a_type", "b"), ("m_type", "c")])
		])
		resolver.fulfill(
			DefaultHTTPResponse(status: 200, statusMessage: "OK", contentType: "application/json", content: payload))
		let data = try result.wait()
		XCTAssertEqual(["z_type", "a_type", "m_type"], data.experiments[0].switchbackClusters?.map { $0.unitType })
	}

	// A request the HTTP client cancels must still reject the client's promise; PromiseKit's default
	// catch policy would skip the cancellation and leave it pending forever.
	func testCancelledRequestsRejectGetContextDataAndPublish() throws {
		let http = HTTPClientMock()
		http.getUrlQueryHeadersReturnValue = Promise(error: PMKError.cancelled)
		http.putUrlQueryHeadersBodyReturnValue = Promise(error: PMKError.cancelled)
		let client = try DefaultClient(
			config: ClientConfig(apiKey: "k", application: "a", endpoint: "https://e.test", environment: "p"),
			httpClient: http)

		let fetchRejected = expectation(description: "getContextData rejects")
		client.getContextData().catch(policy: .allErrors) { error in
			XCTAssertTrue(error.isCancelled)
			fetchRejected.fulfill()
		}
		let publishRejected = expectation(description: "publish rejects")
		client.publish(event: PublishEvent()).catch(policy: .allErrors) { error in
			XCTAssertTrue(error.isCancelled)
			publishRejected.fulfill()
		}
		wait(for: [fetchRejected, publishRejected], timeout: 2)
	}
}
