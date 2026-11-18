import Foundation
#if canImport(FoundationNetworking)
	import FoundationNetworking
#endif
import Testing

@testable import ABsmartly

@Suite struct ConnectionTests {
	static let endpoint = URL(string: "https://test.absmartly.io/v1")!

	static func configuration(
		apiKey: String = "test", application: String = "test_app", environment: ABsmartlyClient.Environment = "test",
		applicationVersion: String = "0", retries: Int = 0, retryInterval: TimeInterval = 0,
		transport: FakeTransport
	) -> ABsmartlyClient.Configuration {
		var configuration = ABsmartlyClient.Configuration(
			endpoint: endpoint, apiKey: apiKey, application: application, environment: environment)
		configuration.applicationVersion = applicationVersion
		configuration.retries = retries
		configuration.retryInterval = retryInterval
		configuration.transport = transport
		return configuration
	}

	static func connection(
		apiKey: String = "test", application: String = "test_app", environment: ABsmartlyClient.Environment = "test",
		applicationVersion: String = "0", retries: Int = 0, retryInterval: TimeInterval = 0,
		transport: FakeTransport = FakeTransport(contextData: Fixtures.data("context"))
	) -> (Connection, FakeTransport) {
		let configuration = configuration(
			apiKey: apiKey, application: application, environment: environment, applicationVersion: applicationVersion,
			retries: retries, retryInterval: retryInterval, transport: transport)
		return (Connection(configuration: configuration), transport)
	}

	static let event = PublishEvent(
		hashed: true, units: [PublishEvent.Unit(type: "session_id", uid: "abc123")], publishedAt: 1_620_000_000_000,
		exposures: [], goals: [], attributes: [])

	static func query(_ url: URL) -> [String: String]? {
		guard let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems else { return nil }
		return Dictionary(items.map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { _, last in last })
	}

	static func path(_ url: URL) -> String {
		var components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
		components.query = nil
		return components.url!.absoluteString
	}

	// MARK: - Configuration

	@Test func configurationPropertiesAreSettable() throws {
		var configuration = ABsmartlyClient.Configuration(
			endpoint: URL(string: "https://example.com")!, apiKey: "", application: "", environment: "")
		configuration.apiKey = "test"
		configuration.application = "test_app"
		configuration.endpoint = Self.endpoint
		configuration.environment = "test"
		configuration.applicationVersion = "2"

		#expect(configuration.apiKey == "test")
		#expect(configuration.application == "test_app")
		#expect(configuration.endpoint.absoluteString == "https://test.absmartly.io/v1")
		#expect(configuration.environment == "test")
		#expect(configuration.applicationVersion == "2")
		configuration.transport = FakeTransport()
		#expect(throws: Never.self) { try ABsmartlyClient(configuration: configuration) }
	}

	@Test func applicationAndEnvironmentAreCapturedAtInit() async throws {
		let transport = FakeTransport()
		var configuration = Self.configuration(application: "website", environment: "production", transport: transport)
		let client = try ABsmartlyClient(configuration: configuration)
		#expect(client.configuration.application == "website")
		#expect(client.configuration.environment == "production")

		// Captured at init, like the HTTP metadata: changing the configuration afterwards does not
		// change the names requests carry or audiences evaluate against.
		configuration.application = "mobile"
		configuration.environment = "staging"
		#expect(client.configuration.application == "website")
		#expect(client.configuration.environment == "production")

		_ = try await withTimeout { try await client.fetchContextData() }
		#expect(transport.requests.first?.headers["X-Application"] == "website")
		#expect(transport.requests.first?.headers["X-Environment"] == "production")
	}

