// Opt-in module: `import ABSmartlyAsync` (which also imports ABSmartly) adds these overloads.
// They are not in ABSmartly itself because, inside an `async` function, Swift prefers an async
// overload, so v1.4.0 code such as `_ = context.publish()` there would stop compiling. Once any
// module in a build imports this one, the overloads are visible to every file using ABSmartly,
// unless that file's module enables MemberImportVisibility (Swift 6.1+).
@_exported import ABSmartly
import Foundation
import PromiseKit

// async/await versions of the SDK's Promise-returning methods. Each one awaits the Promise the
// existing method returns, so it behaves exactly like it: same work, same result, same error.
//
// Cancelling the calling Task does not cancel the underlying work (a fetch, publish or close
// keeps going, as with the Promise), and the call still waits for it to settle and returns its
// result; check `Task.isCancelled` afterwards if needed.
//
// Outside an async context (e.g. a plain `do {}` in synchronous code), `try await
// context.waitUntilReady()` resolves to the Promise method and does not wait; the compiler
// warns "no 'async' operations occur within 'await' expression". Call it from an async function
// or a `Task {}`.
//
// A type that adopts two of `Client`, `ContextDataProvider`, `ContextEventHandler` and
// `HTTPClient` gets two async overloads of the methods they share (`getContextData`,
// `publish(event:)`, `close`); call through one protocol: `try await (x as Client).close()`.
//
// With Swift 6 compilers the methods run in the caller's isolation (`#isolation`), so a
// `Context` can be awaited from a `@MainActor` or actor method without a Sendable diagnostic.

// Only a plain compiler-version condition keeps older compilers (the package supports tools-version
// 5.3) from parsing the async syntax inside.
#if compiler(>=5.5)

@available(iOS 13, macOS 10.15, tvOS 13, watchOS 6, *)
extension Promise {
	#if compiler(>=6.0)
	func asyncValue(isolation: isolated (any Actor)? = #isolation) async throws -> T {
		return try await withCheckedThrowingContinuation { continuation in
			pipe { result in
				switch result {
				case .fulfilled(let value):
					continuation.resume(returning: value)
				case .rejected(let error):
					continuation.resume(throwing: error)
				}
			}
		}
	}
	#else
	func asyncValue() async throws -> T {
		return try await withCheckedThrowingContinuation { continuation in
			pipe { result in
				switch result {
				case .fulfilled(let value):
					continuation.resume(returning: value)
				case .rejected(let error):
					continuation.resume(throwing: error)
				}
			}
		}
	}
	#endif
}

#if compiler(>=6.0)

@available(iOS 13, macOS 10.15, tvOS 13, watchOS 6, *)
extension Context {
	/// Waits until the context is ready, like `waitUntilReady() -> Promise<Context>`. As with the
	/// Promise, a context whose data failed to load is also ready (check `isFailed()`).
	@discardableResult
	public func waitUntilReady(isolation: isolated (any Actor)? = #isolation) async throws -> Context {
		let promise: Promise<Context> = waitUntilReady()
		return try await promise.asyncValue()
	}

	/// Fetches fresh experiment data, like `refresh() -> Promise<Void>`.
	public func refresh(isolation: isolated (any Actor)? = #isolation) async throws {
		let promise: Promise<Void> = refresh()
		try await promise.asyncValue()
	}

	/// Publishes pending events, like `publish() -> Promise<Void>`.
	public func publish(isolation: isolated (any Actor)? = #isolation) async throws {
		let promise: Promise<Void> = publish()
		try await promise.asyncValue()
	}

	/// Publishes pending events and closes the context, like `close() -> Promise<Void>`.
	public func close(isolation: isolated (any Actor)? = #isolation) async throws {
		let promise: Promise<Void> = close()
		try await promise.asyncValue()
	}

	/// Alias for `close()`.
	public func finalize(isolation: isolated (any Actor)? = #isolation) async throws {
		let promise: Promise<Void> = finalize()
		try await promise.asyncValue()
	}
}

@available(iOS 13, macOS 10.15, tvOS 13, watchOS 6, *)
extension ABSmartlySDK {
	/// Fetches context data, like `getContextData() -> Promise<ContextData>`.
	public func getContextData(isolation: isolated (any Actor)? = #isolation) async throws -> ContextData {
		let promise: Promise<ContextData> = getContextData()
		return try await promise.asyncValue()
	}

	/// Closes the client, like `close() -> Promise<Void>`.
	public func close(isolation: isolated (any Actor)? = #isolation) async throws {
		let promise: Promise<Void> = close()
		try await promise.asyncValue()
	}
}

@available(iOS 13, macOS 10.15, tvOS 13, watchOS 6, *)
extension Client {
	public func getContextData(isolation: isolated (any Actor)? = #isolation) async throws -> ContextData {
		let promise: Promise<ContextData> = getContextData()
		return try await promise.asyncValue()
	}

	public func publish(event: PublishEvent, isolation: isolated (any Actor)? = #isolation) async throws {
		let promise: Promise<Void> = publish(event: event)
		try await promise.asyncValue()
	}

	public func close(isolation: isolated (any Actor)? = #isolation) async throws {
		let promise: Promise<Void> = close()
		try await promise.asyncValue()
	}
}

@available(iOS 13, macOS 10.15, tvOS 13, watchOS 6, *)
extension ContextDataProvider {
	public func getContextData(isolation: isolated (any Actor)? = #isolation) async throws -> ContextData {
		let promise: Promise<ContextData> = getContextData()
		return try await promise.asyncValue()
	}
}

