import Foundation
import XCTest

@testable import ABSmartly

// Decoding of the switchback fields: the order of `switchbackClusters`, forward compatibility and
// malformed fields. Includes the equality test ported from java-sdk ExperimentSwitchbackFieldsTest and
// the source-order test from java-sdk SwitchbackServingTest.
final class SwitchbackDecodingTest: SwitchbackTestCase {
	func decodeExperiment(_ json: String, file: StaticString = #filePath, line: UInt = #line) -> Experiment? {
		do {
			return try ContextData.decode(from: Data("{\"experiments\":[\(json)]}".utf8)).experiments.first
		} catch {
			XCTFail("decode failed: \(error)", file: file, line: line)
			return nil
		}
	}

	func clusters(_ experiment: Experiment?) -> [String]? {
		return experiment?.switchbackClusters?.map { "\($0.unitType)=\($0.attributePath ?? "nil")" }
	}

	func captureErrors(_ body: () -> Void) -> [String] {
		var errors: [String] = []
		let lock = NSLock()
		Logger.errorObserver = { message in
			lock.lock()
			errors.append(message)
			lock.unlock()
		}
		defer { Logger.errorObserver = nil }
		body()
		return errors
	}

	// MARK: - Order

	// Three sources whose JSON order is neither alphabetical nor any hash order: the first declared
	// unit serves, whichever unit the context sets first.
	func testThreeSourcesKeepTheirJSONOrderAndTheFirstDeclaredServes() {
		let data = SB.data([
			SB.switchback(
				arms: 3, periodMs: SB.hour, clusters: [("zeta_id", "zcity"), ("alpha_id", "acity"), ("mid_id", "mcity")])
		])
		XCTAssertEqual(["zeta_id=zcity", "alpha_id=acity", "mid_id=mcity"], clusters(data.experiments.first))

		for units in [["alpha_id", "mid_id", "zeta_id"], ["mid_id", "zeta_id", "alpha_id"]] {
			let context = createContext(data, units: nil, clusterAttribute: false) { config in
				for unit in units {
					config.setUnit(unitType: unit, uid: "uid-\(unit)")
				}
			}
			for (name, value) in [("acity", "Lisboa"), ("mcity", "Lisboa"), ("zcity", "Lisboa")] {
				context.setAttribute(name: name, value: JSON(value))
			}
			clock.now = SB.anchor + SB.hour
			XCTAssertEqual(SB.draw("Lisboa", 1, arms: 3), context.getTreatment("exp_sb"))
			XCTAssertEqual("zeta_id", publishExposures(context).first?.unit, "\(units)")
		}

		// Without the zeta unit, alpha (declared second) serves, not mid.
		clock.now = SB.anchor
		let context = createContext(data, units: ["mid_id": "m", "alpha_id": "a"], clusterAttribute: false)
		context.setAttribute(name: "acity", value: JSON("Porto"))
		context.setAttribute(name: "mcity", value: JSON("Porto"))
		XCTAssertEqual(SB.draw("Porto", 0, arms: 3), context.getTreatment("exp_sb"))
		XCTAssertEqual("alpha_id", publishExposures(context).first?.unit)
	}

	// Five sources, so a sorted or hashed map is wrong with high probability; every rotation of the
	// declared order is kept.
	func testEveryDeclaredOrderIsKept() {
		let types = ["store_id", "a_id", "user_id", "device_id", "b_id"]
		for rotation in 0..<types.count {
			let order = Array(types[rotation...] + types[..<rotation])
			let data = SB.data([SB.switchback(arms: 2, periodMs: SB.hour, clusters: order.map { ($0, "p_\($0)") })])
			XCTAssertEqual(order, data.experiments.first?.switchbackClusters?.map { $0.unitType })
		}
	}

