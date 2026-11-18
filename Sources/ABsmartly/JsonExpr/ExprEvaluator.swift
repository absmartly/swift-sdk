import Foundation

// The audience and assignment-rule expression language, ported from 1.5.0 onto `JSONValue` with
// its semantics unchanged, including where they differ from javascript-sdk (see
// docs/plans/swift-2.0.md, "Known 1.5.0 divergences").

enum JsonExpr {
	static func evaluateBoolean(_ expr: JSONValue, vars: [String: JSONValue]) -> Bool {
		let evaluator = ExprEvaluator(vars: vars)
		return evaluator.booleanConvert(evaluator.evaluate(expr))
	}

	static func evaluate(_ expr: JSONValue, vars: [String: JSONValue]) -> JSONValue {
		ExprEvaluator(vars: vars).evaluate(expr)
	}
}

final class ExprEvaluator {
	private let vars: JSONValue
	private lazy var formatter: NumberFormatter = {
		let formatter = NumberFormatter()
		formatter.numberStyle = .decimal
		formatter.maximumFractionDigits = 15
		formatter.minimumIntegerDigits = 1
		formatter.decimalSeparator = "."
		formatter.groupingSize = 0
		return formatter
	}()

	init(vars: [String: JSONValue]) {
		self.vars = .object(vars)
	}

	func evaluate(_ expr: JSONValue) -> JSONValue {
		switch expr {
		case .array(let args):
			return and(args)
		case .object(let object):
			// Only the first key is looked at.
			if let (key, value) = object.first {
				return apply(key, value)
			}
			return .null
		default:
			return .null
		}
	}

	private func apply(_ op: String, _ args: JSONValue) -> JSONValue {
		switch op {
		case "and":
			guard case .array(let items) = args else { return .null }
			return and(items)
		case "or":
			guard case .array(let items) = args else { return .null }
			for item in items where booleanConvert(evaluate(item)) {
				return .bool(true)
			}
			return .bool(items.isEmpty)
		case "value":
			return args
		case "var":
			let path = args.objectValue != nil ? (args["path"] ?? .null) : args
			if case .string(let path) = path {
				return extractVar(path)
			}
			return .null
		case "null":
			return .bool(evaluate(args).isNull)
		case "not":
			return .bool(!booleanConvert(evaluate(args)))
		case "in":
			return binary(args, inOperator)
		case "match":
			return binary(args) { MatchOperator.match(self, $0, $1) }
		case "eq":
			return binary(args) { l, r in compare(l, r).map { .bool($0 == 0) } ?? .null }
		case "gt":
			return binary(args) { l, r in compare(l, r).map { .bool($0 > 0) } ?? .null }
		case "gte":
			return binary(args) { l, r in compare(l, r).map { .bool($0 >= 0) } ?? .null }
		case "lt":
			return binary(args) { l, r in compare(l, r).map { .bool($0 < 0) } ?? .null }
		case "lte":
			return binary(args) { l, r in compare(l, r).map { .bool($0 <= 0) } ?? .null }
		case "semver_eq":
			return binary(args) { l, r in SemverComparator.compare(self, l, r).map { .bool($0 == 0) } ?? .null }
		case "semver_gt":
			return binary(args) { l, r in SemverComparator.compare(self, l, r).map { .bool($0 > 0) } ?? .null }
		case "semver_gte":
			return binary(args) { l, r in SemverComparator.compare(self, l, r).map { .bool($0 >= 0) } ?? .null }
		case "semver_lt":
			return binary(args) { l, r in SemverComparator.compare(self, l, r).map { .bool($0 < 0) } ?? .null }
		case "semver_lte":
			return binary(args) { l, r in SemverComparator.compare(self, l, r).map { .bool($0 <= 0) } ?? .null }
		default:
			return .null
		}
	}

	private func and(_ items: [JSONValue]) -> JSONValue {
		for item in items where !booleanConvert(evaluate(item)) {
			return .bool(false)
		}
		return .bool(true)
	}

	// Both operands are evaluated (the right one only when the left is not null); null if either is.
	private func binary(_ args: JSONValue, _ body: (JSONValue, JSONValue) -> JSONValue) -> JSONValue {
		guard case .array(let items) = args else { return .null }
		let lhs = evaluate(items.first ?? .null)
		guard !lhs.isNull else { return .null }
		let rhs = evaluate(items.count > 1 ? items[1] : .null)
		guard !rhs.isNull else { return .null }
		return body(lhs, rhs)
	}

