import Foundation
import Testing

@testable import ABsmartly

#if DEBUG
	private let countsCacheWrites = true
#else
	private let countsCacheWrites = false
#endif

@Suite(.timeLimit(.minutes(1))) struct PerformanceTests {
	private static let iterations = 10
	private static let bound: TimeInterval = 10

	private func measured(_ block: () throws -> Void, sourceLocation: SourceLocation = #_sourceLocation) rethrows {
		let start = Date()
		for _ in 0..<Self.iterations {
			try block()
		}
		let elapsed = Date().timeIntervalSince(start)
		#expect(elapsed < Self.bound, "took \(elapsed)s", sourceLocation: sourceLocation)
	}

	@Test func largeContextDataHandling() {
		let context = Harness().context()

		#expect(context.state == .ready)

		let experiments = context.experiments
		#expect(!experiments.isEmpty)

		measured {
			for experimentName in experiments {
				_ = context.treatment(for: experimentName, exposing: false)
			}
		}

		#expect(context.pendingEventCount == 0)
	}

	@Test func highFrequencyOperations() {
		let context = Harness().context()

		measured {
			for i in 0..<1000 {
				context.setAttribute("attr_\(i % 100)", to: "value_\(i)")
			}
		}

		#expect(context.attributes.count > 0)
	}

	@Test func treatmentAccessPerformance() {
		let context = Harness().context()
		let experimentNames = context.experiments

		measured {
			for _ in 0..<100 {
				for experimentName in experimentNames {
					_ = context.treatment(for: experimentName)
				}
			}
		}

		#expect(context.pendingEventCount > 0)
	}

	@Test(.enabled(if: countsCacheWrites)) func warmedReadsDoNotWriteAssignmentCache() {
		#if DEBUG
			let context = Harness().context()
			let beforeWarmup = context.assignmentCacheWriteCount
			#expect(context.treatment(for: "exp_test_ab") == 1)
			#expect(context.assignmentCacheWriteCount == beforeWarmup + 1)

			let warmed = context.assignmentCacheWriteCount
			for _ in 0..<100 {
				#expect(context.treatment(for: "exp_test_ab") == 1)
				#expect(context.treatment(for: "exp_test_ab", exposing: false) == 1)
				#expect(context.variableValue("banner.size") == "large")
				#expect(context.variableValue("banner.size", exposing: false) == "large")
			}
			#expect(context.assignmentCacheWriteCount == warmed)
			#expect(context.pendingEventCount == 1)
		#endif
	}

	@Test(.enabled(if: countsCacheWrites)) func revalidatedReadsDoNotWriteAssignmentCache() async throws {
		#if DEBUG
			let rules = ContextAssignmentRulesTests.self
			let audience = #"{"filter":[{"eq":[{"var":"country"},{"value":"DE"}]}]}"#
			let first = rules.contextData(
				rules.experimentJSON(
					rules: rules.rules("{\"type\":\"assign\",\"variant\":2,\"conditions\":\(rules.countryNL)}"),
					audience: audience))
			let env = ContextEnv()
			let context = env.directContext(data: first, units: [.sessionID: "unit-1"], attributes: ["country": "DE"])
			let variant = rules.defaultVariant
			let beforeWarmup = context.assignmentCacheWriteCount
			#expect(context.treatment(for: "exp") == variant)
			#expect(context.assignmentCacheWriteCount == beforeWarmup + 1)
			let warmed = context.assignmentCacheWriteCount

			func readRepeatedly() {
				for _ in 0..<100 {
					#expect(context.treatment(for: "exp") == variant)
					#expect(context.treatment(for: "exp", exposing: false) == variant)
					#expect(context.variableValue("color") == .int(Int64(variant)))
					#expect(context.variableValue("color", exposing: false) == .int(Int64(variant)))
				}
				#expect(context.assignmentCacheWriteCount == warmed)
			}

			context.setAttribute("unrelated", to: true)
			readRepeatedly()
			#expect(context.revalidationCount == 1)

			env.serveNext(
				rules.contextData(
					rules.experimentJSON(
						rules: rules.rules(
							"{\"type\":\"assign\",\"variant\":1,\"conditions\":\(rules.countryNL)}",
							#"{"type":"assign","variant":2,"environments":["staging"]}"#), audience: audience)))
			try await context.refresh()
			readRepeatedly()
			#expect(context.revalidationCount == 2)
			#expect(context.pendingEventCount == 1)
		#endif
	}

	@Test func goalTrackingPerformance() {
		let context = Harness().context()
		let pendingBefore = context.pendingEventCount

		measured {
			for i in 0..<100 {
				context.track("goal_\(i % 10)", properties: ["iteration": .int(Int64(i))])
			}
		}

		let queuedDuringMeasure = context.pendingEventCount - pendingBefore
		#expect(queuedDuringMeasure >= 100)
		#expect(queuedDuringMeasure % 100 == 0)
	}

	@Test func variableAccessPerformance() {
		let context = Harness().context()
		let variableKeys = ["banner.border", "banner.size", "button.color", "submit.color", "submit.shape"]

		measured {
			for _ in 0..<100 {
				for key in variableKeys {
					_ = context.variableValue(key, exposing: false)
				}
			}
		}

		#expect(context.pendingEventCount == 0)
	}

	@Test func overrideSettingPerformance() {
		let context = Harness().context()

		measured {
			for i in 0..<1000 {
				context.overrides["exp_\(i % 100)"] = i % 5
			}
		}

		#expect(context.overrides["exp_50"] != nil)
	}

	@Test func customAssignmentPerformance() {
		let context = Harness().context()

		measured {
			for i in 0..<1000 {
				context.customAssignments["exp_\(i % 100)"] = i % 5
			}
		}

		#expect(context.customAssignments["exp_50"] != nil)
	}

	@Test func unitSettingPerformance() throws {
		let context = Harness().context(units: [:])

		try measured {
			for i in 0..<100 {
				try context.setUnit(UnitType("unit_\(i)"), to: "uid_\(i)")
			}
		}

		#expect(context.units.count == 100)
	}

	@Test func contextCreationPerformance() {
		let harness = Harness()
		let contextData = Fixtures.contextData()

		measured {
			for _ in 0..<10 {
				let context = harness.context(data: contextData)
				#expect(context.state == .ready)
			}
		}
	}

	@Test func cacheMemoryUsage() {
		let context = Harness().context()

		let experiments = context.experiments
		for experimentName in experiments {
			_ = context.treatment(for: experimentName)
		}

		#expect(context.pendingEventCount == experiments.count)

		for i in 0..<100 {
			context.track("goal_\(i)", properties: ["data": .string(String(repeating: "x", count: 100))])
		}

		#expect(context.pendingEventCount == experiments.count + 100)
	}
}
