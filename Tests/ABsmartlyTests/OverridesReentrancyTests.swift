import Foundation
import Testing

@testable import ABsmartly

// `overrides`/`customAssignments` updates whose expression reads the same context must not deadlock:
// the expression runs before the context's lock is taken. Each case runs on its own thread with a
// bounded wait, so a regression fails the test instead of hanging the suite.
@Suite struct OverridesReentrancyTests {
	private static func completes(within seconds: TimeInterval = 2, _ body: @escaping @Sendable () -> Void) -> Bool {
		let done = DispatchSemaphore(value: 0)
		Thread {
			body()
			done.signal()
		}.start()
		return done.wait(timeout: .now() + seconds) == .success
	}

	@Test func overrideDefaultSubscriptMayReadTheContext() {
		let context = Harness().context()
		let finished = Self.completes {
			context.overrides["exp_test_ab", default: context.treatment(for: "exp_test_abc", exposing: false)] += 1
		}
		#expect(finished)
		#expect(context.overrides["exp_test_ab"] == 3)
	}

	@Test func overrideMergeClosureMayReadTheContext() {
		let context = Harness().context()
		let finished = Self.completes {
			context.overrides.merge(["exp_test_ab": 1]) { _, new in new + context.pendingEventCount }
		}
		#expect(finished)
		#expect(context.overrides["exp_test_ab"] == 1)
	}

	@Test func customAssignmentDefaultSubscriptMayReadTheContext() {
		let context = Harness().context()
		let finished = Self.completes {
			context.customAssignments["exp_test_ab", default: context.treatment(for: "exp_test_abc", exposing: false)] += 1
		}
		#expect(finished)
		#expect(context.customAssignments["exp_test_ab"] == 3)
	}

	@Test func concurrentOverrideWritesAreNotLost() async {
		let context = Harness().context()
		await withTaskGroup(of: Void.self) { group in
			for i in 0..<200 {
				group.addTask { context.setOverrides(["exp_\(i)": i]) }
			}
		}
		#expect(context.overrides.count == 200)
	}
}
