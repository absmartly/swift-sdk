import Foundation
import PromiseKit

public final class DefaultClient: Client {
	private let config: ClientConfig
	private let httpClient: HTTPClient
	private let url: String
	private let getQuery: [String: String]
	private let putHeaders: [String: String]

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

		url = config.endpoint + "/context"
		getQuery = ["application": config.application, "environment": config.environment]
		putHeaders = [
			"Content-Type": "application/json; charset=utf-8",
			"X-Agent": "absmartly-swift-sdk",
			"X-API-Key": config.apiKey,
			"X-Environment": config.environment,
			"X-Application": config.application,
			"X-Application-Version": "0",
		]
	}

	public func getContextData() -> Promise<ContextData> {
		return Promise<ContextData> { seal in
			httpClient.get(url: url, query: getQuery, headers: nil).done { response in
				do {
					let result = try JSONDecoder().decode(ContextData.self, from: response.content)
					seal.fulfill(result)
				} catch {
					seal.reject(error)
				}
			}.catch { error in
				seal.reject(error)
			}
		}
	}

	public func publish(event: PublishEvent) -> Promise<Void> {
		return Promise<Void> { seal in
			do {
				let data = try JSONEncoder().encode(event)
				httpClient.put(url: url, query: nil, headers: putHeaders, body: data).done { response in
					seal.fulfill(())
				}.catch { error in
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
}
