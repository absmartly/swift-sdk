import Foundation
import Testing

@testable import ABsmartly

// The SDK's diagnostics keep customer payload text (configs, field values, patterns, audiences,
// error text, event contents) in the entry's `detail`, which Apple logs mark private; the public
// `summary` says what failed without it.
@Suite struct LogPrivacyTests {
	init() {
		LogCapture.install()
	}

	static func experiment(_ marker: String, config: String, extra: String = "") -> ContextData {
		let escaped = config.replacingOccurrences(of: "\"", with: "\\\"")
		return ContextFixtures.decode(
			"""
			{"experiments":[{"id":1,"name":"exp_\(marker)","unitType":"session_id","split":[0.5,0.5],\
			"trafficSplit":[0,1],"variants":[{"name":"A","config":null},{"name":"B","config":"\(escaped)"}]\(extra)}]}
			""")
	}

	static func expectPrivate(_ marker: String, secret: String, sourceLocation: SourceLocation = #_sourceLocation) {
		let entries = LogCapture.entries(containing: secret)
		#expect(!entries.isEmpty, "no diagnostic logged", sourceLocation: sourceLocation)
		for entry in entries {
			#expect(entry.summary.contains(marker), "summary names the experiment", sourceLocation: sourceLocation)
			#expect(!entry.summary.contains(secret), "\(entry.summary)", sourceLocation: sourceLocation)
			#expect(entry.detail?.contains(secret) == true, sourceLocation: sourceLocation)
		}
	}

	@Test func variantConfigTextIsPrivate() {
		let marker = UUID().uuidString
		let secret = "secret-\(marker)"
		_ = DataIndex(Self.experiment(marker, config: "\"\(secret)\""))
		Self.expectPrivate(marker, secret: secret)

		let invalid = "invalid-\(marker)"
		_ = DataIndex(Self.experiment(marker, config: "{\(invalid)"))
		Self.expectPrivate(marker, secret: invalid)
	}

	@Test func customFieldValueIsPrivate() {
		let marker = UUID().uuidString
		let secret = "{secret-\(marker)"
		_ = DataIndex(
			Self.experiment(
				marker, config: "{}",
				extra: ",\"customFieldValues\":[{\"name\":\"f\",\"type\":\"json\",\"value\":\"\(secret)\"}]"))
		Self.expectPrivate(marker, secret: secret)
	}

	// Every regex diagnostic: compile failure, nested quantifiers, over-length pattern, timeout.
	@Test(arguments: ["compile", "nested", "length", "timeout"])
	func regexPatternIsPrivate(path: String) {
		let secret = "secret\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))"
		let (input, pattern): (String, String) =
			switch path {
			case "compile": ("x", "[" + secret)
			case "nested": ("x", "(a+)+" + secret)
			case "length": ("x", secret + String(repeating: "a", count: 1000))
			default: (String(repeating: "a", count: 60) + "b", "^(a|aa)+$|" + secret)
			}
		_ = ExprEvaluator(vars: [:]).evaluate(
			ExprValue(["match": [["value": .string(input)], ["value": .string(pattern)]]] as JSONValue))
		let entries = LogCapture.entries(containing: secret)
		#expect(entries.count == 1)
		for entry in entries {
			#expect(!entry.summary.contains(secret), "\(entry.summary)")
			#expect(entry.detail?.contains(secret) == true)
		}
	}

	@Test func audienceIsPrivate() {
		let secret = "secret-\(UUID().uuidString)"
		_ = AudienceMatcher.parseAudience("{\"filter\":\"\(secret)\"}")
		let entries = LogCapture.entries(containing: secret)
		#expect(!entries.isEmpty)
		for entry in entries {
			#expect(!entry.summary.contains(secret))
			#expect(entry.summary.contains("Audience filter has invalid type"))
		}
	}

	@Test func errorTextIsPrivate() {
		let secret = "secret-\(UUID().uuidString)"
		for error in [ABsmartlyError.transport(secret), .decoding(secret)] {
			#expect(!error.logSummary.contains(secret))
			#expect(error.logDetail == secret)
			let entry = EventLog.entry(.error(error))
			#expect(!entry.summary.contains(secret))
			#expect(entry.detail == secret)
		}
		#expect(ABsmartlyError.notReady.logSummary == "ABsmartly Context is not yet ready.")
		#expect(ABsmartlyError.notReady.logDetail == nil)
	}

	@Test func eventContentsArePrivate() {
		let secret = "secret-\(UUID().uuidString)"
		let goal = Goal(name: "checkout", achievedAt: 0, properties: ["email": .string(secret)])
		let events: [Context.Event] = [
			.goal(goal),
			.publish(
				PublishEvent(
					hashed: true, units: [], publishedAt: 0, exposures: [], goals: [goal],
					attributes: [PublishEvent.Attribute(name: "email", value: .string(secret), setAt: 0)])),
			.ready(ContextFixtures.decode("{\"experiments\":[{\"id\":1,\"name\":\"\(secret)\"}]}")),
		]
		for event in events {
			let entry = EventLog.entry(event)
			#expect(!entry.summary.contains(secret), "\(entry.summary)")
			#expect(entry.detail?.contains(secret) == true)
		}
		#expect(EventLog.entry(.goal(goal)).summary == "goal 'checkout'")
	}

	@Test func contextLoadFailureLogsTheKindPublicly() async {
		let secret = "secret-\(UUID().uuidString)"
		let env = ContextEnv()
		env.failNextRequest(secret)
		let context = env.client.makeContext(units: Fixtures.units)
		try? await context.ready()

		let entries = LogCapture.entries(containing: secret)
		#expect(!entries.isEmpty)
		for entry in entries {
			#expect(entry.summary == "Context initialization failed: transport error")
			#expect(entry.detail?.contains(secret) == true)
		}
	}
}
