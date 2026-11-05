import Foundation
import PromiseKit
import XCTest

@testable import ABSmartly

final class PerformanceTests: XCTestCase {
	var provider: ContextDataProviderMock = ContextDataProviderMock()
	var handler: ContextEventHandlerMock = ContextEventHandlerMock()
	var logger: ContextEventLoggerMock = ContextEventLoggerMock()
	var parser: VariableParser = DefaultVariableParser()
	var scheduler: SchedulerMock = SchedulerMock()
	var clock: ClockMock = ClockMock()

	let units = [
		"email": "bleh@absmartly.com",
		"session_id": "e791e240fcd3df7d238cfc285f475e8152fcc0ec",
		"user_id": "123456789",
	]

	override func setUp() async throws {
		provider = ContextDataProviderMock()
		handler = ContextEventHandlerMock()
		logger = ContextEventLoggerMock()
		parser = DefaultVariableParser()
		scheduler = SchedulerMock()
		scheduler.scheduleAfterExecuteReturnValue = ScheduledHandleMock()
		scheduler.scheduleWithFixedDelayAfterRepeatingExecuteReturnValue = ScheduledHandleMock()
		clock.millisReturnValue = 1_620_000_000_000
	}

	func getContextData(source: String = "context") throws -> ContextData {
		let path = TestResources.path(forResource: source, ofType: "json")
		let data = try Foundation.Data(contentsOf: URL(fileURLWithPath: path), options: .mappedIfSafe)
		return try JSONDecoder().decode(ContextData.self, from: data)
	}

	func createContext(config: ContextConfig, data: Promise<ContextData>? = nil) throws -> Context {
		let data = try data ?? Promise<ContextData>.value(try getContextData())
		return Context(
			config: config, clock: clock, scheduler: scheduler, handler: handler, provider: provider, logger: logger,
			parser: parser, matcher: AudienceMatcher(),
			promise: data)
	}

	func getContextConfig(withUnits: Bool = false) -> ContextConfig {
		let contextConfig: ContextConfig = ContextConfig()

		if withUnits {
			contextConfig.setUnits(units: units)
		}

		return contextConfig
	}

	func testLargeContextDataHandling() throws {
		let contextConfig: ContextConfig = getContextConfig(withUnits: true)
		let context = try createContext(config: contextConfig)

		XCTAssertTrue(context.isReady())

		let experiments = context.getExperiments()
		XCTAssertFalse(experiments.isEmpty)

		self.measure {
			for experimentName in experiments {
				_ = context.peekTreatment(experimentName)
			}
		}

		XCTAssertEqual(0, context.getPendingCount())
	}

	func testHighFrequencyOperations() throws {
		let contextConfig: ContextConfig = getContextConfig(withUnits: true)
		let context = try createContext(config: contextConfig)

		self.measure {
			for i in 0..<1000 {
				context.setAttribute(name: "attr_\(i % 100)", value: JSON("value_\(i)"))
			}
		}

		let attrs = context.getAttributes()
		XCTAssertGreaterThan(attrs.count, 0)
	}

	func testTreatmentAccessPerformance() throws {
		let contextConfig: ContextConfig = getContextConfig(withUnits: true)
		let context = try createContext(config: contextConfig)

		let experimentNames = context.getExperiments()

		self.measure {
			for _ in 0..<100 {
				for experimentName in experimentNames {
					_ = context.getTreatment(experimentName)
				}
			}
		}

		XCTAssertGreaterThan(context.getPendingCount(), 0)
	}

	func testGoalTrackingPerformance() throws {
		let contextConfig: ContextConfig = getContextConfig(withUnits: true)
		let context = try createContext(config: contextConfig)
		let pendingBefore = context.getPendingCount()

		self.measure {
			for i in 0..<100 {
				context.track("goal_\(i % 10)", properties: ["iteration": JSON(i)])
			}
		}

		let queuedDuringMeasure = Int(context.getPendingCount()) - Int(pendingBefore)
		XCTAssertGreaterThanOrEqual(queuedDuringMeasure, 100)
		XCTAssertEqual(0, queuedDuringMeasure % 100)
	}

	func testVariableAccessPerformance() throws {
		let contextConfig: ContextConfig = getContextConfig(withUnits: true)
		let context = try createContext(config: contextConfig)

		let variableKeys = ["banner.border", "banner.size", "button.color", "submit.color", "submit.shape"]

		self.measure {
			for _ in 0..<100 {
				for key in variableKeys {
					_ = context.peekVariableValue(key, defaultValue: nil)
				}
			}
		}
	}

	func testOverrideSettingPerformance() throws {
		let contextConfig: ContextConfig = getContextConfig(withUnits: true)
		let context = try createContext(config: contextConfig)

		self.measure {
			for i in 0..<1000 {
				context.setOverride(experimentName: "exp_\(i % 100)", variant: i % 5)
			}
		}

		let override = context.getOverride(experimentName: "exp_50")
		XCTAssertNotNil(override)
	}

	func testCustomAssignmentPerformance() throws {
		let contextConfig: ContextConfig = getContextConfig(withUnits: true)
		let context = try createContext(config: contextConfig)

		self.measure {
			for i in 0..<1000 {
				context.setCustomAssignment(experimentName: "exp_\(i % 100)", variant: i % 5)
			}
		}

		let assignment = context.getCustomAssignment(experimentName: "exp_50")
		XCTAssertNotNil(assignment)
	}

	func testUnitSettingPerformance() throws {
		let contextConfig: ContextConfig = getContextConfig(withUnits: false)
		let context = try createContext(config: contextConfig)

		self.measure {
			for i in 0..<100 {
				context.setUnit(unitType: "unit_\(i)", uid: "uid_\(i)")
			}
		}

		let units = context.getUnits()
		XCTAssertEqual(100, units.count)
	}

	func testContextCreationPerformance() throws {
		let contextConfig: ContextConfig = getContextConfig(withUnits: true)
		let contextData = try getContextData()

		self.measure {
			for _ in 0..<10 {
				let context = Context(
					config: contextConfig, clock: clock, scheduler: scheduler, handler: handler,
					provider: provider, logger: logger,
					parser: parser, matcher: AudienceMatcher(),
					promise: Promise<ContextData>.value(contextData))
				XCTAssertTrue(context.isReady())
			}
		}
	}

	func testCacheMemoryUsage() throws {
		let contextConfig: ContextConfig = getContextConfig(withUnits: true)
		let context = try createContext(config: contextConfig)

		let experiments = context.getExperiments()
		for experimentName in experiments {
			_ = context.getTreatment(experimentName)
		}

		XCTAssertEqual(UInt(experiments.count), context.getPendingCount())

		for i in 0..<100 {
			context.track("goal_\(i)", properties: ["data": JSON(String(repeating: "x", count: 100))])
		}

		XCTAssertEqual(UInt(experiments.count) + 100, context.getPendingCount())
	}
}
