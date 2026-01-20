import Foundation

public class ABSmartlyConfig {
	public var scheduler: Scheduler?
	public var contextDataProvider: ContextDataProvider?
	public var contextEventHandler: ContextEventHandler?
	public var contextEventLogger: ContextEventLogger?
	public var variableParser: VariableParser?
	public var client: Client?

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
