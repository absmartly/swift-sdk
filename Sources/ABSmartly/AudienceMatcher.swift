import Foundation

public class AudienceMatcher {
	let jsonExpr = JsonExpr()

	public func evaluate(_ audience: String, _ attributes: [String: JSON]) -> Bool? {
		let json = JSON(parseJSON: audience)
		let filter = json["filter"]

		// No filter (e.g. "null" or "{}") means the experiment has no audience.
		guard filter.exists() else {
			return nil
		}

		switch filter.type {
		case .dictionary, .array:
			return jsonExpr.evaluateBooleanExpr(filter, vars: attributes)
		default:
			let truncated = audience.count > 100 ? "\(audience.prefix(100))..." : audience
			Logger.error("Audience filter has invalid type: \(filter.type), expected dictionary or array. Audience: '\(truncated)'")
			return nil
		}
	}
}
