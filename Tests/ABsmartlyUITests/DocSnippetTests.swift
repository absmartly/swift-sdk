import ABsmartly
import Foundation
import Testing

// Every code example in README.md and MIGRATING.md, compiled (and where it can run offline, run).
// The README quotes these snippets verbatim; keep the two in sync. Uses only the public API.

private struct CheckoutConfig: Codable, Sendable {
	var steps: Int
	static let standard = CheckoutConfig(steps: 3)
}

private enum CheckoutVariant: Int {
	case control, single, express
}

@Suite struct DocSnippetTests {
	let deviceID = "device-1"
	let apiKey = "YOUR-API-KEY"

	func makeClient(transport: (any Transport)? = nil) throws -> ABsmartlyClient {
		// README: Initialization
		let client = try ABsmartlyClient(
			endpoint: URL(string: "https://your-company.absmartly.io/v1")!,
			apiKey: apiKey,
			application: "website",
			environment: .production
		)
		guard let transport else { return client }

		// README: Advanced configuration
		var configuration = ABsmartlyClient.Configuration(
			endpoint: URL(string: "https://your-company.absmartly.io/v1")!,
			apiKey: apiKey,
			application: "website",
			environment: "staging")
		configuration.applicationVersion = "1042"
		configuration.timeout = 3
		configuration.retries = 3
		configuration.transport = transport
		configuration.eventLogger = .custom { context, event in
			print("ABsmartly event: \(event)")
		}
		return try ABsmartlyClient(configuration: configuration)
	}

	@Test func creatingContexts() async throws {
		let transport = SnippetTransport()
		let client = try makeClient(transport: transport)
		let contextData = try await client.fetchContextData()

		do {
			// README: Creating a context, 1
			// 1. Await until ready (common case); throws if the context data can't be fetched
			let context = try await client.context(units: [.deviceID: deviceID])
			#expect(context.state == .ready)
		}
		do {
			// README: Creating a context, 2
			// 2. Create now, wait later (e.g. start at launch, await before the first screen needs it)
			let context = client.makeContext(units: [.deviceID: deviceID])
			try await context.ready()
			#expect(context.state == .ready)
		}
		do {
			// README: Creating a context, 3
			// 3. Pre-fetched data from your server: synchronous, ready immediately
			let context = client.context(units: [.deviceID: deviceID], data: contextData)
			#expect(context.state == .ready)
		}
		do {
			// README: Creating a context, options
			let context = try await client.context(
				units: [.deviceID: deviceID, .userID: "user-42"],
				attributes: ["plan": "pro", "age": 42],
				overrides: ["exp_banner": 1],
				options: Context.Options(publishDelay: 0.1, refreshInterval: 300)
			)
			try await context.close()
		}
	}

	@Test func readsAndOverrides() async throws {
		let client = try makeClient(transport: SnippetTransport())
		let context = try await client.context(units: [.deviceID: deviceID])

		// README: Treatments
		let variant = context.treatment(for: "exp_checkout")
		if variant == 1 {
			// show the new checkout
		}
		let peeked = context.treatment(for: "exp_checkout", exposing: false)
		if context.isInTreatment("exp_checkout") {
			// variant != 0
		}
		let style = context.treatment(for: "exp_checkout", as: CheckoutVariant.self)

		// README: Variables
		let color: String = context.variable("button.color", default: "blue")
		let limit = context.variable("cart.limit", default: 10)
		let config: CheckoutConfig = context.variable("checkout", default: .standard)
		let raw: JSONValue? = context.variableValue("checkout")

		// README: Overrides
		let overridden = client.context(
			units: [.deviceID: deviceID], overrides: ["exp_checkout": 1, "exp_banner": 2], data: ContextData())
		overridden.setOverride(2, for: "exp_checkout")
		overridden.setOverrides(["exp_banner": 1, "exp_search": 2])
		overridden.setOverride(nil, for: "exp_banner")
		overridden.setCustomAssignment(1, for: "exp_search")
		let current = overridden.overrides

		// README: Attributes and units
		context.setAttribute("plan", to: "pro")
		context.setAttributes(["age": 42, "country": "PT"])
		try context.setUnit(.userID, to: "user-42")

		// README: Goals
		context.track("purchase", properties: ["total": 19.99, "items": 2])

		// README: Publishing, refreshing and closing
		try await context.publish()
		try await context.refresh()
		try await context.close()

		#expect(variant == 1 && peeked == 1 && style == .single)
		#expect(color == "red" && limit == 10 && config.steps == 3 && raw == nil)
		#expect(current == ["exp_checkout": 2, "exp_search": 2])
	}

