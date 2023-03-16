import Foundation
import PromiseKit
import CircuitBreaker

public class ResilientContextEventHandler: ContextEventHandler {
	private let client: Client
	private let localCache: LocalCache
	private let circuitBreaker: CircuitBreakerHelper

	public init(client: Client, resilienceConfig: ResilienceConfig) {
		self.client = client
		self.localCache = resilienceConfig.localCache
		self.circuitBreaker = CircuitBreakerHelper(resilienceConfig: resilienceConfig)
	}

	public func publish(event: PublishEvent) -> Promise<Void> {
		let (fallbackPromise, fallBackResolver) = Promise<BreakerError?>.pending()

		fallbackPromise.done { err in
			if(err != nil){
				self.localCache.writeEvent(event: event)
			}
		}

		return circuitBreaker.decorate(promise: client.publish(event: event), fallBackResolver: fallBackResolver)
	}
}
