import Foundation
#if canImport(FoundationNetworking)
	import FoundationNetworking
#endif
import Testing

@testable import ABsmartly

@Suite struct ABsmartlyClientTests {
	static let endpoint = URL(string: "https://test.absmartly.io/v1")!
	static let units: [UnitType: String] = [.sessionID: "123456789"]
	static let emptyData = Data(#"{"experiments":[]}"#.utf8)

	static let applicationEnvironmentFilter =
		#"[{"eq":[{"var":"application"},{"value":"website"}]},{"eq":[{"var":"environment"},{"value":"production"}]}]"#

	// MARK: - Configuration validation

	@Test func namedParameterInitialization() throws {
		let client = try ABsmartlyClient(
			endpoint: Self.endpoint, apiKey: "test-api-key", application: "test-app", environment: "test")
		#expect(client.configuration.endpoint == Self.endpoint)
		#expect(client.configuration.apiKey == "test-api-key")
		#expect(client.configuration.application == "test-app")
		#expect(client.configuration.environment == "test")

		// A context can be created from it (pre-fetched data, so the test does not touch the network).
		let context = client.context(units: [.sessionID: "test123"], data: ContextData())
		#expect(context.state == .ready)
		#expect(context.units == [.sessionID: "test123"])
	}

	@Test func namedParameterInitializationWithOptionalParameters() throws {
		let client = try ABsmartlyClient(
			endpoint: Self.endpoint, apiKey: "test-api-key", application: "test-app", environment: "production",
			applicationVersion: "1.2.3")
		#expect(client.configuration.applicationVersion == "1.2.3")
		#expect(client.configuration.environment == .production)

		// timeout and retries are Configuration properties in 2.0.
		var configuration = ABsmartlyClient.Configuration(
			endpoint: Self.endpoint, apiKey: "test-api-key", application: "test-app", environment: "production")
		#expect(configuration.timeout == 3)
		#expect(configuration.retries == 3)
		#expect(configuration.retryInterval == 0.5)
		#expect(configuration.applicationVersion == "0")
		configuration.applicationVersion = "1.2.3"
		configuration.timeout = 5.0
		configuration.retries = 3
		let configured = try ABsmartlyClient(configuration: configuration)
		#expect(configured.configuration.timeout == 5.0)
		#expect(configured.configuration.retries == 3)

		let context = configured.context(units: [.userID: "user456"], data: ContextData())
		#expect(context.units == [.userID: "user456"])
	}

	@Test func namedParameterInitializationThrowsWithEmptyEndpoint() throws {
		let empty = try #require(URLComponents().url)
		#expect(empty.absoluteString.isEmpty)
		#expect(throws: ABsmartlyError.invalidConfiguration("Missing Endpoint configuration")) {
			try ABsmartlyClient(endpoint: empty, apiKey: "test-api-key", application: "test-app", environment: "test")
		}
	}

