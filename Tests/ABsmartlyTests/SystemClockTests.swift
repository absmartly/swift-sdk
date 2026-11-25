import Foundation
import Testing

@testable import ABsmartly

// The production clock behind the publish and refresh timers: it really waits, in seconds, and
// stops when cancelled (the timer tests use TestClock).
@Suite struct SystemClockTests {
	@Test func sleepWaitsTheGivenSeconds() async throws {
		let start = Date()
		try await SystemClock().sleep(seconds: 1)
		#expect(Date().timeIntervalSince(start) >= 0.9)
	}

	@Test func sleepThrowsWhenCancelled() async {
		let sleeping = Task { try await SystemClock().sleep(seconds: 600) }
		sleeping.cancel()
		await #expect(throws: CancellationError.self) { try await sleeping.value }
	}

	// Delays a caller can configure (`publishDelay`, `refreshInterval`) that do not fit a
	// nanosecond count are clamped instead of trapping; the sleep is then cancelled.
	@Test(arguments: [Double.infinity, 1e300, -1, .nan])
	func sleepClampsDelaysThatDoNotFitNanoseconds(seconds: Double) async {
		let sleeping = Task { try await SystemClock().sleep(seconds: seconds) }
		sleeping.cancel()
		_ = try? await sleeping.value
	}

	@Test func millisIsTheWallClock() {
		let now = Int64(Date().timeIntervalSince1970 * 1000)
		#expect(abs(SystemClock().millis() - now) < 1000)
	}
}
