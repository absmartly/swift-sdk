// sourcery: AutoMockable
protocol Operator: AnyObject {
	func evaluate(_ evaluator: Evaluator, _ args: JSON) -> JSON
}
