import Foundation

public class ABSmartlyConfig {
	var scheduler: Scheduler?
	var contextDataProvider: ContextDataProvider?
	var contextEventHandler: ContextEventHandler?
	var contextEventLogger: ContextEventLogger?
	var variableParser: VariableParser?
	var client: Client?

	public init() {
	}

	public convenience init(client: Client) {
		print("Hello, world!")
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
