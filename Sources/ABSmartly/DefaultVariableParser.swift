import Foundation

public class DefaultVariableParser: VariableParser {
	public func parse(experimentName: String, config: String) -> [String: Any?]? {
		let data = Data(config.utf8)
		do {
			if let parsed = try JSONSerialization.jsonObject(with: data, options: .mutableContainers) as? [String: Any?]
			{
				return parsed
			}
		} catch {
			Logger.error(error.localizedDescription)
		}
		return nil
	}
}
