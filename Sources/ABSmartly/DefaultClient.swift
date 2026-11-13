import Foundation
import PromiseKit

public final class DefaultClient: Client {
	private let config: ClientConfig
	private let httpClient: HTTPClient
	private let url: String
	private let getQuery: [String: String]
	private let headers: [String: String]
	// Captured at init, like getQuery/headers, so audience evaluation always sees the same
	// application/environment names used to fetch context data and publish exposures, even if the
	// caller mutates ClientConfig afterwards.
	private let application: String
	private let environment: String

	public convenience init(config: ClientConfig) throws {
		try self.init(config: config, httpClient: DefaultHTTPClient(config: DefaultHTTPClientConfig()))
	}

	public init(config: ClientConfig, httpClient: HTTPClient) throws {
		self.config = config
		self.httpClient = httpClient

		if config.endpoint.isEmpty {
			throw ABSmartlyError("Missing Endpoint configuration")
		}

		if config.apiKey.isEmpty {
			throw ABSmartlyError("Missing APIKey configuration")
		}

		if config.application.isEmpty {
			throw ABSmartlyError("Missing Application configuration")
		}

		if config.environment.isEmpty {
			throw ABSmartlyError("Missing Environment configuration")
		}

		application = config.application
		environment = config.environment

		url = config.endpoint + "/context"
		getQuery = ["application": config.application, "environment": config.environment]
		// Sent on both the context GET and the publish PUT, as javascript-sdk does on every request.
		headers = [
			"Content-Type": "application/json; charset=utf-8",
			"X-Agent": SDKVersion.agent,
			"X-API-Key": config.apiKey,
			"X-Environment": config.environment,
			"X-Application": config.application,
			"X-Application-Version": config.applicationVersion,
		]
	}

	public func getContextData() -> Promise<ContextData> {
		return Promise<ContextData> { seal in
			httpClient.get(url: url, query: getQuery, headers: headers).done(on: DispatchQueue.global()) { response in
				guard (200...299).contains(response.status) else {
					seal.reject(ABSmartlyHTTPError(response.status, response.statusMessage))
					return
				}
				do {
					let result = try JSONDecoder().decode(ContextData.self, from: response.content)
					seal.fulfill(result)
				} catch {
					seal.reject(error)
				}
			}.catch(on: DispatchQueue.global()) { error in
				seal.reject(error)
			}
		}
	}

	public func publish(event: PublishEvent) -> Promise<Void> {
		return Promise<Void> { seal in
			do {
				let data = try JSONEncoder().encode(event)
				httpClient.put(url: url, query: nil, headers: headers, body: data).done(on: DispatchQueue.global()) { response in
					guard (200...299).contains(response.status) else {
						seal.reject(ABSmartlyHTTPError(response.status, response.statusMessage))
						return
					}
					seal.fulfill(())
				}.catch(on: DispatchQueue.global()) { error in
					seal.reject(error)
				}
			} catch {
				seal.reject(error)
			}
		}
	}

	public func close() -> Promise<Void> {
		return httpClient.close()
	}

	// The configured names audiences and assignment-rule conditions target, captured at init so they
	// stay consistent with the HTTP metadata. Empty values are reported as `nil` so the context
	// leaves the key out of the evaluation map.
	public func getApplication() -> String? {
		return application.isEmpty ? nil : application
	}

	public func getEnvironment() -> String? {
		return environment.isEmpty ? nil : environment
	}
}
