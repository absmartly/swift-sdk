import Foundation
import Testing

@testable import ABsmartly

@Suite struct ModelTests {
	static func decode(_ json: String) throws -> ContextData {
		try JSONDecoder().decode(ContextData.self, from: Data(json.utf8))
	}

	static func experiment(_ fields: String) throws -> Experiment {
		try #require(try decode(#"{"experiments":[{"name":"exp"\#(fields.isEmpty ? "" : ",")\#(fields)}]}"#).experiments.first)
	}

	// MARK: - ContextData decoding

	@Test func contextDataDeserialization() throws {
		let contextData = try JSONDecoder().decode(ContextData.self, from: Fixtures.data("context"))
		try #require(contextData.experiments.count == 4)

		let e0 = contextData.experiments[0]
		#expect(e0.id == 1)
		#expect(e0.name == "exp_test_ab")
		#expect(e0.unitType == "session_id")
		#expect(e0.iteration == 1)
		#expect(e0.seedHi == 3_603_515)
		#expect(e0.seedLo == 233_373_850)
		#expect(e0.split == [0.5, 0.5])
		#expect(e0.trafficSeedHi == 449_867_249)
		#expect(e0.trafficSeedLo == 455_443_629)
		#expect(e0.trafficSplit == [0.0, 1.0])
		#expect(e0.fullOnVariant == 0)
		#expect(e0.applications.count == 1)
		#expect(e0.applications.first?.name == "website")
		try #require(e0.variants.count == 2)
		#expect(e0.variants[0].name == "A")
		#expect(e0.variants[0].config == nil)
		#expect(e0.variants[1].name == "B")
		#expect(e0.variants[1].config == "{\"banner.border\":1,\"banner.size\":\"large\"}")

		let e1 = contextData.experiments[1]
		#expect(e1.id == 2)
		#expect(e1.name == "exp_test_abc")
		#expect(e1.unitType == "session_id")
		#expect(e1.iteration == 1)
		#expect(e1.seedHi == 55_006_150)
		#expect(e1.seedLo == 47_189_152)
		#expect(e1.split == [0.34, 0.33, 0.33])
		#expect(e1.trafficSeedHi == 705_671_872)
		#expect(e1.trafficSeedLo == 212_903_484)
		#expect(e1.trafficSplit == [0.0, 1.0])
		#expect(e1.fullOnVariant == 0)
		#expect(e1.applications.count == 1)
		#expect(e1.applications.first?.name == "website")
		try #require(e1.variants.count == 3)
		#expect(e1.variants[0].name == "A")
		#expect(e1.variants[0].config == nil)
		#expect(e1.variants[1].name == "B")
		#expect(e1.variants[1].config == "{\"button.color\":\"blue\"}")
		#expect(e1.variants[2].name == "C")
		#expect(e1.variants[2].config == "{\"button.color\":\"red\"}")

		let e2 = contextData.experiments[2]
		#expect(e2.id == 3)
		#expect(e2.name == "exp_test_not_eligible")
		#expect(e2.unitType == "user_id")
		#expect(e2.iteration == 1)
		#expect(e2.seedHi == 503_266_407)
		#expect(e2.seedLo == 144_942_754)
		#expect(e2.split == [0.34, 0.33, 0.33])
		#expect(e2.trafficSeedHi == 87_768_905)
		#expect(e2.trafficSeedLo == 511_357_582)
		#expect(e2.trafficSplit == [0.99, 0.01])
		#expect(e2.fullOnVariant == 0)
		#expect(e2.applications.count == 1)
		#expect(e2.applications.first?.name == "website")
		try #require(e2.variants.count == 3)
		#expect(e2.variants[0].name == "A")
		#expect(e2.variants[0].config == nil)
		#expect(e2.variants[1].name == "B")
		#expect(e2.variants[1].config == "{\"card.width\":\"80%\"}")
		#expect(e2.variants[2].name == "C")
		#expect(e2.variants[2].config == "{\"card.width\":\"75%\"}")

		let e3 = contextData.experiments[3]
		#expect(e3.id == 4)
		#expect(e3.name == "exp_test_fullon")
		#expect(e3.unitType == "session_id")
		#expect(e3.iteration == 1)
		#expect(e3.seedHi == 856_061_641)
		#expect(e3.seedLo == 990_838_475)
		#expect(e3.split == [0.25, 0.25, 0.25, 0.25])
		#expect(e3.trafficSeedHi == 360_868_579)
		#expect(e3.trafficSeedLo == 330_937_933)
		#expect(e3.trafficSplit == [0.0, 1.0])
		#expect(e3.fullOnVariant == 2)
		#expect(e3.applications.count == 1)
		#expect(e3.applications.first?.name == "website")
		try #require(e3.variants.count == 4)
		#expect(e3.variants[0].name == "A")
		#expect(e3.variants[0].config == nil)
		#expect(e3.variants[1].name == "B")
		#expect(e3.variants[1].config == "{\"submit.color\":\"red\",\"submit.shape\":\"circle\"}")
		#expect(e3.variants[2].name == "C")
		#expect(e3.variants[2].config == "{\"submit.color\":\"blue\",\"submit.shape\":\"rect\"}")
		#expect(e3.variants[3].name == "D")
		#expect(e3.variants[3].config == "{\"submit.color\":\"green\",\"submit.shape\":\"square\"}")
	}

