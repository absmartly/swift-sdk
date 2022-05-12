import Foundation
import PromiseKit

public final class ABSmartlySDK {
	private var client: Client?
	private let contextDataProvider: ContextDataProvider
	private let contextEventHandler: ContextEventHandler
	private let contextEventLogger: ContextEventLogger?
	private let variableParser: VariableParser
	private let scheduler: Scheduler

	public init(config: ABSmartlyConfig) throws {
		contextEventLogger = config.contextEventLogger
		variableParser = config.variableParser ?? DefaultVariableParser()
		scheduler = config.scheduler ?? DefaultScheduler()
		client = config.client

		if config.contextDataProvider == nil || config.contextEventHandler == nil {
			if client == nil {
				throw ABSmartlyError("Missing Client instance")
			}

			contextDataProvider = config.contextDataProvider ?? DefaultContextDataProvider(client: client!)
			contextEventHandler = config.contextEventHandler ?? DefaultContextEventHandler(client: client!)
		} else {
			contextDataProvider = config.contextDataProvider!
			contextEventHandler = config.contextEventHandler!
		}
	}

	public func createContextWithData(config: ContextConfig, contextData: ContextData) -> Context {
		return Context(
			config: config, clock: DefaultClock(), scheduler: scheduler, handler: contextEventHandler,
			provider: contextDataProvider, logger: contextEventLogger, parser: variableParser,
			matcher: AudienceMatcher(),
			promise: Promise<ContextData>.value(contextData))
	}

	public func createContext(config: ContextConfig) -> Context {
		return Context(
			config: config, clock: DefaultClock(), scheduler: scheduler, handler: contextEventHandler,
			provider: contextDataProvider, logger: contextEventLogger, parser: variableParser,
			matcher: AudienceMatcher(),
			promise: contextDataProvider.getContextData())
	}

	public func getContextData() -> Promise<ContextData> {
		return contextDataProvider.getContextData()
	}

	public func close() -> Promise<Void> {
		if client == nil {
			return Promise<Void>.value(())
		}

		return Promise<Void> { seal in
			if client != nil {
				client!.close().done {
					seal.fulfill(())
				}.catch { error in
					seal.reject(error)
				}
				client = nil
			} else {
				seal.fulfill(())
			}
		}
	}
}