	@Test func throwsWithMissingEndpoint() throws {
		var configuration = Self.configuration(transport: FakeTransport())
		configuration.endpoint = try #require(URLComponents().url)
		#expect(throws: ABsmartlyError.invalidConfiguration("Missing Endpoint configuration")) {
			try ABsmartlyClient(configuration: configuration)
		}
	}

	@Test func throwsWithMissingApiKey() {
		let configuration = Self.configuration(apiKey: "", transport: FakeTransport())
		#expect(throws: ABsmartlyError.invalidConfiguration("Missing APIKey configuration")) {
			try ABsmartlyClient(configuration: configuration)
		}
	}

	@Test func throwsWithMissingApplication() {
		let configuration = Self.configuration(application: "", transport: FakeTransport())
		#expect(throws: ABsmartlyError.invalidConfiguration("Missing Application configuration")) {
			try ABsmartlyClient(configuration: configuration)
		}
	}

	@Test func throwsWithMissingEnvironment() {
		let configuration = Self.configuration(environment: "", transport: FakeTransport())
		#expect(throws: ABsmartlyError.invalidConfiguration("Missing Environment configuration")) {
			try ABsmartlyClient(configuration: configuration)
		}
	}

	@Test func constructorAcceptsValidConfig() throws {
		var configuration = ABsmartlyClient.Configuration(
			endpoint: URL(string: "https://example.com/v1")!, apiKey: "my-key", application: "my-app",
			environment: "production")
		configuration.transport = FakeTransport()
		let client = try ABsmartlyClient(configuration: configuration)
		#expect(client.configuration.apiKey == "my-key")
	}

	// MARK: - GET /context

	@Test func getContextData() async throws {
		let (connection, transport) = Self.connection()
		let data = try await withTimeout { try await connection.fetchContextData() }
		#expect(data == Fixtures.contextData())

		#expect(transport.requests.count == 1)
		let request = try #require(transport.requests.first)
		#expect(request.method == "GET")
		#expect(Self.path(request.url) == "https://test.absmartly.io/v1/context")
		#expect(Self.query(request.url) == ["environment": "test", "application": "test_app"])
		#expect(!request.headers.isEmpty)
		#expect(request.body == nil)
		#expect(request.timeout == 3)
	}

	@Test func getContextDataSetsCorrectQueryParameters() async throws {
		let (connection, transport) = Self.connection()
		_ = try await withTimeout { try await connection.fetchContextData() }
		let request = try #require(transport.requests.first)
		let query = try #require(Self.query(request.url))
		#expect(query["application"] == "test_app")
		#expect(query["environment"] == "test")
		#expect(query.count == 2)
	}

	@Test func queryValuesArePercentEncoded() async throws {
		let (connection, transport) = Self.connection(application: "my app&x=1", environment: "a/b?c")
		_ = try await withTimeout { try await connection.fetchContextData() }
		let request = try #require(transport.requests.first)
		#expect(Self.query(request.url) == ["application": "my app&x=1", "environment": "a/b?c"])
	}

	@Test func endpointIsAppendedAsGiven() {
		// "/context" is appended to the endpoint as given: a trailing slash is kept, as in 1.5.0.
		let transport = FakeTransport()
		var configuration = Self.configuration(transport: transport)
		configuration.endpoint = URL(string: "https://test.absmartly.io/v1/")!
		let connection = Connection(configuration: configuration)
		#expect(Self.path(connection.url) == "https://test.absmartly.io/v1//context")
	}

	@Test func getContextDataRejectsOnHttpError() async throws {
		let (connection, transport) = Self.connection()
		transport.enqueue(status: 500)
		let error = try await withTimeout { await sdkError { _ = try await connection.fetchContextData() } }
		#expect(error == .httpStatus(code: 500, message: HTTPURLResponse.localizedString(forStatusCode: 500)))
	}

	@Test func getContextDataRejectsOn404() async throws {
		let (connection, transport) = Self.connection()
		transport.enqueue(status: 404)
		let error = try await withTimeout { await sdkError { _ = try await connection.fetchContextData() } }
		#expect(error == .httpStatus(code: 404, message: HTTPURLResponse.localizedString(forStatusCode: 404)))
	}

	@Test func getContextDataRejectsOnNetworkError() async throws {
		let (connection, transport) = Self.connection()
		struct ConnectionRefused: Error, LocalizedError {
			var errorDescription: String? { "Connection refused" }
		}
		transport.enqueue { _ in throw ConnectionRefused() }
		let error = try await withTimeout { await sdkError { _ = try await connection.fetchContextData() } }
		#expect(error == .transport("Connection refused"))
	}

	@Test func getContextDataRejectsOnMalformedResponse() async throws {
		let (connection, transport) = Self.connection()
		transport.enqueue(status: 200, body: Data("not valid json".utf8))
		let error = try await withTimeout { await sdkError { _ = try await connection.fetchContextData() } }
		guard case .decoding(let message) = error else {
			Issue.record("expected a decoding error, got \(String(describing: error))")
			return
		}
		#expect(!message.isEmpty)
	}

	@Test func getContextDataRejectsAWrongShape() async throws {
		let (connection, transport) = Self.connection()
		transport.enqueue(status: 200, body: Data(#"{"experiments":{}}"#.utf8))
		let error = try await withTimeout { await sdkError { _ = try await connection.fetchContextData() } }
		guard case .decoding = error else {
			Issue.record("expected a decoding error, got \(String(describing: error))")
			return
		}
	}

	@Test func successfulStatusesOtherThan200AreAccepted() async throws {
		let (connection, transport) = Self.connection()
		transport.enqueue(status: 204, body: Data(#"{"experiments":[]}"#.utf8))
		transport.enqueue(status: 299, body: Data(#"{"experiments":[]}"#.utf8))
		_ = try await withTimeout { try await connection.fetchContextData() }
		_ = try await withTimeout { try await connection.fetchContextData() }
		transport.enqueue(status: 300)
		let error = try await withTimeout { await sdkError { _ = try await connection.fetchContextData() } }
		#expect(error == .httpStatus(code: 300, message: HTTPURLResponse.localizedString(forStatusCode: 300)))
	}

	@Test func multipleGetContextDataCalls() async throws {
		let (connection, transport) = Self.connection()
		_ = try await withTimeout { try await connection.fetchContextData() }
		_ = try await withTimeout { try await connection.fetchContextData() }
		#expect(transport.requests.count == 2)
	}

	// MARK: - PUT /context

	@Test func publishCallsEndpoint() async throws {
		let (connection, transport) = Self.connection()
		try await withTimeout { try await connection.publish(Self.event) }

		#expect(transport.publishes.count == 1)
		let request = try #require(transport.publishes.first)
		#expect(request.url.absoluteString == "https://test.absmartly.io/v1/context")
		#expect(Self.query(request.url) == nil)

		#expect(request.headers["Content-Type"] == "application/json; charset=utf-8")
		#expect(request.headers["X-API-Key"] == "test")
		#expect(request.headers["X-Environment"] == "test")
		#expect(request.headers["X-Application"] == "test_app")
		#expect(request.headers["X-Agent"] == "absmartly-swift-sdk/\(SDKVersion.version)")
		#expect(request.headers["X-Agent"] == "absmartly-swift-sdk/2.0.0")
		#expect(request.body != nil)
	}

	@Test func publishSendsCorrectBody() async throws {
		let (connection, transport) = Self.connection()
		var event = Self.event
		event.exposures = [
			Exposure(
				id: 1, name: "exp_test", unit: "session_id", variant: 1, exposedAt: 1_620_000_000_000, assigned: true,
				eligible: true, overridden: false, fullOn: false, custom: false, audienceMismatch: false,
				ruleOverride: false)
		]
		event.goals = [Goal(name: "goal1", achievedAt: 1_620_000_000_000, properties: ["amount": 100])]
		let sent = event
		try await withTimeout { try await connection.publish(sent) }

		let body = try #require(transport.publishedBodies.first)
		#expect(body["hashed"] == true)
		#expect(body["publishedAt"] == .int(1_620_000_000_000))
		#expect(body["units"] != nil)
		#expect(body["exposures"] != nil)
		#expect(body["goals"] != nil)
	}

	@Test func publishOmitsEmptyArrays() async throws {
		let (connection, transport) = Self.connection()
		try await withTimeout { try await connection.publish(Self.event) }
		let body = try #require(transport.publishedBodies.first)
		#expect(body["exposures"] == nil)
		#expect(body["goals"] == nil)
		#expect(body["attributes"] == nil)
	}

	@Test func publishRejectsOnHttpError() async throws {
		let (connection, transport) = Self.connection()
		transport.enqueue(status: 500)
		let error = try await withTimeout { await sdkError { try await connection.publish(Self.event) } }
		#expect(error == .httpStatus(code: 500, message: HTTPURLResponse.localizedString(forStatusCode: 500)))
	}

	@Test func publishRejectsOnNetworkError() async throws {
		let (connection, transport) = Self.connection()
		transport.enqueue { _ in throw URLError(.cannotConnectToHost) }
		let error = try await withTimeout { await sdkError { try await connection.publish(Self.event) } }
		guard case .transport = error else {
			Issue.record("expected a transport error, got \(String(describing: error))")
			return
		}
	}

	@Test func publishRejectsOnClientError() async throws {
		let (connection, transport) = Self.connection()
		transport.enqueue(status: 400)
		let error = try await withTimeout { await sdkError { try await connection.publish(Self.event) } }
		#expect(error == .httpStatus(code: 400, message: HTTPURLResponse.localizedString(forStatusCode: 400)))
	}

	@Test func publishRejectsOn401() async throws {
		let (connection, transport) = Self.connection()
		transport.enqueue(status: 401)
		let error = try await withTimeout { await sdkError { try await connection.publish(Self.event) } }
		#expect(error == .httpStatus(code: 401, message: HTTPURLResponse.localizedString(forStatusCode: 401)))
	}

	@Test func publishSetsApplicationVersionHeader() async throws {
		let (connection, transport) = Self.connection(applicationVersion: "1002003")
		try await withTimeout { try await connection.publish(Self.event) }
		#expect(transport.publishes.first?.headers["X-Application-Version"] == "1002003")
	}

	@Test func multiplePublishCalls() async throws {
		let (connection, transport) = Self.connection()
		var second = Self.event
		second.units = [PublishEvent.Unit(type: "user_id", uid: "user456")]
		second.publishedAt = 1_620_000_001_000
		try await withTimeout { try await connection.publish(Self.event) }
		let sent = second
		try await withTimeout { try await connection.publish(sent) }
		#expect(transport.publishes.count == 2)
	}

	// MARK: - Headers

	// Cross-SDK scenario 320: the context GET carries the same SDK headers as the publish PUT
	// (as javascript-sdk sends on every request), including X-Agent absmartly-<lang>-sdk/<semver>.
	@Test func getContextDataSendsSameHeadersAsPublish() async throws {
		let (connection, transport) = Self.connection(
			apiKey: "test-key", application: "website", environment: "production", applicationVersion: "1004")
		_ = try await withTimeout { try await connection.fetchContextData() }
		try await withTimeout { try await connection.publish(PublishEvent(units: [], publishedAt: 0, exposures: [], goals: [], attributes: [])) }

		let get = try #require(transport.requests.first { $0.method == "GET" })
		#expect(Self.query(get.url) == ["application": "website", "environment": "production"])

		let headers = get.headers
		#expect(headers["Content-Type"] == "application/json; charset=utf-8")
		#expect(headers["X-API-Key"] == "test-key")
		#expect(headers["X-Environment"] == "production")
		#expect(headers["X-Application"] == "website")
		#expect(headers["X-Application-Version"] == "1004")
		let agent = try #require(headers["X-Agent"])
		#expect(
			agent.range(
				of: "^absmartly-[a-z0-9]+-sdk/[0-9]+\\.[0-9]+\\.[0-9]+([-+][0-9A-Za-z.+-]*)?$", options: .regularExpression)
				!= nil, "\(agent)")
		#expect(transport.publishes.first?.headers == headers)
		#expect(headers.count == 6)
	}

	// The collector binds X-Application-Version as a Long and rejects anything else with HTTP 400, so
	// only the wire value is normalised (like the Java SDK): trimmed, 1–18 ASCII digits pass, anything
	// else is sent as "0". Both the context GET and the publish PUT carry the normalised value.
	@Test(arguments: [
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
	])
	func applicationVersionHeaderIsNormalisedOnGetAndPut(configured: String, expected: String) async throws {
		let transport = FakeTransport()
		var configuration = Self.configuration(
			apiKey: "test-key", application: "website", environment: "production", applicationVersion: configured,
			transport: transport)
		configuration.defaultContextOptions = Context.Options(publishDelay: -1)
		let client = try ABsmartlyClient(configuration: configuration)
		let context = try await withTimeout { try await client.context(units: [.sessionID: "abc"]) }
		context.track("goal")
		try await withTimeout { try await context.publish() }

		let get = try #require(transport.requests.first { $0.method == "GET" })
		let put = try #require(transport.publishes.first)
		#expect(get.headers["X-Application-Version"] == expected, "GET for \(configured.debugDescription)")
		#expect(put.headers["X-Application-Version"] == expected, "PUT for \(configured.debugDescription)")
		// The public configuration keeps the caller's value.
		#expect(client.configuration.applicationVersion == configured)
	}

	@Test func sdkVersionAgent() {
		#expect(SDKVersion.version == "2.0.0")
		#expect(SDKVersion.agent == "absmartly-swift-sdk/\(SDKVersion.version)")
	}

	// The publish workflow refuses a tag where these differ; catch the drift before tagging.
	@Test func sdkVersionMatchesPodspec() throws {
		let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
			.deletingLastPathComponent()
		let podspec = try String(contentsOf: root.appendingPathComponent("ABsmartly.podspec"), encoding: .utf8)
		let line = try #require(podspec.split(separator: "\n").first { $0.contains("spec.version =") })
		#expect(line.contains("'\(SDKVersion.version)'"))
	}

	// MARK: - Retry policy

	// A request is attempted, then retried while `attempt <= retries` after a failure without a
	// response; a 502/503 counts as such a failure only while `attempt < retries`, so the
	// `retries`-th attempt's 502/503 is the final response (then rejected as an HTTP error).

	@Test(arguments: [0, 1, 2, 3])
	func transportErrorsAreRetriedRetriesTimes(retries: Int) async throws {
		for method in ["GET", "PUT"] {
			let (connection, transport) = Self.connection(retries: retries)
			for _ in 0...retries {
				transport.enqueue { _ in throw URLError(.timedOut) }
			}
			let error = try await withTimeout {
				await sdkError {
					if method == "GET" { _ = try await connection.fetchContextData() } else { try await connection.publish(Self.event) }
				}
			}
			guard case .transport = error else {
				Issue.record("\(method): expected a transport error, got \(String(describing: error))")
				continue
			}
			#expect(transport.requests.count == retries + 1, "\(method) retries=\(retries)")
		}
	}

	@Test(arguments: [502, 503])
	func badGatewayAndUnavailableAreRetriedUntilTheLastAttempt(status: Int) async throws {
		for (retries, attempts) in [(0, 1), (1, 1), (2, 2), (3, 3)] {
			for method in ["GET", "PUT"] {
				let (connection, transport) = Self.connection(retries: retries)
				for _ in 0..<10 {
					transport.enqueue(status: status)
				}
				let error = try await withTimeout {
					await sdkError {
						if method == "GET" { _ = try await connection.fetchContextData() } else { try await connection.publish(Self.event) }
					}
				}
				#expect(error == .httpStatus(code: status, message: HTTPURLResponse.localizedString(forStatusCode: status)), "\(method)")
				#expect(transport.requests.count == attempts, "\(method) \(status) retries=\(retries)")
			}
		}
	}

	@Test func retryableStatusThenSuccess() async throws {
		let (connection, transport) = Self.connection(retries: 3)
		transport.enqueue(status: 502)
		transport.enqueue(status: 503)
		let data = try await withTimeout { try await connection.fetchContextData() }
		#expect(data == Fixtures.contextData())
		#expect(transport.requests.count == 3)
	}

	@Test func retriesTransportErrorsUntilSuccess() async throws {
		let (connection, transport) = Self.connection(retries: 3)
		transport.enqueue { _ in throw URLError(.networkConnectionLost) }
		transport.enqueue { _ in throw URLError(.networkConnectionLost) }
		try await withTimeout { try await connection.publish(Self.event) }
		#expect(transport.requests.count == 3)
		#expect(transport.requests.allSatisfy { $0 == transport.requests[0] })
	}

	@Test func transportErrorsAfterARetryableStatusStillGetAllRetries() async throws {
		// Each attempt counts once, whatever failed: 502, error, error, error with retries 3 is 4 attempts.
		let (connection, transport) = Self.connection(retries: 3)
		transport.enqueue(status: 502)
		for _ in 0..<5 {
			transport.enqueue { _ in throw URLError(.timedOut) }
		}
		let error = try await withTimeout { await sdkError { _ = try await connection.fetchContextData() } }
		guard case .transport = error else {
			Issue.record("expected a transport error, got \(String(describing: error))")
			return
		}
		#expect(transport.requests.count == 4)
	}

	@Test(arguments: [400, 401, 404, 500, 504])
	func otherStatusesAreNotRetried(status: Int) async throws {
		let (connection, transport) = Self.connection(retries: 3)
		transport.enqueue(status: status)
		let error = try await withTimeout { await sdkError { try await connection.publish(Self.event) } }
		#expect(error == .httpStatus(code: status, message: HTTPURLResponse.localizedString(forStatusCode: status)))
		#expect(transport.requests.count == 1)
	}

	@Test func malformedBodyIsNotRetried() async throws {
		let (connection, transport) = Self.connection(retries: 3)
		transport.enqueue(status: 200, body: Data("nope".utf8))
		let error = try await withTimeout { await sdkError { _ = try await connection.fetchContextData() } }
		guard case .decoding = error else {
			Issue.record("expected a decoding error, got \(String(describing: error))")
			return
		}
		#expect(transport.requests.count == 1)
	}

	@Test func attemptsAreRetryIntervalApart() async throws {
		let (connection, transport) = Self.connection(retries: 2, retryInterval: 0.05)
		for _ in 0..<3 {
			transport.enqueue { _ in throw URLError(.timedOut) }
		}
		let start = Date()
		_ = try await withTimeout { await sdkError { _ = try await connection.fetchContextData() } }
		#expect(transport.requests.count == 3)
		#expect(Date().timeIntervalSince(start) >= 0.1)
	}

	@Test func cancellationStopsRetrying() async throws {
		let (connection, transport) = Self.connection(retries: 3)
		transport.enqueue { _ in throw CancellationError() }
		let error = try await withTimeout { await sdkError { _ = try await connection.fetchContextData() } }
		#expect(error == .cancelled)
		#expect(transport.requests.count == 1)
	}
}
