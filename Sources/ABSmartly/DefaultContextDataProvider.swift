import Foundation
import PromiseKit

public class DefaultContextDataProvider: ContextDataProvider {
	private let client: Client

	init(client: Client) {
		self.client = client
	}

	public func getContextData() -> Promise<ContextData> {
		return client.getContextData()
	}
}
