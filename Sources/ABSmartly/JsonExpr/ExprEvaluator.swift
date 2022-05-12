import Foundation

final class ExprEvaluator: Evaluator {
	let operators: [String: Operator]
	let vars: JSON
	let formatter: NumberFormatter = NumberFormatter()

	init(operators: [String: Operator], vars: [String: JSON]?) {
		self.operators = operators
		self.vars = vars != nil ? JSON(vars!) : JSON()

		formatter.numberStyle = .decimal
		formatter.maximumFractionDigits = 15
		formatter.minimumIntegerDigits = 1
		formatter.decimalSeparator = "."
		formatter.groupingSize = 0
	}

	func evaluate(_ expr: JSON) -> JSON {
		if expr.type == .array {
			if let and = operators["and"] {
				return and.evaluate(self, expr)
			}
		} else if let dict = expr.dictionary {
			for (key, value) in dict {
				if let op = operators[key] {
					return op.evaluate(self, value)
				}
				break
			}
		}
		return JSON.null
	}

	func booleanConvert(_ x: JSON) -> JSON {
		switch x.type {
		case .bool:
			return JSON(x.boolValue)
		case .number:
			return JSON(x.int64Value != 0)
		case .string:
			if let v = x.string {
				return JSON(v != "false" && v != "0" && v != "")
			}
		default:
			break
		}

		return JSON(x.type != .null)
	}

	func numberConvert(_ x: JSON) -> JSON {
		switch x.type {
		case .number:
			return JSON(x.doubleValue)
		case .bool:
			return JSON(x.boolValue ? 1 : 0)
		case .string:
			if let double = Double(x.stringValue) {
				return JSON(double)
			}
			break
		default:
			break
		}
		return JSON.null
	}

	func stringConvert(_ x: JSON) -> JSON {
		switch x.type {
		case .string:
			return JSON(x.stringValue)
		case .bool:
			return JSON(x.boolValue ? "true" : "false")
		case .number:
			if let string = formatter.string(from: x.number!) {
				return JSON(string)
			}
			break
		default:
			break
		}
		return JSON.null
	}

	func extractVar(_ path: String) -> JSON {
		let frags = path.split(separator: "/")

		var target = vars

		for frag in frags {
			var value: JSON? = nil
			switch target.type {
			case .array:
				if let index = Int(frag) {
					value = target[index]
				}
				break
			case .dictionary:
				value = target[String(frag)]
				break
			default:
				break
			}

			if let value = value {
				target = value
				continue
			}

			return JSON.null
		}

		return target
	}

	func compare(_ lhs: JSON, _ rhs: JSON) -> Int? {
		switch (lhs.type, rhs.type) {
		case (.null, .null):
			return 0
		case (.null, _), (_, .null):
			return nil
		default:
			break
		}

		switch lhs.type {
		case .number:
			if let rvalue = numberConvert(rhs).number?.doubleValue {
				let lvalue = lhs.doubleValue
				return (lvalue == rvalue) ? 0 : (lvalue > rvalue ? 1 : -1)
			}
			break
		case .string:
			if let rvalue = stringConvert(rhs).string {
				let lvalue = lhs.stringValue
				return lvalue.compare(rvalue).rawValue
			}
		case .bool:
			if let rvalue = booleanConvert(rhs).bool {
				let lvalue = lhs.boolValue
				return (lvalue == rvalue) ? 0 : (lvalue ? 1 : -1)
			}
			break
		default:
			if lhs.type == rhs.type && lhs == rhs {
				return 0
			}
		}

		return nil
	}
}
