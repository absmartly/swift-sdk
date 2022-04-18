import Foundation

public class ABSmartlyConfig {
	var scheduler: Scheduler?
	var contextDataProvider: ContextDataProvider?
	var contextEventHandler: ContextEventHandler?
	var variableParser: VariableParser?
	var client: Client?

	public init() {
	}

	public convenience init(client: Client) {
		self.init(
			contextDataProvider: nil, contextEventHandler: nil, variableParser: nil, scheduler: nil, client: client)
	}

	public init(
		contextDataProvider: ContextDataProvider?, contextEventHandler: ContextEventHandler?,
		variableParser: VariableParser?, scheduler: Scheduler?, client: Client?
	) {
		self.scheduler = scheduler
		self.contextDataProvider = contextDataProvider
		self.contextEventHandler = contextEventHandler
		self.variableParser = variableParser
		self.client = client
	}
}
