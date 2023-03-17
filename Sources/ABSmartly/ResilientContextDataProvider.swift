import Foundation
import PromiseKit

public class ResilientContextDataProvider: ContextDataProvider {
	private let client: Client
	private let localCache: LocalCache

	public init(client: Client, localCache: LocalCache) {
		self.client = client
		self.localCache = localCache
	}

	public func getContextData() -> Promise<ContextData> {
		let (promiseReturn, resolver) = Promise<ContextData>.pending()
		var promise = client.getContextData()

		promise.done { contextData in
			self.localCache.writeContextData(contextData: contextData)
			resolver.fulfill(contextData)
		}.catch { error in
			var contextData = self.localCache.getContextData()
			if contextData != nil {
				resolver.fulfill(contextData!)
			} else {
				resolver.reject(error)
			}
		}
		return promiseReturn
	}
}
