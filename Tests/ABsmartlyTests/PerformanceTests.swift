import Foundation
import Testing

@testable import ABsmartly

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

	// The peeks are also checked to queue nothing.
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

	// Setting the same UID again is accepted, so the 10 runs leave 100 units.
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