	@Test func oneMalformedExperimentDoesNotFailTheWholeContext() throws {
		let contextData = try Self.decode(
			"""
			{"experiments": [
				{"id": 1, "name": "exp_bad", "iteration": "1", "unitType": "session_id",
				 "customFieldValues": "oops", "applications": 7},
				{"id": 2, "name": "exp_good", "iteration": 3, "unitType": "session_id", "split": [0.5, 0.5],
				 "variants": [{"name": "A", "config": null}, {"name": "B", "config": null}]}
			]}
			""")

		#expect(contextData.experiments.map(\.name) == ["exp_bad", "exp_good"])
		let bad = contextData.experiments[0]
		#expect(bad.id == 1)
		#expect(bad.iteration == 0)
		#expect(bad.unitType == "session_id")
		#expect(bad.variants == [])
		#expect(bad.customFieldValues == [])
		#expect(bad.applications == [])
		#expect(contextData.experiments[1].iteration == 3)
		#expect(contextData.experiments[1].variants.count == 2)
	}

	@Test func experimentWithoutNameStillFailsToDecode() {
		#expect(throws: DecodingError.self) { try Self.decode(#"{"experiments": [{"id": 1}]}"#) }
		#expect(throws: DecodingError.self) { try Self.decode(#"{"experiments": [{"id": 1, "name": null}]}"#) }
		#expect(throws: DecodingError.self) { try Self.decode(#"{"experiments": [{"id": 1, "name": 5}]}"#) }
	}

	@Test func applicationEquality() throws {
		let contextData = try JSONDecoder().decode(ContextData.self, from: Fixtures.data("context"))
		let application = try #require(contextData.experiments[0].applications.first)
		#expect(application == ExperimentApplication(name: "website"))
	}

	@Test func experimentsListIsRequired() {
		// `experiments` itself is not lenient: it must be present and an array.
		#expect(throws: DecodingError.self) { try Self.decode("{}") }
		#expect(throws: DecodingError.self) { try Self.decode(#"{"experiments": null}"#) }
		#expect(throws: DecodingError.self) { try Self.decode(#"{"experiments": {}}"#) }
		#expect(throws: DecodingError.self) { try Self.decode("[]") }
	}

