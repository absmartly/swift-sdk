// sourcery: AutoMockable
protocol Evaluator: AnyObject {
	func evaluate(_ expr: JSON) -> JSON
	func booleanConvert(_ x: JSON) -> JSON
	func numberConvert(_ x: JSON) -> JSON
	func stringConvert(_ x: JSON) -> JSON
	func extractVar(_ path: String) -> JSON
	func compare(_ lhs: JSON, _ rhs: JSON) -> Int?  // returns -1 -> lesser, 0 -> equals, 1 -> greater, null -> undefined comparison}
}
