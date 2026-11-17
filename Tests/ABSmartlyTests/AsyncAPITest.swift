import Foundation
import PromiseKit
import XCTest

@testable import ABSmartly
import ABSmartlyAsync

// The async overloads await the existing Promise-returning methods; these tests check each one
// returns or throws exactly what its Promise settles with.
@available(iOS 13, macOS 10.15, tvOS 13, watchOS 6, *)
final class AsyncAPITest: XCTestCase {
	var provider = ContextDataProviderMock()
	var handler = ContextEventHandlerMock()
	var scheduler = SchedulerMock()
	var clock = ClockMock()

	override func setUp() {
		provider = ContextDataProviderMock()
		handler = ContextEventHandlerMock()
		scheduler = SchedulerMock()
		scheduler.scheduleAfterExecuteReturnValue = ScheduledHandleMock()
		scheduler.scheduleWithFixedDelayAfterRepeatingExecuteReturnValue = ScheduledHandleMock()
		clock.millisReturnValue = 1_620_000_000_000
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
		// Same as the Promise: a load failure makes the context ready and failed, not an error.
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

		try await context.refresh()

		XCTAssertEqual(1, provider.getContextDataCallsCount)
		XCTAssertTrue(context.getExperiments().contains("exp_test_new"))
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

		try await context.publish()

		XCTAssertEqual(0, context.getPendingCount())
		XCTAssertEqual(["goal1"], handler.publishEventReceivedEvent?.goals.map { $0.name })
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

		try await context.close()

		XCTAssertTrue(context.isClosed())
		XCTAssertEqual(1, handler.publishEventCallsCount)
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

		// The call still waits for the publish and returns its result.
		try await task.value
		XCTAssertEqual(1, handler.publishEventCallsCount)
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
		// Code written against v1.4.0 that uses the returned Promise keeps doing so.
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

	func testClientAndProviderOverloads() async throws {
		let client = ClientMock()
		client.getContextDataReturnValue = Promise.value(try contextData())
		client.publishEventReturnValue = Promise(error: ABSmartlyError("rejected"))
		client.closeReturnValue = Promise.value(())

		let fromClient = try await client.getContextData()
		XCTAssertEqual(try contextData(), fromClient)
		await XCTAssertThrowsAsync(try await client.publish(event: self.publishEvent()), "rejected")
		try await client.close()

		let fromProvider = try await DefaultContextDataProvider(client: client).getContextData()
		XCTAssertEqual(try contextData(), fromProvider)

		handler.publishEventReturnValue = Promise.value(())
		try await handler.publish(event: publishEvent())
		XCTAssertEqual(1, handler.publishEventCallsCount)
	}

	func testHTTPClientOverloads() async throws {
		let http = HTTPClientMock()
		let response = DefaultHTTPResponse(status: 200, statusMessage: "OK", contentType: "application/json", content: Data())
		http.getUrlQueryHeadersReturnValue = Promise.value(response)
		http.putUrlQueryHeadersBodyReturnValue = Promise.value(response)
		http.postUrlQueryHeadersBodyReturnValue = Promise(error: ABSmartlyError("post failed"))
		http.closeReturnValue = Promise.value(())

		let got = try await http.get(url: "https://example.test", query: nil, headers: nil)
		XCTAssertEqual(200, got.status)
		let put = try await http.put(url: "https://example.test", query: nil, headers: nil, body: Data())
		XCTAssertEqual(200, put.status)
		await XCTAssertThrowsAsync(
			try await http.post(url: "https://example.test", query: nil, headers: nil, body: nil), "post failed")
		try await http.close()
		XCTAssertEqual(1, http.closeCallsCount)
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