	// `JSONDecoder` alone cannot see the key order: a map with two or more entries is dropped (and
	// logged) so the switchback is an ineligible control, never served by a guessed unit. A
	// single-entry map has only one order.
	func testPlainJSONDecoderDropsAnUnorderedMultiEntryMap() throws {
		let json = SB.json([
			SB.switchback(1, "exp_two", arms: 2, periodMs: SB.hour, clusters: [("user_id", "a"), ("store_id", "b")]),
			SB.switchback(2, "exp_one", arms: 2, periodMs: SB.hour, clusters: [("store_id", "b")]),
		])
		var data: ContextData?
		let errors = captureErrors { data = try? JSONDecoder().decode(ContextData.self, from: json) }
		XCTAssertNil(data?.experiments[0].switchbackClusters)
		XCTAssertEqual(["store_id=b"], clusters(data?.experiments[1]))
		XCTAssertEqual(1, errors.count)
		XCTAssertTrue(errors.first?.contains("exp_two") ?? false, "\(errors)")

		// The same bytes through ContextData.decode keep both entries, in order.
		let ordered = try ContextData.decode(from: json)
		XCTAssertEqual(["user_id=a", "store_id=b"], clusters(ordered.experiments[0]))
	}

	func testDuplicateEscapedAndWhitespaceKeysKeepTheirOrder() {
		let experiment = decodeExperiment(
			"""
			{
			  "id": 1, "name": "exp_sb",
			  "switchbackClusters" : {
			    "z\\u00e9_id" :  "p1" ,
			    "a\\"q" : "p2",
			    "s\\/l" : "p3",
			    "z\\u00e9_id": "p4",
			    "\\ud83d\\ude00": "p5"
			  }
			}
			""")
		// A duplicate key keeps its first position and takes its last value, as in Java and JS.
		let entries = experiment?.switchbackClusters
		XCTAssertEqual(["zé_id", "a\"q", "s/l", "😀"], entries?.map { $0.unitType })
		XCTAssertEqual(["p4", "p2", "p3", "p5"], entries?.map { $0.attributePath ?? "" })
	}

