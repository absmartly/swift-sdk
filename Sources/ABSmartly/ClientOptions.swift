import Foundation

public struct ClientOptions {
	let agent: String = "absmartly-swift-sdk"
	let retries: Int
	let timeout: TimeInterval

	public var apiKey: String
	public var application: String
	public var endpoint: String
	public var environment: String
	public var applicationVersion: UInt64

	public init(
		apiKey: String, application: String, endpoint: String, environment: String, applicationVersion: UInt64 = 0,
		retries: Int = 3, timeout: TimeInterval = 3.0
	) {
		self.apiKey = apiKey
		self.application = application
		self.endpoint = endpoint
		self.environment = environment
		self.applicationVersion = applicationVersion
		self.retries = retries
		self.timeout = timeout
	}
}
