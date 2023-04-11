import Foundation

public class ABSmartlyConfig {
	private(set) var scheduler: Scheduler?
	private(set) var contextDataProvider: ContextDataProvider?
	private(set) var contextEventHandler: ContextEventHandler?
	private(set) var contextEventLogger: ContextEventLogger?
	private(set) var variableParser: VariableParser?
	private(set) var client: Client?

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