	func testRepeatedClusterFieldsAndPathsUseTheLastValue() {
		XCTAssertEqual(["b=y", "a=z"], clusters(decodeExperiment(
			#"{"name":"e","switchbackClusters":{"old":"x"},"switchbackClusters":{"b":"bad","a":"z","b":"y"}}"#)))
		XCTAssertNil(decodeExperiment(
			#"{"name":"e","switchbackClusters":{"a":"x"},"switchbackClusters":null}"#)?.switchbackClusters)
		XCTAssertEqual(["a=nil"], clusters(decodeExperiment(
			#"{"name":"e","switchbackClusters":{"a":"x","a":{"bad":1}}}"#)))
		XCTAssertEqual(["a=x"], clusters(decodeExperiment(
			#"{"name":"e","switchbackClusters":{"a":{"bad":1},"a":"x"}}"#)))
	}

	// A `switchbackClusters` key at another depth never lends its order to an experiment.
	func testNestedSwitchbackClustersElsewhereAreNotUsed() {
		let json = """
			{"meta":{"switchbackClusters":{"b":"x","a":"y"}},"experiments":[{"id":1,"name":"e",\
			"variants":[{"name":"A","config":"{\\"switchbackClusters\\":{\\"q\\":1}}"}],\
			"extra":{"switchbackClusters":{"y":"1","x":"2"}},"switchbackClusters":{"x":"2","y":"1"}}]}
			"""
		let data = try? ContextData.decode(from: Data(json.utf8))
		XCTAssertEqual(["x=2", "y=1"], clusters(data?.experiments.first))
	}

	func testHoldoutEntriesKeepTheirOwnOrder() {
		let data = SB.data(
			[SB.switchback(arms: 2, periodMs: SB.hour, clusters: [("b", "1"), ("a", "2")])],
			holdouts: [SB.switchback(9, "h", arms: 2, periodMs: SB.hour, clusters: [("d", "1"), ("c", "2")])])
		XCTAssertEqual(["b=1", "a=2"], clusters(data.experiments.first))
		XCTAssertEqual(["d=1", "c=2"], clusters(data.holdouts?.first))
	}

	// MARK: - Forward compatibility

	func testUnknownFieldsAndPhase1EFieldsAreIgnored() throws {
		var experiment = SB.switchback(arms: 3, periodMs: SB.hour)
		experiment["switchbackClusterUnitType"] = "user_id"
		experiment["switchbackClusterCount"] = 8
		experiment["switchbackClusterAttribute"] = "city"
		experiment["futureScalar"] = 1
		experiment["futureObject"] = ["a": ["b": 1]]
		experiment["futureArray"] = [1, "x", NSNull()]
		experiment["futureNull"] = NSNull()
		experiment["switchback"] = ["period": 60]
		let root = SB.OrderedObject([
			("future", ["x": 1]), ("experiments", [experiment]), ("futureList", [["switchbackClusters": ["q": "r"]]]),
			("futureNull", NSNull()),
		])
		var data: ContextData?
		let errors = captureErrors { data = try? ContextData.decode(from: Data(SB.serialize(root).utf8)) }
		XCTAssertEqual([], errors)
		XCTAssertEqual(["store_id=store_key"], clusters(data?.experiments.first))

		let context = createContext(try XCTUnwrap(data))
		XCTAssertEqual(SB.expected3Arms, peekSchedule(context))
	}

	// A Phase 1E payload without `switchbackClusters` is the legacy path: ineligible, no exposure.
	func testPhase1EOnlyPayloadIsALegacyIneligibleControl() {
		var experiment = SB.switchback(arms: 3, periodMs: SB.hour, clusters: nil)
		experiment["switchbackClusterUnitType"] = SB.unitType
		experiment["switchbackClusterCount"] = 8
		experiment["switchbackClusterAttribute"] = SB.clusterPath
		let context = createContext(SB.data([experiment]))
		XCTAssertEqual(0, context.getTreatment("exp_sb"))
		XCTAssertEqual(0, context.getPendingCount())
	}

	// MARK: - Malformed fields

	// Each malformed field affects only its own experiment, which serves an ineligible control; the
	// other experiment in the payload still serves.
	func testMalformedFieldsOnlyAffectTheirExperiment() {
		let malformed: [(String, (inout [String: Any]) -> Void)] = [
			("startAt string", { $0["switchbackStartAt"] = "\(SB.anchor)" }),
			("startAt fraction", { $0["switchbackStartAt"] = 1.5 }),
			("periodMs string", { $0["switchbackPeriodMs"] = "3600000" }),
			("clusters array of strings", { $0["switchbackClusters"] = [SB.unitType, SB.clusterPath] }),
			("clusters string", { $0["switchbackClusters"] = "store_id" }),
			("non-string path", { $0["switchbackClusters"] = SB.OrderedObject([(SB.unitType, 7)]) }),
			("object path", { $0["switchbackClusters"] = SB.OrderedObject([(SB.unitType, ["p": 1])]) }),
			("clusterValues nested", { $0["switchbackClusterValues"] = [["bad": 1]] }),
			("clusterValues string", { $0["switchbackClusterValues"] = SB.clusterKey }),
		]
		for (label, change) in malformed {
			var broken = SB.switchback(1, "exp_broken", arms: 3, periodMs: SB.hour)
			change(&broken)
			let healthy = SB.switchback(2, "exp_sb", arms: 3, periodMs: SB.hour)
			var data: ContextData?
			_ = captureErrors { data = try? ContextData.decode(from: SB.json([broken, healthy])) }
			guard let decoded = data else {
				XCTFail("\(label): payload rejected")
				continue
			}
			XCTAssertEqual(2, decoded.experiments.count, label)
			let context = createContext(decoded)
			clock.now = SB.anchor
			XCTAssertEqual(0, context.getTreatment("exp_broken"), label)
			XCTAssertEqual(0, context.getPendingCount(), label)
			XCTAssertEqual(SB.expected3Arms[0], context.getTreatment("exp_sb"), label)
			XCTAssertEqual(1, context.getPendingCount(), label)
		}
	}

	func testScalarAllowListEntriesCompareAsText() {
		let experiment = decodeExperiment(
			#"{"name":"e","switchbackClusters":{"store_id":"key"},"switchbackClusterValues":[42,true,"north",null]}"#)
		XCTAssertEqual(["42", "true", "north", ""], experiment?.switchbackClusterValues)
		XCTAssertEqual(["store_id=key"], clusters(experiment))
		XCTAssertEqual([""], decodeExperiment(
			#"{"name":"e","switchbackClusterValues":[null]}"#)?.switchbackClusterValues)
	}

	// MARK: - Equality (java-sdk ExperimentSwitchbackFieldsTest)

	static func fieldsSwitchback() -> [String: Any] {
		var experiment = SB.switchback(
			arms: 2, periodMs: 3_600_000, clusters: [("store_id", "store/key"), ("device_id", "geo/city")])
		experiment["switchbackClusterValues"] = ["porto", "lisbon"]
		experiment["switchbackStartAt"] = 1_767_225_600_000
		experiment["switchbackCarryoverDurationMs"] = 900_000
		experiment["switchbackBurnInDurationMs"] = 600_000
		experiment["switchbackBurnOutDurationMs"] = 0
		return experiment
	}

	func testEqualityCoversEverySwitchbackField() {
		func decoded(_ experiment: [String: Any]) -> Experiment {
			return SB.data([experiment]).experiments[0]
		}
		XCTAssertEqual(decoded(Self.fieldsSwitchback()), decoded(Self.fieldsSwitchback()))

		let mutations: [(String, (inout [String: Any]) -> Void)] = [
			("randomizationType", { $0["randomizationType"] = "unit" }),
			("clusters null", { $0["switchbackClusters"] = NSNull() }),
			("clusters shorter", { $0["switchbackClusters"] = SB.OrderedObject([("store_id", "store/key")]) }),
			(
				"clusters path",
				{ $0["switchbackClusters"] = SB.OrderedObject([("store_id", "store/key"), ("device_id", "geo/country")]) }
			),
			// Same entries, other order: the order is semantic.
			(
				"clusters order",
				{ $0["switchbackClusters"] = SB.OrderedObject([("device_id", "geo/city"), ("store_id", "store/key")]) }
			),
			("clusterValues null", { $0["switchbackClusterValues"] = NSNull() }),
			("clusterValues order", { $0["switchbackClusterValues"] = ["lisbon", "porto"] }),
			("startAt", { $0["switchbackStartAt"] = 1_767_229_200_000 }),
			("periodMs", { $0["switchbackPeriodMs"] = 86_400_000 }),
			("carryover null", { $0["switchbackCarryoverDurationMs"] = NSNull() }),
			("burnIn", { $0["switchbackBurnInDurationMs"] = 1 }),
			("burnOut", { $0["switchbackBurnOutDurationMs"] = 1 }),
			("designType", { $0["switchbackDesignType"] = "other" }),
			("estimand", { $0["switchbackEstimand"] = "other" }),
		]
		for (label, mutation) in mutations {
			var changed = Self.fieldsSwitchback()
			mutation(&changed)
			XCTAssertNotEqual(decoded(Self.fieldsSwitchback()), decoded(changed), label)
			XCTAssertNotEqual(decoded(changed), decoded(Self.fieldsSwitchback()), label)
		}
	}

	func testFieldsAreDecoded() {
		let experiment = SB.data([Self.fieldsSwitchback()]).experiments[0]
		XCTAssertEqual("switchback", experiment.randomizationType)
		XCTAssertEqual(
			[
				SwitchbackCluster(unitType: "store_id", attributePath: "store/key"),
				SwitchbackCluster(unitType: "device_id", attributePath: "geo/city"),
			], experiment.switchbackClusters)
		XCTAssertEqual(["porto", "lisbon"], experiment.switchbackClusterValues)
		XCTAssertEqual(1_767_225_600_000, experiment.switchbackStartAt)
		XCTAssertEqual(3_600_000, experiment.switchbackPeriodMs)
		XCTAssertEqual(900_000, experiment.switchbackCarryoverDurationMs)
		XCTAssertEqual(600_000, experiment.switchbackBurnInDurationMs)
		XCTAssertEqual(0, experiment.switchbackBurnOutDurationMs)
		XCTAssertEqual("balanced_block", experiment.switchbackDesignType)
		XCTAssertEqual("global_average_treatment_effect", experiment.switchbackEstimand)

		// A unit experiment from before switchbacks has none of them.
		let unit = decodeExperiment("{\"id\":1,\"name\":\"e\"}")
		XCTAssertNil(unit?.randomizationType)
		XCTAssertNil(unit?.switchbackClusters)
		XCTAssertNil(unit?.switchbackStartAt)
	}

	// MARK: - Encoding

	// `Experiment` encodes `switchbackClusters` as an array of `SwitchbackCluster`, which keeps the
	// order through any encoder and decodes back, even with a plain `JSONDecoder`.
	func testEncodingRoundTripsTheClusterOrder() throws {
		let data = SB.data([
			SB.switchback(arms: 2, periodMs: SB.hour, clusters: [("zeta_id", "z"), ("alpha_id", "a"), ("mid_id", "m")])
		])
		let encoded = try JSONEncoder().encode(data)
		let plain = try JSONDecoder().decode(ContextData.self, from: encoded)
		XCTAssertEqual(data, plain)
		XCTAssertEqual(["zeta_id=z", "alpha_id=a", "mid_id=m"], clusters(plain.experiments.first))
		XCTAssertEqual(data, try ContextData.decode(from: encoded))
	}

	// MARK: - Serving (java-sdk SwitchbackServingTest)

	// The declared source order decides, not the order of the units: with units set user first and
	// sources declared session first, both agreeing, session serves.
	func testSourceOrderDecidesWhateverTheUnitOrder() {
		let attributes: [String: JSON] = ["session_store": JSON("s-1"), "user_store": JSON("s-1")]
		let serving = SwitchbackServing.resolve(
			sources: [
				("session_id", SwitchbackAttributePath.parseSupported("session_store")!),
				("user_id", SwitchbackAttributePath.parseSupported("user_store")!),
			], allowedValues: nil, hasUnit: { ["user_id", "session_id"].contains($0) },
			read: { $0.resolve(attributes) })
		XCTAssertEqual(.eligible, serving.status)
		XCTAssertEqual("session_id", serving.unitType)
		XCTAssertEqual("s-1", serving.clusterKey)
	}
}

extension SwitchbackDecodingTest {
	private func orderPayload(_ order: [String], variantName: String = "A") -> Data {
		let clusters = order.map { "\"\($0)\":\"\($0)_path\"" }.joined(separator: ",")
		return Data(
			("{\"experiments\":[{\"id\":1,\"name\":\"exp\",\"randomizationType\":\"switchback\","
				+ "\"variants\":[{\"name\":\"\(variantName)\",\"config\":null}],\"switchbackClusters\":{\(clusters)}}]}").utf8)
	}

	private func order(_ data: ContextData?) -> [String]? {
		return data?.experiments.first?.switchbackClusters?.map { $0.unitType }
	}

	// A decoder passed to ContextData.decode is left as it was: a later plain decode of another payload
	// does not reuse this payload's order.
	func testDecodeLeavesTheCallersDecoderUnchanged() throws {
		let shared = JSONDecoder()
		XCTAssertEqual(["x_type", "y_type"], order(try ContextData.decode(from: orderPayload(["x_type", "y_type"]), decoder: shared)))
		XCTAssertNil(shared.userInfo[SwitchbackClusterOrder.userInfoKey])
		XCTAssertNil(order(try shared.decode(ContextData.self, from: orderPayload(["y_type", "x_type"]))))
		XCTAssertEqual(["y_type", "x_type"], order(try ContextData.decode(from: orderPayload(["y_type", "x_type"]), decoder: shared)))
	}

	// A leading UTF-8 BOM, or an unpaired surrogate escape anywhere in the payload, still keeps the order.
	func testOrderSurvivesABOMAndUnpairedSurrogates() throws {
		var bom = Data([0xEF, 0xBB, 0xBF])
		bom.append(orderPayload(["y_type", "x_type"]))
		if let decoded = try? ContextData.decode(from: bom) {
			XCTAssertEqual(["y_type", "x_type"], order(decoded))
		}
		XCTAssertEqual(
			["y_type", "x_type"], order(try ContextData.decode(from: orderPayload(["y_type", "x_type"], variantName: "\\ud800x"))))
	}
}
