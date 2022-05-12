import Foundation

public class AudienceMatcher {
	let jsonExpr = JsonExpr()

	public func evaluate(_ audience: String, _ attributes: [String: JSON]) -> Bool? {
		let json = JSON(parseJSON: audience)
		let filter = json["filter"]

		if filter.exists() {
			switch filter.type {
			case .dictionary, .array:
				return jsonExpr.evaluateBooleanExpr(filter, vars: attributes)
			default:
				break
			}
		}

		return nil
	}
}
