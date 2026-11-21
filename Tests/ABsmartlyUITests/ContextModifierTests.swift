#if canImport(SwiftUI) && canImport(AppKit)
	import AppKit
	import SwiftUI
	import Testing

	import ABsmartly
	@testable import ABsmartlyUI

	@Suite(.serialized)
	@MainActor
	struct ContextModifierTests {
		enum Transition: CaseIterable, Sendable {
			case nilToContext, contextToContext, contextToNil
		}

		@Test(arguments: Transition.allCases)
		func retargetsMountedHierarchy(_ transition: Transition) async throws {
			let a = try makeContext(variant: 1)
			let b = try makeContext(variant: 2)
			let initial: Context? = transition == .nilToContext ? nil : a
			let replacement: Context? = transition == .contextToNil ? nil : (initial == nil ? a : b)
			let mounted = MountedHierarchy(context: initial)
			defer { mounted.window.close() }

			try await mounted.waitUntil { mounted.matches(context: initial, variant: initial == nil ? 0 : 1) }
			try await mounted.settle()
			let descendantState = try #require(mounted.recorder.snapshot).descendantState

			// Update the input of the existing modifier, not the hosting view's root or its identity.
			mounted.input.context = replacement
			let variant = replacement === b ? 2 : (replacement == nil ? 0 : 1)
			try await mounted.waitUntil { mounted.matches(context: replacement, variant: variant) }
			#expect(mounted.recorder.snapshot?.descendantState == descendantState)

			// An obsolete context must no longer invalidate the mounted readers, even on lifecycle events.
			// Drain the new subscription's initial invalidation before measuring the revision.
			try await mounted.settle()
			let revision = try #require(mounted.recorder.snapshot).revision
			if let initial {
				initial.setOverride(2, for: "experiment")
				try await initial.refresh()
				try await initial.close()
				try await mounted.settle()
				#expect(mounted.recorder.snapshot?.revision == revision)
				#expect(mounted.matches(context: replacement, variant: variant))
			}

			if let replacement {
				// Merely re-evaluating the modifier with the same context must not restart its task.
				mounted.input.context = replacement
				try await mounted.settle()
				#expect(mounted.recorder.snapshot?.revision == revision)

				// Overrides do not emit an event. Only the replacement's refresh can update these readers.
				let refreshedVariant = variant == 1 ? 2 : 1
				replacement.setOverride(refreshedVariant, for: "experiment")
				try await replacement.refresh()
				try await mounted.waitUntil {
					mounted.matches(context: replacement, variant: refreshedVariant)
						&& (mounted.recorder.snapshot?.revision ?? 0) > revision
				}
				#expect(mounted.recorder.snapshot?.descendantState == descendantState)

				try await replacement.close()
				try await mounted.waitUntil { mounted.matches(context: replacement, variant: 0) }
			}
			#expect(mounted.recorder.snapshot?.descendantState == descendantState)
		}

		private func makeContext(variant: Int) throws -> Context {
			var configuration = ABsmartlyClient.Configuration(
				endpoint: URL(string: "https://example.com/v1")!, apiKey: "test",
				application: "test", environment: "test")
			configuration.transport = ContextTransport()
			let client = try ABsmartlyClient(configuration: configuration)
			return client.context(
				units: [.deviceID: "device"], overrides: ["experiment": variant],
				options: Context.Options(publishDelay: -1), data: ContextTransport.data)
		}
	}

	private struct ContextTransport: Transport {
		static let data = ContextData(experiments: [
			Experiment(
				id: 1, name: "experiment", unitType: "device_id", split: [0, 1, 0],
				variants: [
					ExperimentVariant(name: "control", config: nil),
					ExperimentVariant(name: "red", config: #"{"color":"red"}"#),
					ExperimentVariant(name: "green", config: #"{"color":"green"}"#),
				])
		])

		func send(_ request: HTTPRequest) async throws -> HTTPResponse {
			HTTPResponse(
				statusCode: 200,
				body: request.method == "GET" ? try JSONEncoder().encode(Self.data) : Data("{}".utf8))
		}
	}

	@MainActor
	private final class ContextInput: ObservableObject {
		@Published var context: Context?

		init(context: Context?) { self.context = context }
	}

	private struct Snapshot: Equatable {
		let contextID: ObjectIdentifier?
		let variant: Int
		let color: String
		let descendantState: UUID
		let revision: Int
	}

	@MainActor
	private final class Recorder {
		var snapshot: Snapshot?
	}

	private struct Root: View {
		@ObservedObject var input: ContextInput
		let recorder: Recorder

		var body: some View {
			Reader(recorder: recorder).absmartlyContext(input.context)
		}
	}

	private struct Reader: View {
		@Environment(\.absmartlyContext) private var context
		@Environment(\.absmartlyRevision) private var revision
		@Treatment("experiment") private var variant
		@Variable("color", default: "blue") private var color: String
		// This changes if a fix resets the descendant hierarchy with .id(context).
		@State private var descendantState = UUID()
		let recorder: Recorder

		var body: some View {
			SnapshotView(
				snapshot: Snapshot(
					contextID: context.map(ObjectIdentifier.init), variant: variant, color: color,
					descendantState: descendantState, revision: revision),
				recorder: recorder)
		}
	}

	// Record committed SwiftUI updates, rather than evaluating an unmounted view's body in the test.
	private struct SnapshotView: NSViewRepresentable {
		let snapshot: Snapshot
		let recorder: Recorder

		func makeNSView(context: NSViewRepresentableContext<Self>) -> NSView { NSView() }

		func updateNSView(_ nsView: NSView, context: NSViewRepresentableContext<Self>) {
			recorder.snapshot = snapshot
		}
	}

	@MainActor
	private final class MountedHierarchy {
		let input: ContextInput
		let recorder = Recorder()
		let window: NSWindow

		init(context: Context?) {
			_ = NSApplication.shared
			input = ContextInput(context: context)
			window = NSWindow(
				contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
				styleMask: [.borderless], backing: .buffered, defer: false)
			window.isReleasedWhenClosed = false
			window.contentView = NSHostingView(rootView: Root(input: input, recorder: recorder))
			window.orderFront(nil)
		}

		func matches(context: Context?, variant: Int) -> Bool {
			guard let snapshot = recorder.snapshot else { return false }
			return snapshot.contextID == context.map(ObjectIdentifier.init)
				&& snapshot.variant == variant
				&& snapshot.color == (variant == 1 ? "red" : (variant == 2 ? "green" : "blue"))
		}

		func waitUntil(_ condition: () -> Bool) async throws {
			let deadline = Date().addingTimeInterval(5)
			while !condition(), Date() < deadline {
				render()
				try await Task.sleep(nanoseconds: 10_000_000)
			}
			try #require(condition())
		}

		func settle() async throws {
			for _ in 0..<10 {
				render()
				try await Task.sleep(nanoseconds: 10_000_000)
			}
		}

		private func render() {
			window.contentView?.layoutSubtreeIfNeeded()
			RunLoop.main.run(until: Date().addingTimeInterval(0.01))
		}
	}
#endif
