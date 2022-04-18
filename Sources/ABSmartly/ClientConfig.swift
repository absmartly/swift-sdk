import Foundation

public class ClientConfig {
	public var agent: String = "absmartly-swift-sdk"
	public var retries: Int = 3
	public var timeout: TimeInterval = 3.0

	public var apiKey: String = ""
	public var application: String = ""
	public var endpoint: String = ""
	public var environment: String = ""
	public var applicationVersion: UInt64 = 0

	public init() {
	}

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
