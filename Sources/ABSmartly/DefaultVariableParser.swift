import Foundation

public class DefaultVariableParser: VariableParser {
	public func parse(experimentName: String, config: String) -> [String: JSON]? {
		let data = Data(config.utf8)
		do {
			let parsed = try JSON(data: data, options: .mutableContainers)
			return parsed.dictionary
		} catch {
			Logger.error(error.localizedDescription)
		}
		return nil
	}
}
