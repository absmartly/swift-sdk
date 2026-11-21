import Foundation
import PromiseKit
import XCTest

@testable import ABSmartly
import ABSmartlyAsync

@available(iOS 13, macOS 10.15, tvOS 13, watchOS 6, *)
final class AsyncAPITest: XCTestCase {
	var provider = ContextDataProviderMock()
	var handler = ContextEventHandlerMock()
	var scheduler = SchedulerMock()
	let clock = FixedClock(1_620_000_000_000)

	override func setUp() {
		provider = ContextDataProviderMock()
		handler = ContextEventHandlerMock()
		scheduler = SchedulerMock()
		scheduler.scheduleAfterExecuteReturnValue = ScheduledHandleMock()
		scheduler.scheduleWithFixedDelayAfterRepeatingExecuteReturnValue = ScheduledHandleMock()
		// A default, so a misrouted call (e.g. publish() calling refresh()) fails an assertion on
		// the provider's call count instead of crashing the run in the mock.
		provider.getContextDataReturnValue = Promise(error: ABSmartlyError("unexpected fetch"))
	}

	private func contextData() throws -> ContextData {
		let path = TestResources.path(forResource: "context", ofType: "json")
		return try JSONDecoder().decode(ContextData.self, from: Data(contentsOf: URL(fileURLWithPath: path)))
	}

	private func makeContext(_ data: Promise<ContextData>) -> Context {
		let config = ContextConfig()
		config.setUnit(unitType: "session_id", uid: "e791e240fcd3df7d238cfc285f475e8152fcc0ec")
		return Context(
			config: config, clock: clock, scheduler: scheduler, handler: handler, provider: provider, logger: nil,
			parser: DefaultVariableParser(), matcher: AudienceMatcher(), promise: data)
	}

	func testWaitUntilReadyReturnsTheContextOnceLoaded() async throws {
		let (promise, resolver) = Promise<ContextData>.pending()
		let context = makeContext(promise)
		XCTAssertFalse(context.isReady())

		DispatchQueue.global().asyncAfter(deadline: .now() + 0.05) {
			resolver.fulfill(try! self.contextData())
		}
		let ready = try await context.waitUntilReady()

		XCTAssertTrue(ready === context)
		XCTAssertTrue(context.isReady())
		XCTAssertEqual(1, context.getTreatment("exp_test_ab"))
	}

	func testWaitUntilReadyDoesNotThrowForAFailedContext() async throws {
		let (promise, resolver) = Promise<ContextData>.pending()
		let context = makeContext(promise)
		resolver.reject(ABSmartlyError("load failed"))

		try await context.waitUntilReady()

		XCTAssertTrue(context.isFailed())
		XCTAssertEqual("load failed", (context.readyError() as? ABSmartlyError)?.errorMessage)
	}

	func testRefreshAwaitsTheFetch() async throws {
		let context = makeContext(Promise.value(try contextData()))
		provider.getContextDataReturnValue = Promise.value(try contextData(source: "refreshed"))
		handler.publishEventReturnValue = Promise.value(())
		context.track("goal1", properties: nil)

		try await context.refresh()

		XCTAssertEqual(1, provider.getContextDataCallsCount)
		XCTAssertTrue(context.getExperiments().contains("exp_test_new"))
		XCTAssertEqual(0, handler.publishEventCallsCount)
		XCTAssertFalse(context.isClosed())
	}

	func testRefreshThrowsTheFetchError() async throws {
		let context = makeContext(Promise.value(try contextData()))
		provider.getContextDataReturnValue = Promise(error: ABSmartlyError("refresh failed"))

		do {
			try await context.refresh()
			XCTFail("expected refresh to throw")
		} catch {
			XCTAssertEqual("refresh failed", (error as? ABSmartlyError)?.errorMessage)
		}
	}

