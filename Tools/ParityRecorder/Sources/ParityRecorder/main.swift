import ABSmartly
import Foundation
import PromiseKit

// The parity probe, 1.5.0 side. Every step records a JSON line; ParityTests runs the same steps on
// 2.0 and compares. Keep the step list in sync with Tests/ABsmartlyTests/ParityTests.swift.

let outputDir = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "parity")
try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
let fixturesDir = outputDir.deletingLastPathComponent()

final class Recorder: ContextEventLogger {
	var events: [[String: Any]] = []
	let lock = NSLock()

	func handleEvent(context: Context, event: ContextEventLoggerEvent) {
		var record: [String: Any]
		switch event {
		case .ready: record = ["type": "ready"]
		case .refresh: record = ["type": "refresh"]
		case .publish(let e): record = ["type": "publish", "body": encode(e)]
		case .exposure(let e): record = ["type": "exposure", "body": encode(e)]
		case .goal(let g): record = ["type": "goal", "body": encode(g)]
		case .close: record = ["type": "close"]
		case .error(let e): record = ["type": "error", "message": e.localizedDescription]
		}
		lock.lock()
		events.append(record)
		lock.unlock()
	}

	func drain() -> [[String: Any]] {
		lock.lock()
		defer { lock.unlock() }
		let result = events
		events = []
		return result
	}
}

// Timestamps are wall-clock in 1.x (no clock injection on its public path), so they are dropped.
let timestampKeys: Set<String> = ["publishedAt", "exposedAt", "achievedAt", "setAt"]

func normalise(_ value: Any) -> Any {
	if let dict = value as? [String: Any] {
		var result: [String: Any] = [:]
		for (key, inner) in dict where !timestampKeys.contains(key) {
			result[key] = normalise(inner)
		}
		return result
	}
	if let array = value as? [Any] {
		// Units are published in dictionary order, which differs between runs.
		let mapped = array.map(normalise)
		if let units = mapped as? [[String: Any]], units.allSatisfy({ $0.keys.sorted() == ["type", "uid"] }) {
			return units.sorted { ($0["type"] as! String) < ($1["type"] as! String) }
		}
		return mapped
	}
	return value
}

func encode<T: Encodable>(_ value: T) -> Any {
	let data = try! JSONEncoder().encode(value)
	return normalise(try! JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]))
}

final class Publisher: ContextPublisher {
	var bodies: [Any] = []
	func publish(event: PublishEvent) -> Promise<Void> {
		bodies.append(encode(event))
		return Promise.value(())
	}
}

final class Provider: ContextDataProvider {
	func getContextData() -> Promise<ContextData> { Promise.value(ContextData()) }
}

func jsonAny(_ json: JSON?) -> Any {
	guard let json = json else { return NSNull() }
	return json.object
}

func loadData(_ name: String) -> ContextData {
	let data = try! Data(contentsOf: fixturesDir.appendingPathComponent(name + ".json"))
	return try! JSONDecoder().decode(ContextData.self, from: data)
}

// A UID sweep over every kind of unit value the cross-SDK contract cares about.
let uidSweep: [String] = [
	"123456789", "e791e240fcd3df7d238cfc285f475e8152fcc0ec", "bleh@absmartly.com", "  padded  ", "ação",
	"café", "日本語", "😀🎉", "0", "-1", "9007199254740993", "12345678901234567890", "1.5", "a", "Z",
	"user-00000", "user-00001", "user-00002", "user-00003", "user-00004", "user-00005", "user-00006",
	"user-00007", "user-00008", "user-00009",
]

let fixtures = [
	"context", "audience_context", "audience_strict_context", "audience_key_conflict_disjoint_context", "refreshed",
	"refreshed_full_on", "parity_rules_context",
]

var lines: [Any] = []

// Linux: 1.5.0 delivers every event on the completing thread, synchronously here.

