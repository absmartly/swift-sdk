import Foundation

public class ABSmartlyConfig {
	public var scheduler: Scheduler?
	public var contextDataProvider: ContextDataProvider?
	public var contextEventHandler: ContextEventHandler?
	public var contextEventLogger: ContextEventLogger?
	public var variableParser: VariableParser?
	public var client: Client?

	/// The same value as `contextEventHandler`, under the name other A/B Smartly SDKs use.
	public var contextPublisher: ContextPublisher? {
		get { contextEventHandler }
		set { contextEventHandler = newValue }
	}

	public init() {
	}

	public convenience init(client: Client) {
		self.init(
			contextDataProvider: nil, contextEventHandler: nil, contextEventLogger: nil, variableParser: nil,
			scheduler: nil, client: client)
	}

	public init(
		contextDataProvider: ContextDataProvider?, contextEventHandler: ContextEventHandler?,
		contextEventLogger: ContextEventLogger?,
		variableParser: VariableParser?, scheduler: Scheduler?, client: Client?
	) {
		self.scheduler = scheduler
		self.contextDataProvider = contextDataProvider
		self.contextEventHandler = contextEventHandler
		self.contextEventLogger = contextEventLogger
		self.variableParser = variableParser
		self.client = client
	}
}

extension ABSmartlyConfig {
	/// `init(contextDataProvider:contextEventHandler:...)` under the name other A/B Smartly SDKs use.
	public convenience init(
		contextDataProvider: ContextDataProvider?, contextPublisher: ContextPublisher?,
		contextEventLogger: ContextEventLogger?,
		variableParser: VariableParser?, scheduler: Scheduler?, client: Client?
	) {
		self.init(
			contextDataProvider: contextDataProvider, contextEventHandler: contextPublisher,
			contextEventLogger: contextEventLogger, variableParser: variableParser,
			scheduler: scheduler, client: client)
	}
}

/// `ABSmartlyConfig` under the spelling other A/B Smartly SDKs use.
public typealias ABsmartlyConfig = ABSmartlyConfig

@available(*, deprecated, message: "Use ABSmartlyConfig instead")
public typealias AbsmartlyConfig = ABSmartlyConfig
