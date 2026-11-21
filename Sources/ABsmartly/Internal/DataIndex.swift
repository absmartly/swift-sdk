import Foundation

/// The experiment data a context reads, indexed once per `ContextData`: variables parsed, rules and
/// audiences parsed, custom fields typed. Immutable and shared by every read.
struct DataIndex: Sendable {
	// A class, so reads share one entry instead of copying its fields.
	final class Entry: Sendable {
		let data: Experiment
		/// One variable map per variant (empty when the variant has no object config).
		let variables: [[String: JSONValue]]
		/// Parsed `data.assignmentRules`; nil when there are none or they are not valid JSON.
		let rules: [ExprValue]?
		let audience: AudienceMatcher.Audience
		let customFields: [String: CustomField]

		init(
			data: Experiment, variables: [[String: JSONValue]], rules: [ExprValue]?,
			audience: AudienceMatcher.Audience, customFields: [String: CustomField]
		) {
			self.data = data
			self.variables = variables
			self.rules = rules
			self.audience = audience
			self.customFields = customFields
		}
	}

	struct CustomField: Sendable {
		let type: String
		let value: JSONValue?
	}

	let data: ContextData
	let experiments: [String: Entry]
	/// For each variable key, the experiments whose variants define it, by ascending unique id.
	let variableExperiments: [String: [Entry]]

	static let empty = DataIndex(ContextData())

	init(_ data: ContextData) {
		var experiments: [String: Entry] = [:]
		var variableExperiments: [String: [Entry]] = [:]

		for experiment in data.experiments {
			var rules: [ExprValue]?
			if let assignmentRules = experiment.assignmentRules, !assignmentRules.isEmpty {
				rules = AudienceMatcher.parseRules(assignmentRules)
				if rules == nil {
					Log.error("Failed to parse assignmentRules for experiment '\(experiment.name)'.")
				}
			}

			var variables: [[String: JSONValue]] = []
			var keys: [String] = []
			for variant in experiment.variants {
				if let config = variant.config, !config.isEmpty,
					let parsed = Self.parseVariables(experimentName: experiment.name, config: config)
				{
					keys.append(contentsOf: parsed.keys)
					variables.append(parsed)
				} else {
					variables.append([:])
				}
			}

			let entry = Entry(
				data: experiment,
				variables: variables,
				rules: rules,
				audience: experiment.audience.map(AudienceMatcher.parseAudience) ?? .none,
				customFields: Self.customFields(experiment))

			for key in keys {
				variableExperiments[key, default: []].insertUniqueSorted(entry) { $0.data.id < $1.data.id }
			}
			experiments[experiment.name] = entry
		}

		self.data = data
		self.experiments = experiments
		self.variableExperiments = variableExperiments
	}

	// A variant config must be a JSON object; anything else gives the variant no variables.
	private static func parseVariables(experimentName: String, config: String) -> [String: JSONValue]? {
		let truncated = config.count > 100 ? "\(config.prefix(100))..." : config
		do {
			let parsed = try JSONValue(parsing: config)
			guard case .object(let object) = parsed else {
				Log.error("Variant config for experiment '\(experimentName)' is not a valid JSON object. Config: '\(truncated)'")
				return nil
			}
			return object
		} catch {
			Log.error("Failed to parse variant config for experiment '\(experimentName)': \(error). Config: '\(truncated)'")
			return nil
		}
	}

	// Typed as in 1.5.0: `json*` parsed (a JSON `null` is no value), `boolean*` true only for "true",
	// `number*` a number when it parses, anything else the text.
	private static func customFields(_ experiment: Experiment) -> [String: CustomField] {
		var fields: [String: CustomField] = [:]
		for field in experiment.customFieldValues {
			guard let type = field.type, let name = field.name else { continue }

			var value: JSONValue?
			if let text = field.value {
				if type.hasPrefix("json") {
					do {
						let parsed = try JSONValue(parsing: text)
						// Not a ternary: `nil` there would become `JSONValue.null` (ExpressibleByNilLiteral).
						if !parsed.isNull {
							value = parsed
						}
					} catch {
						let truncated = text.count > 100 ? "\(text.prefix(100))..." : text
						Log.error(
							"Failed to parse JSON custom field '\(name)' for experiment '\(experiment.name)': \(error). Original value: '\(truncated)'"
						)
					}
				} else if type.hasPrefix("boolean") {
					value = .bool(text == "true")
				} else if type.hasPrefix("number") {
					value = Double(text).map(JSONValue.double)
				} else {
					value = .string(text)
				}
			}
			fields[name] = CustomField(type: type, value: value)
		}
		return fields
	}
}

extension Array {
	// Binary-search insert; an element ordered equal to an existing one is not inserted.
	mutating func insertUniqueSorted(_ element: Element, isSorted: (Element, Element) -> Bool) {
		var left = 0
		var right = count - 1
		while left <= right {
			let mid = left + (right - left) / 2
			if isSorted(self[mid], element) {
				left = mid + 1
			} else if isSorted(element, self[mid]) {
				right = mid - 1
			} else {
				return
			}
		}
		insert(element, at: left)
	}
}