for fixture in fixtures {
	let data = loadData(fixture)
	for uid in uidSweep {
		let recorder = Recorder()
		let publisher = Publisher()
		// A real DefaultClient supplies the system attributes (application/environment); the provider
		// and publisher are fakes, so nothing goes over the network.
		let client = try! DefaultClient(
			config: ClientConfig(
				apiKey: "k", application: "website", endpoint: "http://127.0.0.1:9", environment: "production"))
		let config = ABsmartlyConfig(
			contextDataProvider: Provider(), contextPublisher: publisher, contextEventLogger: nil,
			variableParser: nil, scheduler: nil, client: client)
		let sdk = try! ABsmartlySDK(config: config)
		let contextConfig = ContextConfig()
		contextConfig.publishDelay = -1
		contextConfig.eventLogger = recorder
		for unitType in ["session_id", "user_id", "email", "device_id"] {
			contextConfig.setUnit(unitType: unitType, uid: uid)
		}
		let context = sdk.createContextWithData(config: contextConfig, contextData: data)

		var record: [String: Any] = ["fixture": fixture, "uid": uid]
		var peeks: [String: Int] = [:]
		var treatments: [String: Int] = [:]
		for experiment in data.experiments {
			peeks[experiment.name] = context.peekTreatment(experiment.name)
		}
		var peekVariables: [String: Any] = [:]
		var variables: [String: Any] = [:]
		let keys = context.getVariableKeys().keys.sorted()
		for key in keys {
			peekVariables[key] = jsonAny(context.peekVariableValue(key))
		}
		// Attribute changes can flip audiences and rules; which ones depends on the uid, so every
		// branch is visited across the sweep.
		let index = uidSweep.firstIndex(of: uid)!
		context.setAttribute(name: "age", value: JSON(15 + index))
		if index % 2 == 0 {
			context.setAttribute(name: "language", value: JSON("en-US"))
		} else {
			context.setAttribute(name: "language", value: JSON("de"))
		}
		if index % 3 == 0 {
			context.setAttribute(name: "country", value: JSON("US"))
		}
		context.setAttribute(name: "app_version", value: JSON(["1.9.9", "2.1.0", "v2.10.0-beta", "2.1.0-rc.1"][index % 4]))
		if index % 5 == 0 {
			context.setAttribute(name: "environment", value: JSON("staging"))
		}
		for experiment in data.experiments {
			treatments[experiment.name] = context.getTreatment(experiment.name)
		}
		for key in keys {
			variables[key] = jsonAny(context.getVariableValue(key))
		}
		context.track("goal_\(uid.count)", properties: ["amount": JSON(12.5), "uid": JSON(uid)])
		record["peeks"] = peeks
		record["treatments"] = treatments
		record["peekVariables"] = peekVariables
		record["variables"] = variables
		record["variableKeys"] = context.getVariableKeys()
		var customFields: [String: Any] = [:]
		for experiment in data.experiments {
			for key in context.getCustomFieldKeys(experimentName: experiment.name).sorted() {
				let value = context.getCustomFieldValue(experimentName: experiment.name, key: key)
				let type = context.getCustomFieldValueType(experimentName: experiment.name, key: key) ?? ""
				var rendered: Any = NSNull()
				switch value {
				case let json as JSON: rendered = json.object
				case let dict as [String: JSON]: rendered = dict.mapValues { $0.object }
				case let double as Double: rendered = double
				case let bool as Bool: rendered = bool
				case let string as String: rendered = string
				default: break
				}
				customFields["\(experiment.name).\(key)"] = ["type": type, "value": rendered]
			}
		}
		record["customFields"] = customFields
		_ = try? hang(context.publish())  // the fake publisher settles at once
		var events = recorder.drain()
		// publishedAt and exposedAt/achievedAt/setAt are wall-clock in 1.x (no clock injection on
		// the public path); the replay normalises them.
		record["events"] = events
		record["published"] = publisher.bodies
		events = []
		lines.append(record)
	}
}

// One record per line, keys sorted, so a re-recording diffs line by line.
var output = Data("[\n".utf8)
for (i, line) in lines.enumerated() {
	output += try JSONSerialization.data(withJSONObject: line, options: [.sortedKeys])
	output += Data((i == lines.count - 1 ? "\n" : ",\n").utf8)
}
output += Data("]\n".utf8)
try output.write(to: outputDir.appendingPathComponent("probe-1.5.0.json"))
print("wrote \(lines.count) records to \(outputDir.path)")
