import Foundation

#if canImport(FoundationNetworking)
	import FoundationNetworking
#endif

// Sent as the X-Agent header ("absmartly-swift-sdk/<version>"). Keep `version` equal to the podspec's
// `spec.version`: the release workflow refuses to publish a tag where they differ.
enum SDKVersion {
	static let name = "absmartly-swift-sdk"
	static let version = "2.2.0"
	static let agent = "\(name)/\(version)"
}

/// The SDK's HTTP calls to the collector: building requests, retrying, checking the status and
/// (de)serialising, over the configured `Transport`.
struct Connection: Sendable {
	let transport: any Transport
	/// `GET` URL: `<endpoint>/context?application=…&environment=…`.
	let url: URL
	/// `PUT` URL: `<endpoint>/context`, without a query (as 1.x's `put(url:query: nil)`).
	let publishURL: URL
	let headers: [String: String]
	let timeout: TimeInterval
	let retries: Int
	let retryInterval: TimeInterval

	init(configuration: ABsmartlyClient.Configuration) {
		transport = configuration.transport ?? URLSessionTransport(timeout: configuration.timeout)
		// Appended like 1.x's `endpoint + "/context"`, so a trailing slash is kept as given.
		var components = URLComponents(string: configuration.endpoint.absoluteString + "/context")!
		publishURL = components.url!
		components.queryItems = [
			URLQueryItem(name: "application", value: configuration.application),
			URLQueryItem(name: "environment", value: configuration.environment.rawValue),
		]
		url = components.url!
		timeout = configuration.timeout
		retries = configuration.retries
		retryInterval = configuration.retryInterval
		// Sent on both the context GET and the publish PUT, as javascript-sdk does on every request.
		headers = [
			"Content-Type": "application/json; charset=utf-8",
			"X-Agent": SDKVersion.agent,
			"X-API-Key": configuration.apiKey,
			"X-Environment": configuration.environment.rawValue,
			"X-Application": configuration.application,
			"X-Application-Version": Self.wireApplicationVersion(configuration.applicationVersion),
		]
	}

	// The collector binds X-Application-Version as a Long and rejects anything else with HTTP 400,
	// which would stop the context from loading. Like the Java SDK, only the header value is
	// normalised: trimmed, 1–18 ASCII digits are sent as-is, anything else as "0".
	static func wireApplicationVersion(_ version: String) -> String {
		let trimmed = version.unicodeScalars.drop(while: { $0.value <= 0x20 }).reversed().drop(while: {
			$0.value <= 0x20
		}).reversed()
		guard (1...18).contains(trimmed.count), trimmed.allSatisfy({ $0 >= "0" && $0 <= "9" }) else {
			return "0"
		}
		return String(String.UnicodeScalarView(trimmed))
	}

	func fetchContextData() async throws(ABsmartlyError) -> ContextData {
		let response = try await send(method: "GET", url: url, body: nil)
		return try ContextData(json: response.body)
	}

	func publish(_ event: PublishEvent) async throws(ABsmartlyError) {
		let body: Data
		do {
			body = try JSONEncoder.absmartly().encode(event)
		} catch {
			// Non-finite numbers encode as null; Foundation can still reject, e.g., very deep nesting.
			throw .decoding(error.safeDescription)
		}
		_ = try await send(method: "PUT", url: publishURL, body: body)
	}

	// 1.x's retry policy: a request that fails without a response is retried up to `retries` times;
	// a 502 or 503 is retried until the `retries`-th attempt, whose response is final. Other
	// statuses are final. Attempts are `retryInterval` apart.
	private func send(method: String, url: URL, body: Data?) async throws(ABsmartlyError) -> HTTPResponse {
		let request = HTTPRequest(method: method, url: url, headers: headers, body: body, timeout: timeout)
		var attempt = 1
		while true {
			do {
				let response = try await transport.send(request)
				let retryable = response.statusCode == 502 || response.statusCode == 503
				if retryable && attempt < retries {
					throw ABsmartlyError.httpStatus(
						code: response.statusCode, message: Self.statusMessage(response.statusCode))
				}
				guard (200...299).contains(response.statusCode) else {
					throw ABsmartlyError.httpStatus(
						code: response.statusCode, message: Self.statusMessage(response.statusCode))
				}
				return response
			} catch {
				let wrapped = ABsmartlyError.wrapping(error)
				let finalStatus: Bool
				if case .httpStatus(let code, _) = wrapped {
					finalStatus = !((code == 502 || code == 503) && attempt < retries)
				} else {
					finalStatus = false
				}
				if wrapped == .cancelled || finalStatus || attempt > retries {
					throw wrapped
				}
			}
			attempt += 1
			do {
				try await Task.sleep(nanoseconds: UInt64(max(0, retryInterval) * 1_000_000_000))
			} catch {
				throw .cancelled
			}
		}
	}

	static func statusMessage(_ code: Int) -> String {
		HTTPURLResponse.localizedString(forStatusCode: code)
	}
}