	@Test func missingKnownFieldsTakeTheirDefaults() throws {
		let experiment = try Self.experiment("")
		#expect(
			experiment
				== Experiment(
					id: 0, name: "exp", unitType: nil, iteration: 0, seedHi: 0, seedLo: 0, split: [], trafficSeedHi: 0,
					trafficSeedLo: 0, trafficSplit: [], fullOnVariant: 0, applications: [], variants: [],
					audienceStrict: false, audience: nil, customFieldValues: [], assignmentRules: nil))
	}

	@Test func nullKnownFieldsTakeTheirDefaults() throws {
		let fields = [
			"id", "unitType", "iteration", "seedHi", "seedLo", "split", "trafficSeedHi", "trafficSeedLo", "trafficSplit",
			"fullOnVariant", "applications", "variants", "audienceStrict", "audience", "customFieldValues",
			"assignmentRules",
		].map { "\"\($0)\":null" }.joined(separator: ",")
		let experiment = try Self.experiment(fields)
		let defaults = try Self.experiment("")
		#expect(experiment == defaults)
	}

	@Test(arguments: [
		#""id":"1""#, #""id":1.5"#, #""id":true"#, #""unitType":5"#, #""iteration":"1""#, #""seedHi":[]"#,
		#""seedLo":{}"#, #""split":"0.5""#, #""split":[0.5,"x"]"#, #""trafficSeedHi":"x""#, #""trafficSeedLo":false"#,
		#""trafficSplit":{}"#, #""fullOnVariant":"2""#, #""applications":7"#, #""applications":[{"name":5}]"#,
		#""variants":"A""#, #""variants":[{"name":"A","config":{}}]"#, #""audienceStrict":"true""#,
		#""audienceStrict":1"#, #""audience":{}"#, #""customFieldValues":"oops""#,
		#""customFieldValues":[{"name":"f","type":"text","value":5}]"#, #""assignmentRules":{"rules":[]}"#,
	])
	func wrongTypedFieldTakesItsDefault(field: String) throws {
		let experiment = try Self.experiment(field)
		let defaults = try Self.experiment("")
		#expect(experiment == defaults, "\(field)")
	}

	@Test func wrongTypedFieldDoesNotAffectItsNeighbours() throws {
		let experiment = try Self.experiment(#""id":7,"iteration":"x","seedHi":11,"variants":5,"split":[1]"#)
		#expect(experiment.id == 7)
		#expect(experiment.iteration == 0)
		#expect(experiment.seedHi == 11)
		#expect(experiment.variants == [])
		#expect(experiment.split == [1])
	}

	@Test func unknownFieldsAreIgnoredAtEveryLevel() throws {
		let contextData = try Self.decode(
			"""
			{"experiments":[{"name":"exp","id":3,"futureField":{"deep":[1,2]},"randomizationType":"switchback",
			"applications":[{"name":"website","id":9,"extra":true}],
			"variants":[{"name":"A","config":null,"extra":1},{"name":"B","config":"{}","weight":0.5}],
			"customFieldValues":[{"name":"owner","type":"text","value":"me","id":4}]}],
			"serverTime":123,"meta":{"x":null}}
			""")
		let experiment = try #require(contextData.experiments.first)
		#expect(experiment.id == 3)
		#expect(experiment.applications == [ExperimentApplication(name: "website")])
		#expect(
			experiment.variants == [
				ExperimentVariant(name: "A", config: nil), ExperimentVariant(name: "B", config: "{}"),
			])
		#expect(experiment.customFieldValues == [CustomFieldValue(name: "owner", type: "text", value: "me")])
	}

	@Test func nestedModelsHaveOptionalFields() throws {
		let experiment = try Self.experiment(
			#""applications":[{}],"variants":[{}],"customFieldValues":[{"name":null,"type":null,"value":null}]"#)
		#expect(experiment.applications == [ExperimentApplication(name: nil)])
		#expect(experiment.variants == [ExperimentVariant(name: nil, config: nil)])
		#expect(experiment.customFieldValues == [CustomFieldValue(name: nil, type: nil, value: nil)])
	}

	@Test func numericFieldsAcceptWholeFloats() throws {
		// JSONDecoder reads 1.0 as Int 1; a fractional value is wrong-typed.
		let experiment = try Self.experiment(#""id":2.0,"iteration":3e0,"split":[1,0]"#)
		#expect(experiment.id == 2)
		#expect(experiment.iteration == 3)
		#expect(experiment.split == [1.0, 0.0])
	}

	@Test func assignmentRulesAreKeptAsAString() throws {
		let rules = #"{"rules":[]}"#
		let experiment = try Self.experiment(#""assignmentRules":\#(String(describing: JSONValue.string(rules)))"#)
		#expect(experiment.assignmentRules == rules)
	}

	@Test func contextDataRoundTrips() throws {
		let data = Fixtures.contextData()
		let reencoded = try JSONDecoder().decode(ContextData.self, from: try JSONEncoder().encode(data))
		#expect(reencoded == data)
	}

	// MARK: - Publish body encoding

	@Test func serialize() throws {
		let units = [
			PublishEvent.Unit(type: "session_id", uid: "pAE3a1i5Drs5mKRNq56adA"),
			PublishEvent.Unit(type: "user_id", uid: "JfnnlDI7RTiF9RgfG2JNCw"),
		]

		let attributes = [
			PublishEvent.Attribute(name: "attr1", value: "value1", setAt: 123_456_000),
			PublishEvent.Attribute(name: "attr2", value: "value2", setAt: 123_456_789),
			PublishEvent.Attribute(name: "attr2", value: .null, setAt: 123_450_000),
			PublishEvent.Attribute(name: "attr3", value: ["nested": ["value": 5]], setAt: 123_470_000),
			PublishEvent.Attribute(name: "attr4", value: ["nested": [1, 2, "test"]], setAt: 123_480_000),
		]

		let exposures = [
			Exposure(
				id: 1, name: "exp_test_ab", unit: "session_id", variant: 1, exposedAt: 123_470_000, assigned: true,
				eligible: true, overridden: false, fullOn: false, custom: false, audienceMismatch: true,
				ruleOverride: false)
		]

		let properties: [String: JSONValue] = ["amount": 6, "value": 5.25, "tries": 1]

		let goals = [
			Goal(name: "goal1", achievedAt: 123_456_000, properties: properties),
			Goal(name: "goal2", achievedAt: 123_456_789, properties: nil),
		]

		let event = PublishEvent(
			hashed: true, units: units, publishedAt: 123_456_789, exposures: exposures, goals: goals,
			attributes: attributes)

		let encoder = JSONEncoder()
		encoder.outputFormatting = .sortedKeys
		let string = String(decoding: try encoder.encode(event), as: UTF8.self)

		#expect(
			string
				== "{\"attributes\":[{\"name\":\"attr1\",\"setAt\":123456000,\"value\":\"value1\"},{\"name\":\"attr2\",\"setAt\":123456789,\"value\":\"value2\"},{\"name\":\"attr2\",\"setAt\":123450000,\"value\":null},{\"name\":\"attr3\",\"setAt\":123470000,\"value\":{\"nested\":{\"value\":5}}},{\"name\":\"attr4\",\"setAt\":123480000,\"value\":{\"nested\":[1,2,\"test\"]}}],\"exposures\":[{\"assigned\":true,\"audienceMismatch\":true,\"custom\":false,\"eligible\":true,\"exposedAt\":123470000,\"fullOn\":false,\"id\":1,\"name\":\"exp_test_ab\",\"overridden\":false,\"ruleOverride\":false,\"unit\":\"session_id\",\"variant\":1}],\"goals\":[{\"achievedAt\":123456000,\"name\":\"goal1\",\"properties\":{\"amount\":6,\"tries\":1,\"value\":5.25}},{\"achievedAt\":123456789,\"name\":\"goal2\",\"properties\":null}],\"hashed\":true,\"publishedAt\":123456789,\"units\":[{\"type\":\"session_id\",\"uid\":\"pAE3a1i5Drs5mKRNq56adA\"},{\"type\":\"user_id\",\"uid\":\"JfnnlDI7RTiF9RgfG2JNCw\"}]}"
		)
	}

	@Test func serializeOmitsEmptyLists() throws {
		let encoder = JSONEncoder()
		encoder.outputFormatting = .sortedKeys
		let event = PublishEvent(hashed: true, units: [], publishedAt: 1, exposures: [], goals: [], attributes: [])
		#expect(String(decoding: try encoder.encode(event), as: UTF8.self) == #"{"hashed":true,"publishedAt":1}"#)
		let unhashed = PublishEvent(hashed: false, units: [], publishedAt: 0, exposures: [], goals: [], attributes: [])
		#expect(String(decoding: try encoder.encode(unhashed), as: UTF8.self) == #"{"hashed":false,"publishedAt":0}"#)
	}

	@Test func serializeExposureWithoutUnitAndGoalWithEmptyProperties() throws {
		let encoder = JSONEncoder()
		encoder.outputFormatting = .sortedKeys
		let exposure = Exposure(
			id: 0, name: "missing", unit: nil, variant: 0, exposedAt: 5, assigned: false, eligible: true,
			overridden: false, fullOn: false, custom: false, audienceMismatch: false, ruleOverride: true)
		// A nil unit is left out (synthesised Encodable).
		#expect(
			String(decoding: try encoder.encode(exposure), as: UTF8.self)
				== #"{"assigned":false,"audienceMismatch":false,"custom":false,"eligible":true,"exposedAt":5,"fullOn":false,"id":0,"name":"missing","overridden":false,"ruleOverride":true,"variant":0}"#
		)
		let goal = Goal(name: "g", achievedAt: 1, properties: [:])
		#expect(String(decoding: try encoder.encode(goal), as: UTF8.self) == #"{"achievedAt":1,"name":"g","properties":{}}"#)
	}

	@Test func publishedBodyFromAContextMatches1x() async throws {
		let harness = Harness()
		let context = harness.context(attributes: ["attr1": "value1"])
		_ = context.treatment(for: "exp_test_ab")
		context.track("goal2")
		try await withTimeout { try await context.publish() }
		let body = try #require(harness.transport.publishes.first?.body)
		let object = try #require(try JSONDecoder().decode(JSONValue.self, from: body).objectValue)
		#expect(Set(object.keys) == ["hashed", "units", "publishedAt", "exposures", "goals", "attributes"])
		#expect(object["publishedAt"] == .int(Fixtures.now))
		#expect(object["goals"]?[0]?["properties"] == .null)
		#expect(object["goals"]?[0]?.objectValue?.keys.contains("properties") == true)
	}

	// MARK: - Variable parsing

	static let expectedVariables: [String: JSONValue] = [
		"a": 1,
		"b": "test",
		"c": [
			"test": 2,
			"double": 19.123,
			"list": ["x", "y", "z"],
			"point": [
				"x": -1.0,
				"y": 0.0,
				"z": 1.0,
			],
		],
		"d": true,
		"f": [9_234_567_890, "a", true, false],
		"g": 9.123,
	]

	@Test func parse() throws {
		let config = String(decoding: Fixtures.data("variables"), as: UTF8.self)
		let actual = try JSONValue(parsing: config)
		#expect(actual == .object(Self.expectedVariables))
		// Integers stay integers, and 9234567890 is exact.
		#expect(actual["f"]?[0] == .int(9_234_567_890))
		#expect(actual["a"].map { if case .int = $0 { true } else { false } } == true)
	}

	@Test func parsedVariantVariablesReachTheContext() {
		let config = String(decoding: Fixtures.data("variables"), as: UTF8.self)
		let data = ContextData(experiments: [
			Experiment(
				id: 1, name: "test", unitType: "session_id", split: [0, 1],
				variants: [ExperimentVariant(name: "A", config: nil), ExperimentVariant(name: "B", config: config)])
		])
		let context = Harness().context(data: data)
		for (key, value) in Self.expectedVariables {
			#expect(context.variableValue(key, exposing: false) == value, "\(key)")
		}
		#expect(Set(context.variableKeys.keys) == Set(Self.expectedVariables.keys))
	}

	@Test func returnsNilOnError() throws {
		let truncated = String(decoding: Fixtures.data("variables").prefix(6), as: UTF8.self)
		#expect(throws: ABsmartlyError.self) { try JSONValue(parsing: truncated) }

		// A variant whose config does not parse has no variables.
		let data = ContextData(experiments: [
			Experiment(
				id: 1, name: "test", unitType: "session_id", split: [0, 1],
				variants: [ExperimentVariant(name: "A", config: nil), ExperimentVariant(name: "B", config: truncated)])
		])
		let context = Harness().context(data: data)
		#expect(context.variableKeys.isEmpty)
		#expect(context.variableValue("a", exposing: false) == nil)
	}
}