	func testPublishSendsQueuedEvents() async throws {
		let context = makeContext(Promise.value(try contextData()))
		context.track("goal1", properties: nil)
		handler.publishEventReturnValue = Promise.value(())
		provider.getContextDataReturnValue = Promise.value(try contextData())

		try await context.publish()

		XCTAssertEqual(1, handler.publishEventCallsCount)
		XCTAssertEqual(0, context.getPendingCount())
		XCTAssertEqual(["goal1"], handler.publishEventReceivedEvent?.goals.map { $0.name })
		XCTAssertEqual(0, provider.getContextDataCallsCount)
	}

	func testOverloadsWaitForTheirPromise() async throws {
		let context = makeContext(Promise.value(try contextData()))
		let settled = ManagedFlag()

		context.track("goal1", properties: nil)
		let (publish, publishResolver) = Promise<Void>.pending()
		handler.publishEventReturnValue = publish
		DispatchQueue.global().asyncAfter(deadline: .now() + 0.1) {
			settled.set()
			publishResolver.fulfill(())
		}
		try await context.publish()
		XCTAssertTrue(settled.isSet)

		let refreshSettled = ManagedFlag()
		let (refresh, refreshResolver) = Promise<ContextData>.pending()
		provider.getContextDataReturnValue = refresh
		DispatchQueue.global().asyncAfter(deadline: .now() + 0.1) {
			refreshSettled.set()
			refreshResolver.fulfill(try! self.contextData())
		}
		try await context.refresh()
		XCTAssertTrue(refreshSettled.isSet)
		XCTAssertEqual(1, provider.getContextDataCallsCount)
		XCTAssertEqual(1, handler.publishEventCallsCount)
	}

	func testPublishThrowsThePublishError() async throws {
		let context = makeContext(Promise.value(try contextData()))
		context.track("goal1", properties: nil)
		handler.publishEventReturnValue = Promise(error: ABSmartlyError("publish failed"))

		do {
			try await context.publish()
			XCTFail("expected publish to throw")
		} catch {
			XCTAssertEqual("publish failed", (error as? ABSmartlyError)?.errorMessage)
		}
		XCTAssertEqual(1, context.getPendingCount())
	}

	func testCloseFlushesAndCloses() async throws {
		let context = makeContext(Promise.value(try contextData()))
		context.track("goal1", properties: nil)
		handler.publishEventReturnValue = Promise.value(())
		provider.getContextDataReturnValue = Promise.value(try contextData())

		try await context.close()

		XCTAssertTrue(context.isClosed())
		XCTAssertEqual(1, handler.publishEventCallsCount)
		XCTAssertEqual(0, provider.getContextDataCallsCount)
	}

	func testCloseThrowsWhenTheFinalPublishFails() async throws {
		let context = makeContext(Promise.value(try contextData()))
		context.track("goal1", properties: nil)
		handler.publishEventReturnValue = Promise(error: ABSmartlyError("publish failed"))

		do {
			try await context.close()
			XCTFail("expected close to throw")
		} catch {
			XCTAssertEqual("publish failed", (error as? ABSmartlyError)?.errorMessage)
		}
		XCTAssertFalse(context.isClosed())
	}

	func testFinalizeClosesTheContext() async throws {
		let context = makeContext(Promise.value(try contextData()))
		try await context.finalize()
		XCTAssertTrue(context.isFinalized())
	}

	func testCancellingTheTaskDoesNotCancelThePublish() async throws {
		let context = makeContext(Promise.value(try contextData()))
		context.track("goal1", properties: nil)
		let (publish, publishResolver) = Promise<Void>.pending()
		handler.publishEventReturnValue = publish

		let task = Task { try await context.publish() }
		task.cancel()
		DispatchQueue.global().asyncAfter(deadline: .now() + 0.05) { publishResolver.fulfill(()) }

		try await task.value
		XCTAssertEqual(1, handler.publishEventCallsCount)
		XCTAssertEqual(0, provider.getContextDataCallsCount)
		XCTAssertEqual(0, context.getPendingCount())
	}