	private func inOperator(_ haystack: JSONValue, _ needle: JSONValue) -> JSONValue {
		switch haystack {
		case .array(let items):
			for item in items where compare(item, needle) == 0 {
				return .bool(true)
			}
			return .bool(false)
		case .string(let string):
			guard let needle = stringConvert(needle) else { return .bool(false) }
			return .bool(string.contains(needle))
		case .object(let object):
			guard let needle = stringConvert(needle) else { return .bool(false) }
			return .bool(object[needle] != nil)
		default:
			return .null
		}
	}

	// Numbers are true when their integer part is non-zero.
	func booleanConvert(_ x: JSONValue) -> Bool {
		switch x {
		case .bool(let value):
			return value
		case .int(let value):
			return value != 0
		case .double(let value):
			if value.isNaN { return false }
			guard let truncated = Int64(exactly: value.rounded(.towardZero)) else { return true }
			return truncated != 0
		case .string(let value):
			return value != "false" && value != "0" && value != ""
		case .null:
			return false
		case .array, .object:
			return true
		}
	}

	func numberConvert(_ x: JSONValue) -> Double? {
		switch x {
		case .int(let value):
			return Double(value)
		case .double(let value):
			return value
		case .bool(let value):
			return value ? 1 : 0
		case .string(let value):
			return Double(value)
		default:
			return nil
		}
	}

	// Numbers are formatted with up to 15 fraction digits, without grouping.
	func stringConvert(_ x: JSONValue) -> String? {
		switch x {
		case .string(let value):
			return value
		case .bool(let value):
			return value ? "true" : "false"
		case .int(let value):
			return formatter.string(from: NSNumber(value: value))
		case .double(let value):
			return formatter.string(from: NSNumber(value: value))
		default:
			return nil
		}
	}

	func extractVar(_ path: String) -> JSONValue {
		var target = vars
		for fragment in path.split(separator: "/") {
			switch target {
			case .array(let items):
				guard let index = Int(fragment), items.indices.contains(index) else { return .null }
				target = items[index]
			case .object(let object):
				guard let value = object[String(fragment)] else { return .null }
				target = value
			default:
				return .null
			}
		}
		return target
	}

	/// -1, 0 or 1, or nil when the operands cannot be compared.
	func compare(_ lhs: JSONValue, _ rhs: JSONValue) -> Int? {
		switch (lhs, rhs) {
		case (.null, .null):
			return 0
		case (.null, _), (_, .null):
			return nil
		default:
			break
		}

		switch lhs {
		case .int, .double:
			guard let rvalue = numberConvert(rhs) else { return nil }
			let lvalue = lhs.doubleValue!
			return lvalue == rvalue ? 0 : (lvalue > rvalue ? 1 : -1)
		case .string(let lvalue):
			guard let rvalue = stringConvert(rhs) else { return nil }
			return lvalue.compare(rvalue).rawValue
		case .bool(let lvalue):
			let rvalue = booleanConvert(rhs)
			return lvalue == rvalue ? 0 : (lvalue ? 1 : -1)
		default:
			return Self.deepEquals(lhs, rhs) ? 0 : nil
		}
	}

	// Arrays and objects compare equal like Foundation collections: numbers and booleans by numeric
	// value, strings by UTF-16 code units.
	static func deepEquals(_ lhs: JSONValue, _ rhs: JSONValue) -> Bool {
		switch (lhs, rhs) {
		case (.array(let l), .array(let r)):
			return l.count == r.count && zip(l, r).allSatisfy { deepEquals($0, $1) }
		case (.object(let l), .object(let r)):
			return l.count == r.count && l.allSatisfy { key, value in r[key].map { deepEquals(value, $0) } ?? false }
		case (.string(let l), .string(let r)):
			return l.utf16.elementsEqual(r.utf16)
		case (.null, .null):
			return true
		default:
			guard let l = scalarNumber(lhs), let r = scalarNumber(rhs) else { return false }
			return NSArray(object: l).isEqual(to: [r])
		}
	}

	private static func scalarNumber(_ x: JSONValue) -> NSNumber? {
		switch x {
		case .bool(let value): return NSNumber(value: value)
		case .int(let value): return NSNumber(value: value)
		case .double(let value): return NSNumber(value: value)
		default: return nil
		}
	}
}
