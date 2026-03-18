import Foundation
import PromiseKit

public final class ABsmartlySDK {
	private var client: Client?
	private let contextDataProvider: ContextDataProvider
	private let contextEventHandler: ContextPublisher
	private let contextEventLogger: ContextEventLogger?
	private let variableParser: VariableParser
	private let scheduler: Scheduler

	public init(config: ABsmartlyConfig) throws {
		contextEventLogger = config.contextEventLogger
		variableParser = config.variableParser ?? DefaultVariableParser()
		scheduler = config.scheduler ?? DefaultScheduler()
		client = config.client

		if config.contextDataProvider == nil || config.contextPublisher == nil {
			guard let client = client else {
				throw ABSmartlyError("Missing Client instance")
			}

			contextDataProvider = config.contextDataProvider ?? DefaultContextDataProvider(client: client)
			contextEventHandler = config.contextPublisher ?? DefaultContextPublisher(client: client)
		} else {
			guard let provider = config.contextDataProvider, let handler = config.contextPublisher else {
				throw ABSmartlyError("Missing contextDataProvider or contextPublisher")
			}
			contextDataProvider = provider
			contextEventHandler = handler
		}
	}

	public convenience init(
		endpoint: String,
		apiKey: String,
		application: String,
		environment: String,
		applicationVersion: String = "0",
		timeout: TimeInterval = 3.0,
		retries: UInt = 5,
		contextEventLogger: ContextEventLogger? = nil,
		contextDataProvider: ContextDataProvider? = nil,
		contextEventHandler: ContextEventHandler? = nil,
		variableParser: VariableParser? = nil,
		scheduler: Scheduler? = nil
	) throws {
		if endpoint.isEmpty {
			throw ABSmartlyError("Missing Endpoint configuration")
		}

		if apiKey.isEmpty {
			throw ABSmartlyError("Missing APIKey configuration")
		}

		if application.isEmpty {
			throw ABSmartlyError("Missing Application configuration")
		}

		if environment.isEmpty {
			throw ABSmartlyError("Missing Environment configuration")
		}

		let clientConfig = ClientConfig(
			apiKey: apiKey,
			application: application,
			endpoint: endpoint,
			environment: environment,
			applicationVersion: applicationVersion
		)

		let httpClientConfig = DefaultHTTPClientConfig()
		httpClientConfig.connectionResourceTimeout = timeout
		httpClientConfig.connectionRequestTimeout = timeout
		httpClientConfig.retries = retries

		let client = try DefaultClient(
			config: clientConfig,
			httpClient: DefaultHTTPClient(config: httpClientConfig)
		)

		let sdkConfig = ABsmartlyConfig(
			contextDataProvider: contextDataProvider,
			contextPublisher: contextEventHandler,
			contextEventLogger: contextEventLogger,
			variableParser: variableParser,
			scheduler: scheduler,
			client: client
		)

		try self.init(config: sdkConfig)
	}

	public func createContextWithData(config: ContextConfig, contextData: ContextData) -> Context {
		return Context(
			config: config, clock: DefaultClock(), scheduler: scheduler, handler: contextEventHandler,
			provider: contextDataProvider, logger: config.eventLogger, parser: variableParser,
			matcher: AudienceMatcher(),
			promise: Promise<ContextData>.value(contextData))
	}

	public func createContext(config: ContextConfig) -> Context {
		return Context(
			config: config, clock: DefaultClock(), scheduler: scheduler, handler: contextEventHandler,
			provider: contextDataProvider, logger: config.eventLogger, parser: variableParser,
			matcher: AudienceMatcher(),
			promise: contextDataProvider.getContextData())
	}

	public func getContextData() -> Promise<ContextData> {
		return contextDataProvider.getContextData()
	}

	public func close() -> Promise<Void> {
		guard let clientToClose = client else {
			return Promise<Void>.value(())
		}
		client = nil
		return clientToClose.close()
	}
}

@available(*, deprecated, message: "Use ABsmartlySDK instead")
public typealias AbsmartlySDK = ABsmartlySDK

@available(*, deprecated, message: "Use ABsmartlySDK instead")
public typealias ABSmartlySDK = ABsmartlySDK