	@Test func stateAndEvents() async throws {
		let client = try makeClient(transport: SnippetTransport())
		let context = client.makeContext(units: [.deviceID: deviceID])

		// README: Events
		let listener = Task {
			var seen: [String] = []
			for await event in context.events {
				switch event {
				case .ready: seen.append("ready")
				case .exposure(let exposure): seen.append("exposure \(exposure.name)")
				case .goal(let goal): seen.append("goal \(goal.name)")
				case .error(let error): seen.append("error \(error)")
				case .refresh, .publish: break
				case .close: seen.append("close")
				}
			}
			return seen
		}

		// README: State
		switch context.state {
		case .loading: print("loading")
		case .ready: print("ready")
		case .failed(let error): print("failed: \(error)")
		case .closing, .closed: print("closed")
		}

		try await context.ready()
		_ = context.treatment(for: "exp_checkout")
		try await context.close()
		let seen = await listener.value
		#expect(seen.last == "close")
	}

	@Test func errors() async throws {
		let transport = SnippetTransport(status: 500)
		let client = try makeClient(transport: transport)

		// README: Errors
		do {
			let context = try await client.context(units: [.deviceID: deviceID])
			_ = context.treatment(for: "exp_checkout")
		} catch .httpStatus(let code, _) {
			print("ABsmartly is unavailable (\(code)); using defaults")
		} catch {
			print("ABsmartly failed: \(error.localizedDescription)")
		}
	}
}

#if canImport(SwiftUI) && canImport(ABsmartlyUI)
	import SwiftUI
	import ABsmartlyUI

	// README: SwiftUI
	struct RootView: View {
		var body: some View { CheckoutButton() }
	}

	struct CheckoutButton: View {
		@Treatment("exp_checkout") var variant
		@Variable("button.color", default: "blue") var color: String

		var body: some View {
			Button(variant == 1 ? "Buy now" : "Buy") {}
		}
	}

	@MainActor
	func appScene(context: Context) -> some View {
		RootView().absmartlyContext(context)
	}

	// README: View model
	@MainActor
	final class CheckoutModel: ObservableObject {
		@Published var showExpressCheckout = false
		private let context: Context

		init(context: Context) {
			self.context = context
			showExpressCheckout = context.treatment(for: "exp_checkout") == 2
		}

		func purchase(total: Double) {
			context.track("purchase", properties: ["total": .double(total)])
			Task { try? await context.publish() }
		}
	}
#endif

/// Serves one experiment (`exp_checkout`, variant 1 for every unit, with `button.color`) offline.
private final class SnippetTransport: Transport {
	let status: Int

	init(status: Int = 200) {
		self.status = status
	}

	func send(_ request: HTTPRequest) async throws -> HTTPResponse {
		guard status == 200 else { return HTTPResponse(statusCode: status, body: Data()) }
		if request.method != "GET" {
			return HTTPResponse(statusCode: 200, body: Data("{}".utf8))
		}
		let json = #"""
			{"experiments":[{"id":1,"name":"exp_checkout","unitType":"device_id","iteration":1,"seedHi":1,"seedLo":2,
			"split":[0,1,0],"trafficSeedHi":3,"trafficSeedLo":4,"trafficSplit":[0,1],"fullOnVariant":0,
			"variants":[{"name":"A","config":null},{"name":"B","config":"{\"button.color\":\"red\"}"},{"name":"C","config":null}]}]}
			"""#
		return HTTPResponse(statusCode: 200, body: Data(json.utf8))
	}
}
