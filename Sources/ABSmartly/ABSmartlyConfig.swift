import Foundation

public class ABSmartlyConfig {
	var scheduler: Scheduler?
	var contextDataProvider: ContextDataProvider?
	var contextEventHandler: ContextEventHandler?
	var contextEventLogger: ContextEventLogger?
	var variableParser: VariableParser?
	var client: Client?
	var resilienceConfig: ResilienceConfig?

	public init() {
	}

	public convenience init(client: Client) {
		print("Hello, world!")
		self.init(
			contextDataProvider: nil, contextEventHandler: nil, contextEventLogger: nil, variableParser: nil,
			scheduler: nil, client: client, resilienceConfig: nil)
	}

	public convenience init(client: Client, resilienceConfig: ResilienceConfig) {
		print("Hello, world!")
		self.init(
			contextDataProvider: nil, contextEventHandler: nil, contextEventLogger: nil, variableParser: nil,
			scheduler: nil, client: client, resilienceConfig: resilienceConfig)
	}

	public init(
		contextDataProvider: ContextDataProvider?, contextEventHandler: ContextEventHandler?,
		contextEventLogger: ContextEventLogger?,
		variableParser: VariableParser?, scheduler: Scheduler?, client: Client?, resilienceConfig: ResilienceConfig?
	) {
		self.scheduler = scheduler
		self.contextDataProvider = contextDataProvider
		self.contextEventHandler = contextEventHandler
		self.contextEventLogger = contextEventLogger
		self.variableParser = variableParser
		self.client = client
		self.resilienceConfig = resilienceConfig
	}
}
