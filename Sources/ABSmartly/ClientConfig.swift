import Foundation

public class ClientConfig {
	public var apiKey: String = ""
	public var application: String = ""
	public var endpoint: String = ""
	public var environment: String = ""

	public init() {
	}

	public init(
		apiKey: String, application: String, endpoint: String, environment: String
	) {
		self.apiKey = apiKey
		self.application = application
		self.endpoint = endpoint
		self.environment = environment
	}

	public convenience init(from data: Data) {
		let dict = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: String]
		self.init(from: dict ?? [:])
	}

	public convenience init(from dict: [String: String]) {
		self.init(
			apiKey: dict["apikey"] ?? "", application: dict["application"] ?? "", endpoint: dict["endpoint"] ?? "",
			environment: dict["environment"] ?? "")
	}
}
