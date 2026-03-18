import Foundation

public class DefaultVariableParser: VariableParser {
	public init() {}

	public func parse(experimentName: String, config: String) -> [String: JSON]? {
		let data = Data(config.utf8)
		do {
			let parsed = try JSON(data: data, options: .mutableContainers)
			if let dictionary = parsed.dictionary {
				return dictionary
			} else {
				let truncated = config.count > 100 ? "\(config.prefix(100))..." : config
				Logger.error("Variant config for experiment '\(experimentName)' is not a valid JSON object. Config: '\(truncated)'")
				return nil
			}
		} catch {
			let truncated = config.count > 100 ? "\(config.prefix(100))..." : config
			Logger.error("Failed to parse variant config for experiment '\(experimentName)': \(error.localizedDescription). Config: '\(truncated)'")
			return nil
		}
	}
}
