import Foundation

/// The entry point of the SDK: holds the collector configuration and creates contexts.
///
/// ```swift
/// let client = try ABsmartlyClient(
///     endpoint: URL(string: "https://acme.absmartly.io/v1")!,
///     apiKey: apiKey, application: "ios", environment: .production)
/// let context = try await client.context(units: [.deviceID: deviceID])
/// ```
public final class ABsmartlyClient: Sendable {
	/// An environment name. `.production`, `.staging` and `.development` are the common ones; any
	/// string literal works.
	public struct Environment: RawRepresentable, Hashable, Sendable, ExpressibleByStringLiteral {
		public let rawValue: String

		public init(rawValue: String) {
			self.rawValue = rawValue
		}

		public init(stringLiteral value: String) {
			rawValue = value
		}

		public static let production: Environment = "production"
		public static let staging: Environment = "staging"
		public static let development: Environment = "development"
	}

	/// Everything the client needs; all of it is optional except the four collector values.
	public struct Configuration: Sendable {
		/// The collector endpoint, e.g. `https://acme.absmartly.io/v1`; requests go to `<endpoint>/context`.
		public var endpoint: URL
		public var apiKey: String
		public var application: String
		public var environment: Environment
		/// Sent as `X-Application-Version`: 1–18 ASCII digits (after trimming) are sent as given,
		/// anything else as `"0"`, because the collector only accepts an integer.
		public var applicationVersion: String = "0"
		/// Seconds allowed for each request.
		public var timeout: TimeInterval = 3
		/// How many times a request is retried after a failure without a response, or a 502/503.
		public var retries: Int = 3
		/// Seconds between attempts.
		public var retryInterval: TimeInterval = 0.5
		/// Sends the requests; a `URLSessionTransport` with `timeout` when nil.
		public var transport: (any Transport)?
		/// Receives the events of every context whose options set no logger of their own.
		public var eventLogger: EventLogger?
		/// The context options used when `context(...)` is called without options.
		public var defaultContextOptions = Context.Options()

		public init(endpoint: URL, apiKey: String, application: String, environment: Environment) {
			self.endpoint = endpoint
			self.apiKey = apiKey
			self.application = application
			self.environment = environment
		}
	}

	public let configuration: Configuration
	let connection: Connection
	let clock: Clock

	/// Validates the configuration. Throws `.invalidConfiguration` (with the 1.x message) for an empty
	/// endpoint, API key, application or environment.
	public convenience init(configuration: Configuration) throws(ABsmartlyError) {
		try self.init(configuration: configuration, clock: SystemClock())
	}

	public convenience init(
		endpoint: URL, apiKey: String, application: String, environment: Environment,
		applicationVersion: String = "0", eventLogger: EventLogger? = nil
	) throws(ABsmartlyError) {
		var configuration = Configuration(
			endpoint: endpoint, apiKey: apiKey, application: application, environment: environment)
		configuration.applicationVersion = applicationVersion
		configuration.eventLogger = eventLogger
		try self.init(configuration: configuration)
	}

	init(configuration: Configuration, clock: Clock) throws(ABsmartlyError) {
		if configuration.endpoint.absoluteString.isEmpty {
			throw .invalidConfiguration("Missing Endpoint configuration")
		}
		if configuration.apiKey.isEmpty {
			throw .invalidConfiguration("Missing APIKey configuration")
		}
		if configuration.application.isEmpty {
			throw .invalidConfiguration("Missing Application configuration")
		}
		if configuration.environment.rawValue.isEmpty {
			throw .invalidConfiguration("Missing Environment configuration")
		}
		self.configuration = configuration
		self.clock = clock
		connection = Connection(configuration: configuration)
	}

	/// Fetches the context data (`GET <endpoint>/context`), e.g. to pass it to a server-rendered app.
	public func fetchContextData() async throws(ABsmartlyError) -> ContextData {
		try await connection.fetchContextData()
	}

	/// Creates a context and returns once its data is loaded. Throws the load error; the failed
	/// context is not returned (use `makeContext` to keep a context that may fail).
	public func context(
		units: [UnitType: String] = [:], attributes: [String: JSONValue] = [:], overrides: [String: Int] = [:],
		customAssignments: [String: Int] = [:], options: Context.Options? = nil
	) async throws(ABsmartlyError) -> Context {
		let context = makeContext(
			units: units, attributes: attributes, overrides: overrides, customAssignments: customAssignments,
			options: options)
		try await context.ready()
		return context
	}

	/// Creates a context and starts loading its data; it is usable at once (reads return defaults
	/// until it is ready). `try await context.ready()` waits for it.
	public func makeContext(
		units: [UnitType: String] = [:], attributes: [String: JSONValue] = [:], overrides: [String: Int] = [:],
		customAssignments: [String: Int] = [:], options: Context.Options? = nil
	) -> Context {
		let context = newContext(units, attributes, overrides, customAssignments, options)
		let connection = connection
		context.load { () async throws(ABsmartlyError) -> ContextData in
			try await connection.fetchContextData()
		}
		return context
	}

	/// Creates a context from data fetched earlier (`fetchContextData()` or your own server). The
	/// context is ready when this returns.
	public func context(
		units: [UnitType: String] = [:], attributes: [String: JSONValue] = [:], overrides: [String: Int] = [:],
		customAssignments: [String: Int] = [:], options: Context.Options? = nil, data: ContextData
	) -> Context {
		let context = newContext(units, attributes, overrides, customAssignments, options)
		context.install(data)
		return context
	}

	private func newContext(
		_ units: [UnitType: String], _ attributes: [String: JSONValue], _ overrides: [String: Int],
		_ customAssignments: [String: Int], _ options: Context.Options?
	) -> Context {
		var options = options ?? configuration.defaultContextOptions
		if options.eventLogger == nil {
			options.eventLogger = configuration.eventLogger
		}
		return Context(
			connection: connection, clock: clock, options: options,
			application: configuration.application, environment: configuration.environment.rawValue,
			units: units.map { ($0.key.rawValue, ContextState.UID.string($0.value)) },
			attributes: attributes, overrides: overrides, customAssignments: customAssignments)
	}
}

/// The time source of a context: event timestamps and the publish and refresh timers.
protocol Clock: Sendable {
	/// Milliseconds since the Unix epoch.
	func millis() -> Int64
	/// Suspends for `seconds`; throws `CancellationError` when the task is cancelled.
	func sleep(seconds: TimeInterval) async throws
}

struct SystemClock: Clock {
	func millis() -> Int64 {
		Int64(Date().timeIntervalSince1970 * 1000)
	}

	func sleep(seconds: TimeInterval) async throws {
		try await Task.sleep(nanoseconds: UInt64(max(0, min(seconds, 1e9)) * 1_000_000_000))
	}
}