	@Test func namedParameterInitializationThrowsWithEmptyApiKey() {
		#expect(throws: ABsmartlyError.invalidConfiguration("Missing APIKey configuration")) {
			try ABsmartlyClient(endpoint: Self.endpoint, apiKey: "", application: "test-app", environment: "test")
		}
	}

	@Test func namedParameterInitializationThrowsWithEmptyApplication() {
		#expect(throws: ABsmartlyError.invalidConfiguration("Missing Application configuration")) {
			try ABsmartlyClient(endpoint: Self.endpoint, apiKey: "test-api-key", application: "", environment: "test")
		}
	}

	@Test func namedParameterInitializationThrowsWithEmptyEnvironment() {
		#expect(throws: ABsmartlyError.invalidConfiguration("Missing Environment configuration")) {
			try ABsmartlyClient(endpoint: Self.endpoint, apiKey: "test-api-key", application: "test-app", environment: "")
		}
	}

	@Test func validationMessagesReadLikeTheOnes1xThrew() {
		do {
			_ = try ABsmartlyClient(endpoint: Self.endpoint, apiKey: "", application: "a", environment: "e")
			Issue.record("expected an error")
		} catch {
			#expect(error.localizedDescription == "Missing APIKey configuration")
		}
	}

	// MARK: - Event loggers

	@Test func namedParameterInitializationWithCustomEventLogger() throws {
		let recorder = EventRecorder()
		let client = try ABsmartlyClient(
			endpoint: Self.endpoint, apiKey: "test-api-key", application: "test-app", environment: "test",
			eventLogger: recorder.logger)
		#expect(client.configuration.eventLogger != nil)
	}

	@Test func eventLoggerIsPassedToFetchedContexts() async throws {
		let harness = Harness(contextData: Self.emptyData)
		let context = harness.client.makeContext(units: [.sessionID: "test123"])
		try await withTimeout { try await context.ready() }
		#expect(await eventually { harness.recorder.events.contains(.ready(ContextData())) })
	}

	@Test func eventLoggerIsPassedToContextsWithData() {
		let harness = Harness()
		_ = harness.client.context(units: [.sessionID: "test123"], data: ContextData())
		#expect(harness.recorder.events == [.ready(ContextData())])
	}

	@Test func contextOptionsEventLoggerOverridesClientEventLogger() {
		let harness = Harness()
		let contextRecorder = EventRecorder()
		_ = harness.client.context(
			units: [.sessionID: "test123"], options: Context.Options(eventLogger: contextRecorder.logger),
			data: ContextData())
		#expect(contextRecorder.events == [.ready(ContextData())])
		#expect(harness.recorder.events.isEmpty)
	}

	// MARK: - Creation paths

	@Test func makeContextLoadsInTheBackground() async throws {
		let harness = Harness()
		let gate = ResponseGate()
		harness.transport.enqueue { _ in
			await gate.wait()
			return HTTPResponse(statusCode: 200, body: Self.emptyData)
		}

		let context = harness.client.makeContext(units: Self.units)
		#expect(context.state == .loading)
		#expect(!context.state.isSettled)
		#expect(await eventually { harness.transport.requests.count == 1 })
		#expect(context.state == .loading)

		gate.open()
		try await withTimeout { try await context.ready() }
		#expect(context.state == .ready)
		#expect(harness.transport.requests.count == 1)
	}

	@Test func makeContextReadyThrowsTheLoadError() async throws {
		let harness = Harness()
		harness.transport.enqueue(status: 500)
		let context = harness.client.makeContext(units: Self.units)
		let error = try await withTimeout { await sdkError { try await context.ready() } }
		#expect(error == .httpStatus(code: 500, message: HTTPURLResponse.localizedString(forStatusCode: 500)))
		#expect(context.state == .failed(.httpStatus(code: 500, message: HTTPURLResponse.localizedString(forStatusCode: 500))))
		#expect(context.state.isSettled)
		#expect(harness.recorder.errors == [.httpStatus(code: 500, message: HTTPURLResponse.localizedString(forStatusCode: 500))])
	}

	@Test func awaitedContextIsReady() async throws {
		let harness = Harness()
		let context = try await withTimeout { try await harness.client.context(units: Fixtures.units) }
		#expect(context.state == .ready)
		#expect(harness.transport.requests.map(\.method) == ["GET"])
		#expect(context.contextData == Fixtures.contextData())
		#expect(context.treatment(for: "exp_test_abc", exposing: false) == 2)
	}

	@Test func awaitedContextThrowsTheLoadError() async throws {
		let harness = Harness()
		harness.transport.enqueue { _ in throw URLError(.notConnectedToInternet) }
		let error = try await withTimeout {
			await sdkError { _ = try await harness.client.context(units: Self.units) }
		}
		guard case .transport = error else {
			Issue.record("expected a transport error, got \(String(describing: error))")
			return
		}
	}

	@Test func createContextWithData() {
		let harness = Harness()
		let context = harness.client.context(units: Self.units, data: ContextData())
		#expect(context.state == .ready)
		#expect(context.state.isSettled)
		#expect(harness.transport.requests.isEmpty)
	}

	@Test func fetchContextData() async throws {
		let harness = Harness()
		let data = try await withTimeout { try await harness.client.fetchContextData() }
		#expect(harness.transport.requests.count == 1)
		#expect(harness.transport.requests.first?.method == "GET")
		#expect(data == Fixtures.contextData())
	}

	@Test func customTransportServesFetchAndContextCreation() async throws {
		let transport = FakeTransport(contextData: Self.emptyData)
		var configuration = ABsmartlyClient.Configuration(
			endpoint: Self.endpoint, apiKey: "test-api-key", application: "website", environment: "production")
		configuration.transport = transport
		configuration.defaultContextOptions = Context.Options(publishDelay: -1)
		let client = try ABsmartlyClient(configuration: configuration)

		let data = try await withTimeout { try await client.fetchContextData() }
		#expect(data == ContextData())
		#expect(transport.requests.count == 1)

		let context = client.makeContext(units: Self.units)
		try await withTimeout { try await context.ready() }
		#expect(transport.requests.count == 2)
	}

	// MARK: - System attributes

	// Every creation path forwards the client's application/environment into the Context, so a strict
	// audience targeting them matches without the caller setting them.
	@Test func preFetchedContextForwardsClientApplicationAndEnvironment() throws {
		let harness = Harness(application: "website", environment: "production")
		let filter = Self.applicationEnvironmentFilter

		let context = harness.context(data: try strictAudienceContextData(filter: filter), units: Self.units)
		#expect(context.state == .ready)
		#expect(context.treatment(for: "exp_test_ab", exposing: false) == 1)

		// A staging target does not match the configured production environment.
		let staging = harness.context(
			data: try strictAudienceContextData(filter: filter.replacingOccurrences(of: "production", with: "staging")),
			units: Self.units)
		#expect(staging.treatment(for: "exp_test_ab", exposing: false) == 0)

		// Nor does another application.
		let otherApp = harness.context(
			data: try strictAudienceContextData(filter: filter.replacingOccurrences(of: "website", with: "mobile")),
			units: Self.units)
		#expect(otherApp.treatment(for: "exp_test_ab", exposing: false) == 0)

		// They are evaluation inputs, not attributes the caller set.
		#expect(context.attributes.isEmpty)
	}

	@Test func makeContextForwardsClientApplicationAndEnvironment() async throws {
		for (filter, expected) in [
			(Self.applicationEnvironmentFilter, 1),
			(Self.applicationEnvironmentFilter.replacingOccurrences(of: "production", with: "staging"), 0),
			(Self.applicationEnvironmentFilter.replacingOccurrences(of: "website", with: "mobile"), 0),
		] {
			let data = try JSONEncoder().encode(try strictAudienceContextData(filter: filter))
			let harness = Harness(contextData: data, application: "website", environment: "production")
			let context = harness.client.makeContext(units: Self.units)
			try await withTimeout { try await context.ready() }
			#expect(context.treatment(for: "exp_test_ab", exposing: false) == expected, "\(filter)")
		}
	}

	@Test func awaitedContextForwardsClientApplicationAndEnvironment() async throws {
		for (filter, expected) in [
			(Self.applicationEnvironmentFilter, 1),
			(Self.applicationEnvironmentFilter.replacingOccurrences(of: "production", with: "staging"), 0),
			(Self.applicationEnvironmentFilter.replacingOccurrences(of: "website", with: "mobile"), 0),
		] {
			let data = try JSONEncoder().encode(try strictAudienceContextData(filter: filter))
			let harness = Harness(contextData: data, application: "website", environment: "production")
			let context = try await withTimeout { try await harness.client.context(units: Self.units) }
			#expect(context.treatment(for: "exp_test_ab", exposing: false) == expected, "\(filter)")
		}
	}

	// A client configured with an application version does not inject it as `app_version`.
	@Test func createContextDoesNotEvaluateApplicationVersion() throws {
		let client = try ABsmartlyClient(
			endpoint: Self.endpoint, apiKey: "test-api-key", application: "website", environment: "production",
			applicationVersion: "1.2.3")
		let data = try strictAudienceContextData(filter: #"[{"eq":[{"var":"app_version"},{"value":"1.2.3"}]}]"#)
		let context = client.context(
			units: Self.units, options: Context.Options(publishDelay: -1), data: data)
		#expect(context.treatment(for: "exp_test_ab", exposing: false) == 0)

		// The same audience matches once the attribute is set explicitly.
		context.setAttribute("app_version", to: "1.2.3")
		#expect(context.treatment(for: "exp_test_ab", exposing: false) == 1)
	}

	// `app_version` is absent from evaluation even with a configured application version: a `null`
	// check on it matches, so no value (not even "0") is injected.
	@Test(arguments: ["1.2.3", "1004", "0"])
	func createContextLeavesAppVersionUnset(applicationVersion: String) throws {
		let client = try ABsmartlyClient(
			endpoint: Self.endpoint, apiKey: "test-api-key", application: "website", environment: "production",
			applicationVersion: applicationVersion)
		let data = try strictAudienceContextData(filter: #"[{"null":{"var":"app_version"}}]"#)
		let context = client.context(units: Self.units, options: Context.Options(publishDelay: -1), data: data)
		#expect(context.treatment(for: "exp_test_ab", exposing: false) == 1)
		#expect(context.attribute("app_version") == nil)
	}

	// MARK: - Context creation parameters

	@Test func setUnit() {
		let context = Harness().context(data: ContextData(), units: [.sessionID: "0ab1e23f4eee"])
		#expect(context.units[.sessionID] == "0ab1e23f4eee")
	}

	@Test func setUnits() {
		let units: [UnitType: String] = [.sessionID: "0ab1e23f4eee", .userID: String(0xabcdef)]
		let context = Harness().context(data: ContextData(), units: units)
		#expect(context.units == units)
	}

	@Test func setAttribute() {
		let context = Harness().context(data: ContextData(), attributes: ["user_agent": "Chrome", "age": 9])
		#expect(context.attributes["user_agent"]?.stringValue == "Chrome")
		#expect(context.attributes["age"]?.intValue == 9)
	}

	@Test func setAttributes() {
		let attributes: [String: JSONValue] = ["user_agent": "Chrome", "age": 9]
		let harness = Harness()
		for context in [
			harness.context(data: ContextData(), attributes: attributes),
			harness.client.makeContext(units: Self.units, attributes: attributes),
		] {
			#expect(context.attributes == attributes)
			#expect(context.attributes["user_agent"]?.stringValue == "Chrome")
			#expect(context.attributes["age"]?.intValue == 9)
		}
	}

	@Test func setOverride() {
		let context = Harness().context(overrides: ["exp_test": 2])
		#expect(context.overrides["exp_test"] == 2)
	}

	@Test func setOverrides() {
		let overrides = ["exp_test": 2, "exp_test_new": 1]
		let context = Harness().context(overrides: overrides)
		#expect(context.overrides == overrides)
	}

	@Test func setCustomAssignment() {
		let context = Harness().context(customAssignments: ["exp_test": 2])
		#expect(context.customAssignments["exp_test"] == 2)
	}

	@Test func setCustomAssignments() {
		let assignments = ["exp_test": 2, "exp_test_new": 1]
		let context = Harness().context(customAssignments: assignments)
		#expect(context.customAssignments == assignments)
	}

	@Test func setPublishDelay() {
		var options = Context.Options()
		#expect(options.publishDelay == 0.1)
		options.publishDelay = 999
		#expect(options.publishDelay == 999)
	}

	@Test func defaultContextOptionsApplyWhenNoneAreGiven() async throws {
		// The Harness's default options disable auto-publish; a queued exposure stays pending.
		let harness = Harness()
		let context = harness.context()
		_ = context.treatment(for: "exp_test_ab")
		try await Task.sleep(nanoseconds: 150_000_000)
		#expect(harness.transport.publishes.isEmpty)
		#expect(context.pendingEventCount == 1)
	}
}
