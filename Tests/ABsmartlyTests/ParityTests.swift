import Foundation
import Testing

@testable import ABsmartly

// Replays the parity probe on 2.0 and compares it with what 1.5.0 recorded
// (Resources/parity/probe-1.5.0.json, written by Tools/ParityRecorder against the pinned 1.5.0
// commit). The steps mirror Tools/ParityRecorder/Sources/ParityRecorder/main.swift exactly; keep them
// in sync. Timestamps are dropped on both sides and units sorted by type (1.5.0 publishes them in
// dictionary order); everything else must be identical.
@Suite struct ParityTests {
	static let timestampKeys: Set<String> = ["publishedAt", "exposedAt", "achievedAt", "setAt"]

	static let uidSweep: [String] = [
		"123456789", "e791e240fcd3df7d238cfc285f475e8152fcc0ec", "bleh@absmartly.com", "  padded  ", "ação",
		"café", "日本語", "😀🎉", "0", "-1", "9007199254740993", "12345678901234567890", "1.5", "a", "Z",
		"user-00000", "user-00001", "user-00002", "user-00003", "user-00004", "user-00005", "user-00006",
		"user-00007", "user-00008", "user-00009",
	]

	static func normalise(_ value: JSONValue) -> JSONValue {
		switch value {
		case .object(let object):
			var result: [String: JSONValue] = [:]
			for (key, inner) in object where !timestampKeys.contains(key) {
				result[key] = normalise(inner)
			}
			return .object(result)
		case .array(let items):
			let mapped = items.map(normalise)
			let isUnits =
				!mapped.isEmpty
				&& mapped.allSatisfy { $0.objectValue.map { Set($0.keys) == ["type", "uid"] } ?? false }
			if isUnits {
				return .array(mapped.sorted { ($0["type"]?.stringValue ?? "") < ($1["type"]?.stringValue ?? "") })
			}
			return .array(mapped)
		default:
			return value
		}
	}

	static func encoded<T: Encodable>(_ value: T) -> JSONValue {
		let data = try! JSONEncoder().encode(value)
		return normalise(try! JSONDecoder().decode(JSONValue.self, from: data))
	}

	/// Runs the probe for one fixture and uid on 2.0, producing the record 1.5.0 produced.
	static func probe(fixture: String, uid: String) async throws -> JSONValue {
		let harness = Harness(application: "website", environment: "production")
		let data = Fixtures.contextData(fixture)
		var units: [UnitType: String] = [:]
		for unitType in ["session_id", "user_id", "email", "device_id"] {
			units[UnitType(unitType)] = uid
		}
		let context = harness.context(data: data, units: units)

		var record: [String: JSONValue] = ["fixture": .string(fixture), "uid": .string(uid)]
		var peeks: [String: JSONValue] = [:]
		for experiment in data.experiments {
			peeks[experiment.name] = .int(Int64(context.treatment(for: experiment.name, exposing: false)))
		}
		let keys = context.variableKeys.keys.sorted()
		var peekVariables: [String: JSONValue] = [:]
		for key in keys {
			peekVariables[key] = context.variableValue(key, exposing: false) ?? .null
		}

		let index = uidSweep.firstIndex(of: uid)!
		context.setAttribute("age", to: 15 + index)
		context.setAttribute("language", to: index % 2 == 0 ? "en-US" : "de")
		if index % 3 == 0 {
			context.setAttribute("country", to: "US")
		}
		context.setAttribute("app_version", to: ["1.9.9", "2.1.0", "v2.10.0-beta", "2.1.0-rc.1"][index % 4])
		if index % 5 == 0 {
			context.setAttribute("environment", to: "staging")
		}

		var treatments: [String: JSONValue] = [:]
		for experiment in data.experiments {
			treatments[experiment.name] = .int(Int64(context.treatment(for: experiment.name)))
		}
		var variables: [String: JSONValue] = [:]
		for key in keys {
			variables[key] = context.variableValue(key) ?? .null
		}
		context.track("goal_\(uid.count)", properties: ["amount": 12.5, "uid": .string(uid)])

		record["peeks"] = .object(peeks)
		record["treatments"] = .object(treatments)
		record["peekVariables"] = .object(peekVariables)
		record["variables"] = .object(variables)
		record["variableKeys"] = .object(context.variableKeys.mapValues { .array($0.map(JSONValue.string)) })

		var customFields: [String: JSONValue] = [:]
		for experiment in data.experiments {
			for key in context.customFieldKeys(in: experiment.name).sorted() {
				customFields["\(experiment.name).\(key)"] = [
					"type": .string(context.customFieldType(key, in: experiment.name) ?? ""),
					"value": context.customFieldValue(key, in: experiment.name) ?? .null,
				]
			}
		}
		record["customFields"] = .object(customFields)

		try await context.publish()

		record["events"] = .array(
			harness.recorder.events.map { event -> JSONValue in
				switch event {
				case .ready: return ["type": "ready"]
				case .refresh: return ["type": "refresh"]
				case .publish(let e): return ["type": "publish", "body": encoded(e)]
				case .exposure(let e): return ["type": "exposure", "body": encoded(e)]
				case .goal(let g): return ["type": "goal", "body": encoded(g)]
				case .close: return ["type": "close"]
				case .error(let e): return ["type": "error", "message": .string(e.description)]
				}
			})
		record["published"] = .array(harness.transport.publishedBodies.map(normalise))
		return .object(record)
	}

	// The one known difference (see docs/plans/swift-2.0.md, "Known 2.0 difference from 1.5.0"):
	// 1.5.0 types a `boolean` custom field as `Bool(text)`, so "TRUE" is nil; 2.0 gives `false`.
	static let knownCustomFieldDifferences: [String: JSONValue] = [
		"custom_fields.flag": ["type": "boolean", "value": false]
	]

	static let recorded: [JSONValue] = {
		let url = Fixtures.resources.appendingPathComponent("parity/probe-1.5.0.json")
		let data = try! Data(contentsOf: url)
		return try! JSONDecoder().decode([JSONValue].self, from: data)
	}()

	@Test func recordingCoversEveryFixtureAndUID() {
		#expect(Self.recorded.count == 7 * Self.uidSweep.count)
	}

	// Serialized: the probes are CPU-bound, and running all seven fixtures at once can starve the
	// timer-based tests on a small host.
	@Test(
		.serialized,
		arguments: [
			"context", "audience_context", "audience_strict_context", "audience_key_conflict_disjoint_context",
			"refreshed",
			"refreshed_full_on", "parity_rules_context",
		])
	func matches150(fixture: String) async throws {
		for expected in Self.recorded where expected["fixture"]?.stringValue == fixture {
			let uid = try #require(expected["uid"]?.stringValue)
			// Hands the thread back between probes so this CPU-bound loop does not starve the timer
			// tests running in parallel on the cooperative pool.
			await Task.yield()
			let actual = try await Self.probe(fixture: fixture, uid: uid)
			for key in ["peeks", "treatments", "peekVariables", "variables", "variableKeys", "events", "published"] {
				#expect(actual[key] == expected[key], "\(fixture) uid=\(uid) \(key)")
			}
			var expectedFields = expected["customFields"]?.objectValue ?? [:]
			for (field, value) in Self.knownCustomFieldDifferences where expectedFields[field] != nil {
				#expect(expectedFields[field] == ["type": "boolean", "value": .null], "\(fixture) uid=\(uid) \(field)")
				expectedFields[field] = value
			}
			#expect(actual["customFields"] == .object(expectedFields), "\(fixture) uid=\(uid) customFields")
		}
	}
}