	@MainActor
	func testCallableFromTheMainActor() async throws {
		let context = makeContext(Promise.value(try contextData()))
		handler.publishEventReturnValue = Promise.value(())
		provider.getContextDataReturnValue = Promise.value(try contextData())
		context.track("goal1", properties: nil)

		let ready = try await context.waitUntilReady()
		try await ready.publish()
		try await ready.refresh()
		try await ready.close()

		XCTAssertTrue(context.isClosed())
	}

	func testPromiseOverloadsStillResolveInAsyncCode() async throws {
		let context = makeContext(Promise.value(try contextData()))
		let promise: Promise<Context> = context.waitUntilReady()
		let ready = try await withCheckedThrowingContinuation { continuation in
			promise.done { continuation.resume(returning: $0) }.catch { continuation.resume(throwing: $0) }
		}
		XCTAssertTrue(ready === context)
		_ = context.publish().done {}
	}

	func testSDKGetContextDataAndClose() async throws {
		let client = ClientMock()
		client.getContextDataReturnValue = Promise.value(try contextData())
		client.closeReturnValue = Promise.value(())
		let sdk = try ABSmartlySDK(config: ABSmartlyConfig(client: client))

		let data = try await sdk.getContextData()
		XCTAssertEqual(try contextData(), data)

		try await sdk.close()
		XCTAssertEqual(1, client.closeCallsCount)
	}

	func testSDKCloseAwaitsPendingClientRejectionAndPreservesIt() async throws {
		struct CloseError: Error, Equatable { let id = UUID() }
		let sentinel = CloseError()
		let client = ClientMock()
		// Still pending when close() returns it, so an overload that does not await would return early.
		client.closeClosure = { after(seconds: 0.02).then { Promise<Void>(error: sentinel) } }
		let sdk = try ABSmartlySDK(config: ABSmartlyConfig(client: client))

		do {
			try await sdk.close()
			XCTFail("SDK.close returned without the client's pending rejection")
		} catch {
			XCTAssertEqual(sentinel, error as? CloseError)
		}
		XCTAssertEqual(1, client.closeCallsCount)
	}

	func testSDKCreateContextThenAwaitReady() async throws {
		let client = ClientMock()
		client.getContextDataReturnValue = Promise.value(try contextData())
		client.publishEventReturnValue = Promise.value(())
		let sdk = try ABSmartlySDK(config: ABSmartlyConfig(client: client))
		let config = ContextConfig()
		config.setUnit(unitType: "session_id", uid: "e791e240fcd3df7d238cfc285f475e8152fcc0ec")

		let context = sdk.createContext(config: config)
		try await context.waitUntilReady()

		XCTAssertEqual(1, context.getTreatment("exp_test_ab"))
		try await context.close()
		XCTAssertEqual(1, client.publishEventCallsCount)
	}

	func testClientCloseAwaitsPendingRejection() async throws {
		struct CloseError: Error, Equatable { let id = UUID() }
		let sentinel = CloseError()
		let mock = ClientMock()
		mock.closeClosure = { after(seconds: 0.02).then { Promise<Void>(error: sentinel) } }
		let client: Client = mock

		do {
			try await client.close()
			XCTFail("Client.close returned before rejecting")
		} catch {
			XCTAssertEqual(sentinel, error as? CloseError)
		}
		XCTAssertEqual(1, mock.closeCallsCount)
	}

	func testEventHandlerPublishAwaitsPendingRejection() async throws {
		struct PublishError: Error, Equatable { let id = UUID() }
		let sentinel = PublishError()
		let mock = ContextEventHandlerMock()
		mock.publishEventClosure = { _ in after(seconds: 0.02).then { Promise<Void>(error: sentinel) } }
		let handler: ContextEventHandler = mock

		do {
			try await handler.publish(event: publishEvent())
			XCTFail("ContextEventHandler.publish returned before rejecting")
		} catch {
			XCTAssertEqual(sentinel, error as? PublishError)
		}
		XCTAssertEqual(1, mock.publishEventCallsCount)
	}

