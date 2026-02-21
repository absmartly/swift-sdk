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
				Logger.error("Variant config for experiment '\(experimentName)' is not a valid JSON object. Config: '\(config.prefix(100))...'")
				return nil
			}
		} catch {
			Logger.error("Failed to parse variant config for experiment '\(experimentName)': \(error.localizedDescription). Config: '\(config.prefix(100))...'")
			return nil
		}
	}
}
