// Ported from 1.x PublicErrorFormattingTest.swift: formats SDK errors the way an app does, through
// the public API only (no `@testable`). On Linux with Swift 6.0 and 6.1, `localizedDescription`
// crashed for class-based errors; 2.0's error is an enum, and transport errors that are classes are
// read safely when wrapped.
//
// Not ported: PublicErrorFormattingTest.testLocalizedDescriptionOfABSmartlyError's `ABSmartlyError("…")`
//   initialiser and `errorMessage` property — 2.0's `ABsmartlyError` is an enum with fixed cases; the
//   formatting assertions are ported per case below.

import Foundation
import Testing

import ABsmartly

@Suite struct ErrorTests {
	static let endpoint = URL(string: "https://test.absmartly.io/v1")!

	@Test func localizedDescriptionOfThrownSDKError() {
		do {
			_ = try ABsmartlyClient(endpoint: Self.endpoint, apiKey: "", application: "test-app", environment: "test")
			Issue.record("expected an error")
		} catch {
			let erased: any Error = error
			#expect(erased.localizedDescription == "Missing APIKey configuration")
			#expect((erased as? ABsmartlyError) == .invalidConfiguration("Missing APIKey configuration"))
			#expect((erased as? LocalizedError)?.errorDescription == "Missing APIKey configuration")
		}
	}

	@Test(arguments: [
		(ABsmartlyError.invalidConfiguration("Missing Endpoint configuration"), "Missing Endpoint configuration"),
		(.invalidConfiguration("Missing APIKey configuration"), "Missing APIKey configuration"),
		(.invalidConfiguration("Missing Application configuration"), "Missing Application configuration"),
		(.invalidConfiguration("Missing Environment configuration"), "Missing Environment configuration"),
		(.notReady, "ABsmartly Context is not yet ready."),
		(.closing, "ABsmartly Context is finalizing."),
		(.closed, "ABsmartly Context is finalized."),
		(.blankUnitUID(unitType: "session_id"), "Unit 'session_id' UID must not be blank."),
		(.unitAlreadySet(unitType: "user_id"), "Unit 'user_id' UID already set."),
		(.httpStatus(code: 500, message: "Internal Server Error"), "Internal Server Error"),
		(.transport("Connection refused"), "Connection refused"),
		(.decoding("Something failed"), "Something failed"),
		(.cancelled, "The operation was cancelled."),
	])
	func localizedDescriptionOfEachCase(error: ABsmartlyError, message: String) {
		let erased: any Error = error
		#expect(erased.localizedDescription == message)
		#expect(error.errorDescription == message)
		#expect(error.localizedDescription == message)
		#expect(error.description == message)
		#expect("\(error)" == message)
	}

	@Test func equalityAndHashing() {
		#expect(ABsmartlyError.httpStatus(code: 500, message: "a") == .httpStatus(code: 500, message: "a"))
		#expect(ABsmartlyError.httpStatus(code: 500, message: "a") != .httpStatus(code: 502, message: "a"))
		#expect(ABsmartlyError.blankUnitUID(unitType: "a") != .unitAlreadySet(unitType: "a"))
		#expect(ABsmartlyError.transport("x") != .decoding("x"))
		let set: Set<ABsmartlyError> = [.notReady, .notReady, .closed, .transport("x"), .transport("x")]
		#expect(set.count == 3)
	}

	// MARK: - Errors from a custom transport, through the public API

	final class ThrowingTransport: Transport {
		let error: @Sendable () -> any Error
		init(_ error: @escaping @Sendable () -> any Error) { self.error = error }
		func send(_ request: HTTPRequest) async throws -> HTTPResponse { throw error() }
	}

	struct StructError: LocalizedError {
		var errorDescription: String? { "struct failure" }
	}

	/// A class-based, non-NSError error: reading its `localizedDescription` crashed on Linux with
	/// Swift 6.0/6.1.
	final class ClassError: LocalizedError, @unchecked Sendable {
		var errorDescription: String? { "class failure" }
	}

	static func fetchError(_ error: @escaping @Sendable () -> any Error) async -> ABsmartlyError? {
		var configuration = ABsmartlyClient.Configuration(
			endpoint: endpoint, apiKey: "k", application: "a", environment: "e")
		configuration.transport = ThrowingTransport(error)
		configuration.retries = 0
		guard let client = try? ABsmartlyClient(configuration: configuration) else { return nil }
		do {
			_ = try await client.fetchContextData()
			return nil
		} catch {
			return error
		}
	}

	@Test func transportErrorsAreWrappedWithTheirDescription() async {
		#expect(await Self.fetchError { StructError() } == .transport("struct failure"))
		#expect(await Self.fetchError { ClassError() } == .transport("class failure"))
		let nsError = NSError(domain: "test", code: 7, userInfo: [NSLocalizedDescriptionKey: "ns failure"])
		#expect(await Self.fetchError { nsError } == .transport("ns failure"))
	}

	@Test func sdkErrorsThrownByATransportPassThrough() async {
		#expect(await Self.fetchError { ABsmartlyError.closed } == .closed)
	}

	@Test func cancellationIsReportedAsCancelled() async {
		#expect(await Self.fetchError { CancellationError() } == .cancelled)
		#expect(await Self.fetchError { URLError(.cancelled) } == .cancelled)
	}

	@Test func decodingErrorsAreReportedAsDecoding() async {
		let error = await Self.fetchError {
			DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "bad"))
		}
		guard case .decoding = error else {
			Issue.record("expected .decoding, got \(String(describing: error))")
			return
		}
	}

	@Test func urlErrorsAreTransportErrors() async {
		let error = await Self.fetchError { URLError(.timedOut) }
		guard case .transport(let message) = error else {
			Issue.record("expected .transport, got \(String(describing: error))")
			return
		}
		#expect(!message.isEmpty)
	}
}