	func testHTTPClientCloseAwaitsPendingRejection() async throws {
		struct CloseError: Error, Equatable { let id = UUID() }
		let sentinel = CloseError()
		let mock = HTTPClientMock()
		mock.closeClosure = { after(seconds: 0.02).then { Promise<Void>(error: sentinel) } }
		let client: HTTPClient = mock

		do {
			try await client.close()
			XCTFail("HTTPClient.close returned before rejecting")
		} catch {
			XCTAssertEqual(sentinel, error as? CloseError)
		}
		XCTAssertEqual(1, mock.closeCallsCount)
	}

	func testClientPublishAwaitsPendingRejection() async throws {
		struct PublishError: Error, Equatable { let id = UUID() }
		let sentinel = PublishError()
		let mock = ClientMock()
		mock.publishEventClosure = { _ in after(seconds: 0.02).then { Promise<Void>(error: sentinel) } }
		let client: Client = mock

		do {
			try await client.publish(event: publishEvent())
			XCTFail("Client.publish returned before rejecting")
		} catch {
			XCTAssertEqual(sentinel, error as? PublishError)
		}
		XCTAssertEqual(1, mock.publishEventCallsCount)
	}

	func testSDKGetContextDataAwaitsPendingRejection() async throws {
		struct FetchError: Error, Equatable { let id = UUID() }
		let sentinel = FetchError()
		let mock = ClientMock()
		mock.getContextDataClosure = { after(seconds: 0.02).then { Promise<ContextData>(error: sentinel) } }
		let sdk = try ABSmartlySDK(config: ABSmartlyConfig(client: mock))

		do {
			_ = try await sdk.getContextData()
			XCTFail("SDK.getContextData returned before rejecting")
		} catch {
			XCTAssertEqual(sentinel, error as? FetchError)
		}
		XCTAssertEqual(1, mock.getContextDataCallsCount)
	}

	func testHTTPClientGetAwaitsPendingRejection() async throws {
		struct RequestError: Error, Equatable { let id = UUID() }
		let sentinel = RequestError()
		let mock = HTTPClientMock()
		mock.getUrlQueryHeadersClosure = { _, _, _ in
			after(seconds: 0.02).then { Promise<Response>(error: sentinel) }
		}
		let client: HTTPClient = mock

		do {
			_ = try await client.get(url: "https://example.test/get", query: nil, headers: nil)
			XCTFail("HTTPClient.get returned before rejecting")
		} catch {
			XCTAssertEqual(sentinel, error as? RequestError)
		}
		XCTAssertEqual(1, mock.getUrlQueryHeadersCallsCount)
	}

	func testClientFetchAwaitsPendingRejection() async throws {
		struct Failure: Error, Equatable { let id = UUID() }
		let sentinel = Failure()
		let mock = ClientMock()
		mock.getContextDataClosure = { after(seconds: 0.02).then { Promise<ContextData>(error: sentinel) } }
		let client: Client = mock
		do {
			_ = try await client.getContextData()
			XCTFail("ClientFetch returned before rejecting")
		} catch {
			XCTAssertEqual(sentinel, error as? Failure)
		}
		XCTAssertEqual(1, mock.getContextDataCallsCount)
	}

	func testProviderFetchAwaitsPendingRejection() async throws {
		struct Failure: Error, Equatable { let id = UUID() }
		let sentinel = Failure()
		let mock = ContextDataProviderMock()
		mock.getContextDataClosure = { after(seconds: 0.02).then { Promise<ContextData>(error: sentinel) } }
		let client: ContextDataProvider = mock
		do {
			_ = try await client.getContextData()
			XCTFail("ProviderFetch returned before rejecting")
		} catch {
			XCTAssertEqual(sentinel, error as? Failure)
		}
		XCTAssertEqual(1, mock.getContextDataCallsCount)
	}