@available(iOS 13, macOS 10.15, tvOS 13, watchOS 6, *)
extension ContextEventHandler {
	public func publish(event: PublishEvent, isolation: isolated (any Actor)? = #isolation) async throws {
		let promise: Promise<Void> = publish(event: event)
		try await promise.asyncValue()
	}
}

@available(iOS 13, macOS 10.15, tvOS 13, watchOS 6, *)
extension DefaultHTTPClient {
	public func request(
		method: String, url: String, query: [String: String]?, headers: [String: String]?, body: Data?,
		isolation: isolated (any Actor)? = #isolation
	) async throws -> Response {
		let promise: Promise<Response> = request(method: method, url: url, query: query, headers: headers, body: body)
		return try await promise.asyncValue()
	}
}

@available(iOS 13, macOS 10.15, tvOS 13, watchOS 6, *)
extension HTTPClient {
	public func get(
		url: String, query: [String: String]?, headers: [String: String]?,
		isolation: isolated (any Actor)? = #isolation
	) async throws -> Response {
		let promise: Promise<Response> = get(url: url, query: query, headers: headers)
		return try await promise.asyncValue()
	}

	public func put(
		url: String, query: [String: String]?, headers: [String: String]?, body: Data?,
		isolation: isolated (any Actor)? = #isolation
	) async throws -> Response {
		let promise: Promise<Response> = put(url: url, query: query, headers: headers, body: body)
		return try await promise.asyncValue()
	}

	public func post(
		url: String, query: [String: String]?, headers: [String: String]?, body: Data?,
		isolation: isolated (any Actor)? = #isolation
	) async throws -> Response {
		let promise: Promise<Response> = post(url: url, query: query, headers: headers, body: body)
		return try await promise.asyncValue()
	}

	public func close(isolation: isolated (any Actor)? = #isolation) async throws {
		let promise: Promise<Void> = close()
		try await promise.asyncValue()
	}
}

#else

// Swift 5.5–5.10 compilers have no `#isolation`; the same methods, without it.

@available(iOS 13, macOS 10.15, tvOS 13, watchOS 6, *)
extension Context {
	@discardableResult
	public func waitUntilReady() async throws -> Context {
		let promise: Promise<Context> = waitUntilReady()
		return try await promise.asyncValue()
	}

	public func refresh() async throws {
		let promise: Promise<Void> = refresh()
		try await promise.asyncValue()
	}

	public func publish() async throws {
		let promise: Promise<Void> = publish()
		try await promise.asyncValue()
	}

	public func close() async throws {
		let promise: Promise<Void> = close()
		try await promise.asyncValue()
	}

	public func finalize() async throws {
		let promise: Promise<Void> = finalize()
		try await promise.asyncValue()
	}
}

@available(iOS 13, macOS 10.15, tvOS 13, watchOS 6, *)
extension ABSmartlySDK {
	public func getContextData() async throws -> ContextData {
		let promise: Promise<ContextData> = getContextData()
		return try await promise.asyncValue()
	}

	public func close() async throws {
		let promise: Promise<Void> = close()
		try await promise.asyncValue()
	}
}

@available(iOS 13, macOS 10.15, tvOS 13, watchOS 6, *)
extension Client {
	public func getContextData() async throws -> ContextData {
		let promise: Promise<ContextData> = getContextData()
		return try await promise.asyncValue()
	}

	public func publish(event: PublishEvent) async throws {
		let promise: Promise<Void> = publish(event: event)
		try await promise.asyncValue()
	}

	public func close() async throws {
		let promise: Promise<Void> = close()
		try await promise.asyncValue()
	}
}

@available(iOS 13, macOS 10.15, tvOS 13, watchOS 6, *)
extension ContextDataProvider {
	public func getContextData() async throws -> ContextData {
		let promise: Promise<ContextData> = getContextData()
		return try await promise.asyncValue()
	}
}

@available(iOS 13, macOS 10.15, tvOS 13, watchOS 6, *)
extension ContextEventHandler {
	public func publish(event: PublishEvent) async throws {
		let promise: Promise<Void> = publish(event: event)
		try await promise.asyncValue()
	}
}

@available(iOS 13, macOS 10.15, tvOS 13, watchOS 6, *)
extension DefaultHTTPClient {
	public func request(method: String, url: String, query: [String: String]?, headers: [String: String]?, body: Data?)
		async throws -> Response
	{
		let promise: Promise<Response> = request(method: method, url: url, query: query, headers: headers, body: body)
		return try await promise.asyncValue()
	}
}

@available(iOS 13, macOS 10.15, tvOS 13, watchOS 6, *)
extension HTTPClient {
	public func get(url: String, query: [String: String]?, headers: [String: String]?) async throws -> Response {
		let promise: Promise<Response> = get(url: url, query: query, headers: headers)
		return try await promise.asyncValue()
	}

	public func put(url: String, query: [String: String]?, headers: [String: String]?, body: Data?) async throws
		-> Response
	{
		let promise: Promise<Response> = put(url: url, query: query, headers: headers, body: body)
		return try await promise.asyncValue()
	}

	public func post(url: String, query: [String: String]?, headers: [String: String]?, body: Data?) async throws
		-> Response
	{
		let promise: Promise<Response> = post(url: url, query: query, headers: headers, body: body)
		return try await promise.asyncValue()
	}

	public func close() async throws {
		let promise: Promise<Void> = close()
		try await promise.asyncValue()
	}
}

#endif

#endif
