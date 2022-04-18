import Foundation
import PromiseKit

public class DefaultContextEventHandler: ContextEventHandler {
	private let client: Client

	init(client: Client) {
		self.client = client
	}

	public func publish(event: PublishEvent) -> Promise<Void> {
		return client.publish(event: event)
	}
}