	func testHTTPPutAwaitsPendingRejection() async throws {
		struct Failure: Error, Equatable { let id = UUID() }
		let sentinel = Failure()
		let mock = HTTPClientMock()
		mock.putUrlQueryHeadersBodyClosure = { _, _, _, _ in after(seconds: 0.02).then { Promise<Response>(error: sentinel) } }
		let client: HTTPClient = mock
		do {
			_ = try await client.put(url: "https://example.test/put", query: nil, headers: nil, body: nil)
			XCTFail("HTTPPut returned before rejecting")
		} catch {
			XCTAssertEqual(sentinel, error as? Failure)
		}
		XCTAssertEqual(1, mock.putUrlQueryHeadersBodyCallsCount)
	}

	func testHTTPPostAwaitsPendingRejection() async throws {
		struct Failure: Error, Equatable { let id = UUID() }
		let sentinel = Failure()
		let mock = HTTPClientMock()
		mock.postUrlQueryHeadersBodyClosure = { _, _, _, _ in after(seconds: 0.02).then { Promise<Response>(error: sentinel) } }
		let client: HTTPClient = mock
		do {
			_ = try await client.post(url: "https://example.test/post", query: nil, headers: nil, body: nil)
			XCTFail("HTTPPost returned before rejecting")
		} catch {
			XCTAssertEqual(sentinel, error as? Failure)
		}
		XCTAssertEqual(1, mock.postUrlQueryHeadersBodyCallsCount)
	}

	func testFinalizeAwaitsRejectedFinalPublishAndRetainsGoal() async throws {
		struct Failure: Error, Equatable { let id = UUID() }
		let sentinel = Failure()
		let context = makeContext(Promise.value(try contextData()))
		context.track("goal", properties: nil)
		handler.publishEventClosure = { _ in after(seconds: 0.02).then { Promise<Void>(error: sentinel) } }
		do {
			try await context.finalize()
			XCTFail("finalize returned before rejecting")
		} catch {
			XCTAssertEqual(sentinel, error as? Failure)
		}
		XCTAssertEqual(1, handler.publishEventCallsCount)
		XCTAssertFalse(context.isClosed())
		XCTAssertFalse(context.isClosing())
		XCTAssertEqual(1, context.getPendingCount())
	}

	func testClientAndProviderOverloads() async throws {
		let client = ClientMock()
		client.getContextDataReturnValue = Promise.value(try contextData())
		client.publishEventReturnValue = Promise(error: ABSmartlyError("rejected"))
		client.closeReturnValue = Promise.value(())

		let fromClient = try await client.getContextData()
		XCTAssertEqual(try contextData(), fromClient)
		await XCTAssertThrowsAsync(try await client.publish(event: self.publishEvent()), "rejected")
		try await client.close()
		XCTAssertEqual(1, client.closeCallsCount)

		let fromProvider = try await DefaultContextDataProvider(client: client).getContextData()
		XCTAssertEqual(try contextData(), fromProvider)

		handler.publishEventReturnValue = Promise.value(())
		try await handler.publish(event: publishEvent())
		XCTAssertEqual(1, handler.publishEventCallsCount)
	}

