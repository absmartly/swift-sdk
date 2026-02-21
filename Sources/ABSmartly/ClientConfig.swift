import Foundation

public class ClientConfig {
	public private(set) var apiKey: String = ""
	public var application: String = ""
	public var applicationVersion: String = "0"
	public var endpoint: String = ""
	public var environment: String = ""

	public init() {
	}

	public init(
		apiKey: String,
		application: String,
		endpoint: String,
		environment: String,
		applicationVersion: String = "0"
	) {
		self.apiKey = apiKey
		self.application = application
		self.applicationVersion = applicationVersion
		self.endpoint = endpoint
		self.environment = environment
	}

	public convenience init(from data: Data) {
		do {
			if let dict = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: String] {
				self.init(from: dict)
			} else {
				Logger.error("Failed to parse ClientConfig plist: result is not a [String: String] dictionary")
				self.init(from: [:])
			}
		} catch {
			Logger.error("Failed to parse ClientConfig plist: \(error.localizedDescription)")
			self.init(from: [:])
		}
	}

	public convenience init(from dict: [String: String]) {
		self.init(
			apiKey: dict["apikey"] ?? "",
			application: dict["application"] ?? "",
			endpoint: dict["endpoint"] ?? "",
			environment: dict["environment"] ?? "",
			applicationVersion: dict["applicationVersion"] ?? "0"
		)
	}
}
