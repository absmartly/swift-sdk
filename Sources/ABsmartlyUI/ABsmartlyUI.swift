#if !ABSMARTLY_SINGLE_MODULE
	@_exported import ABsmartly
#endif

#if canImport(SwiftUI)
	import SwiftUI

	/// Re-renders readers when the currently supplied context becomes ready, refreshes or closes.
	@MainActor
	final class ContextObserver: ObservableObject {
		@Published private(set) var revision = 0

		func observe(_ context: Context?) async {
			guard let context, !Task.isCancelled else { return }
			let events = context.events
			// Re-read after subscribing: readiness may have changed since the view last rendered.
			revision += 1
			for await event in events {
				// A replaced context may still have buffered events when its task is cancelled.
				guard !Task.isCancelled else { return }
				switch event {
				case .ready, .refresh, .close:
					revision += 1
				default:
					break
				}
			}
		}
	}

	private struct ContextKey: EnvironmentKey {
		static let defaultValue: Context? = nil
	}

	extension EnvironmentValues {
		/// The ABsmartly context `@Treatment` and `@Variable` read; set it with `.absmartlyContext(_:)`.
		public var absmartlyContext: Context? {
			get { self[ContextKey.self] }
			set { self[ContextKey.self] = newValue }
		}
	}

	private struct ContextModifier: ViewModifier {
		let context: Context?
		@StateObject private var observer = ContextObserver()

		func body(content: Content) -> some View {
			content
				.environment(\.absmartlyContext, context)
				.environment(\.absmartlyRevision, observer.revision)
				// Restart only the subscription, not the identity (and state) of the descendants.
				.task(id: context.map(ObjectIdentifier.init)) {
					await observer.observe(context)
				}
		}
	}

	private struct RevisionKey: EnvironmentKey {
		static let defaultValue = 0
	}

	extension EnvironmentValues {
		// Changes when the context becomes ready or refreshes, so wrappers that read it re-render.
		var absmartlyRevision: Int {
			get { self[RevisionKey.self] }
			set { self[RevisionKey.self] = newValue }
		}
	}

	extension View {
		/// Makes `context` available to `@Treatment` and `@Variable` in this view hierarchy. Views that
		/// read them re-render when the context becomes ready or refreshes.
		public func absmartlyContext(_ context: Context?) -> some View {
			modifier(ContextModifier(context: context))
		}
	}

	/// The variant of an experiment for the environment's context: `0` without a context or before
	/// it is ready. Reading it queues the exposure, like `Context.treatment(for:)`.
	///
	/// ```swift
	/// @Treatment("exp_checkout") var variant
	/// ```
	@MainActor
	@propertyWrapper
	public struct Treatment: DynamicProperty {
		@Environment(\.absmartlyContext) private var context
		@Environment(\.absmartlyRevision) private var revision
		private let experiment: String
		private let exposing: Bool

		public init(_ experiment: String, exposing: Bool = true) {
			self.experiment = experiment
			self.exposing = exposing
		}

		public var wrappedValue: Int {
			guard let context, context.state == .ready else { return 0 }
			return context.treatment(for: experiment, exposing: exposing)
		}
	}

	/// A variable for the environment's context, decoded as `Value`: the default without a context,
	/// before it is ready, or when no running experiment defines the key. Reading it queues the
	/// exposure, like `Context.variable(_:default:)`.
	///
	/// ```swift
	/// @Variable("button.color", default: "blue") var color: String
	/// ```
	@MainActor
	@propertyWrapper
	public struct Variable<Value: Decodable & Sendable>: DynamicProperty {
		@Environment(\.absmartlyContext) private var context
		@Environment(\.absmartlyRevision) private var revision
		private let key: String
		private let defaultValue: Value
		private let exposing: Bool

		public init(_ key: String, default defaultValue: Value, exposing: Bool = true) {
			self.key = key
			self.defaultValue = defaultValue
			self.exposing = exposing
		}

		public var wrappedValue: Value {
			guard let context, context.state == .ready else { return defaultValue }
			return context.variable(key, default: defaultValue, exposing: exposing)
		}
	}
#endif