	func testHTTPClientOverloads() async throws {
		let http = HTTPClientMock()
		let getResponse = DefaultHTTPResponse(status: 200, statusMessage: "OK", contentType: "application/json", content: Data())
		let putResponse = DefaultHTTPResponse(status: 204, statusMessage: "No Content", contentType: "text/plain", content: Data())
		http.getUrlQueryHeadersReturnValue = Promise.value(getResponse)
		http.putUrlQueryHeadersBodyReturnValue = Promise.value(putResponse)
		http.postUrlQueryHeadersBodyReturnValue = Promise(error: ABSmartlyError("post failed"))
		http.closeReturnValue = Promise.value(())

		let got = try await http.get(url: "https://example.test/get", query: ["q": "1"], headers: ["h": "2"])
		XCTAssertEqual(200, got.status)
		XCTAssertEqual("https://example.test/get", http.getUrlQueryHeadersReceivedArguments?.url)
		XCTAssertEqual(["q": "1"], http.getUrlQueryHeadersReceivedArguments?.query)
		XCTAssertEqual(["h": "2"], http.getUrlQueryHeadersReceivedArguments?.headers)
		let put = try await http.put(url: "https://example.test/put", query: ["p": "3"], headers: ["k": "4"], body: Data([5]))
		XCTAssertEqual("https://example.test/put", http.putUrlQueryHeadersBodyReceivedArguments?.url)
		XCTAssertEqual(["p": "3"], http.putUrlQueryHeadersBodyReceivedArguments?.query)
		XCTAssertEqual(["k": "4"], http.putUrlQueryHeadersBodyReceivedArguments?.headers)
		XCTAssertEqual(Data([5]), http.putUrlQueryHeadersBodyReceivedArguments?.body)
		XCTAssertEqual(204, put.status)
		XCTAssertEqual(1, http.getUrlQueryHeadersCallsCount)
		XCTAssertEqual(1, http.putUrlQueryHeadersBodyCallsCount)
		await XCTAssertThrowsAsync(
			try await http.post(url: "https://example.test/post", query: ["a": "b"], headers: ["c": "d"], body: Data([6])),
			"post failed")
		XCTAssertEqual("https://example.test/post", http.postUrlQueryHeadersBodyReceivedArguments?.url)
		XCTAssertEqual(["a": "b"], http.postUrlQueryHeadersBodyReceivedArguments?.query)
		XCTAssertEqual(["c": "d"], http.postUrlQueryHeadersBodyReceivedArguments?.headers)
		XCTAssertEqual(Data([6]), http.postUrlQueryHeadersBodyReceivedArguments?.body)
		XCTAssertEqual(1, http.postUrlQueryHeadersBodyCallsCount)
		try await http.close()
		XCTAssertEqual(1, http.closeCallsCount)
	}

	func testDefaultHTTPClientRequestOverloadPassesItsArguments() async throws {
		final class RecordingHTTPClient: DefaultHTTPClient {
			var received: (method: String, url: String, query: [String: String]?, headers: [String: String]?, body: Data?)?
			override func request(
				method: String, url: String, query: [String: String]?, headers: [String: String]?, body: Data?
			) -> Promise<Response> {
				received = (method, url, query, headers, body)
				return after(seconds: 0.02).then { Promise<Response>(error: URLError(.badURL)) }
			}
		}
		let http = RecordingHTTPClient(config: DefaultHTTPClientConfig())
		do {
			_ = try await http.request(
				method: "PATCH", url: "https://example.test/r", query: ["q": "1"], headers: ["h": "2"], body: Data([7]))
			XCTFail("expected the request to fail")
		} catch {
			XCTAssertEqual(URLError(.badURL), error as? URLError)
		}
		XCTAssertEqual("PATCH", http.received?.method)
		XCTAssertEqual("https://example.test/r", http.received?.url)
		XCTAssertEqual(["q": "1"], http.received?.query)
		XCTAssertEqual(["h": "2"], http.received?.headers)
		XCTAssertEqual(Data([7]), http.received?.body)
	}

	private func contextData(source: String) throws -> ContextData {
		let path = TestResources.path(forResource: source, ofType: "json")
		return try JSONDecoder().decode(ContextData.self, from: Data(contentsOf: URL(fileURLWithPath: path)))
	}

	private func publishEvent() -> PublishEvent {
		return PublishEvent(true, [], 0, [], [], [])
	}
}

@available(iOS 13, macOS 10.15, tvOS 13, watchOS 6, *)
private func XCTAssertThrowsAsync<T>(
	_ expression: @autoclosure () async throws -> T, _ message: String, file: StaticString = #filePath,
	line: UInt = #line
) async {
	do {
		_ = try await expression()
		XCTFail("expected an error", file: file, line: line)
	} catch {
		XCTAssertEqual(message, (error as? ABSmartlyError)?.errorMessage, file: file, line: line)
	}
}

private final class ManagedFlag {
	private let lock = NSLock()
	private var value = false

	func set() {
		lock.lock()
		value = true
		lock.unlock()
	}

	var isSet: Bool {
		lock.lock()
		defer { lock.unlock() }
		return value
	}
}
