import Foundation

public class AudienceMatcher {
	let jsonExpr = JsonExpr()

	public func evaluate(_ audience: String, _ attributes: [String: JSON]) -> Bool? {
		let json = JSON(parseJSON: audience)
		let filter = json["filter"]

		guard filter.exists() else {
			Logger.error("Audience JSON missing 'filter' field. Audience: '\(audience.prefix(100))...'")
			return nil
		}

		switch filter.type {
		case .dictionary, .array:
			return jsonExpr.evaluateBooleanExpr(filter, vars: attributes)
		default:
			Logger.error("Audience filter has invalid type: \(filter.type), expected dictionary or array. Audience: '\(audience.prefix(100))...'")
			return nil
		}
	}
}
