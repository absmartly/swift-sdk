import Foundation

public class ResilienceConfig {
	public var failureRateThreshold: Int = 20
	public var backoffPeriodInMilliseconds: Int = 30000
	public var timeoutInMilliseconds: Int = 30000
	public var localCache: LocalCache

	public init(localCache: LocalCache) {
		self.localCache = localCache;
	}

	public init(
			failureRateThreshold: Int, backoffPeriodInMilliseconds: Int, timeoutInMilliseconds: Int, localCache: LocalCache
	) {
		self.failureRateThreshold = failureRateThreshold
		self.backoffPeriodInMilliseconds = backoffPeriodInMilliseconds
		self.timeoutInMilliseconds = timeoutInMilliseconds
		self.localCache = localCache
	}

	public convenience init(from data: Data) {
		let dict = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: String]
		self.init(from: dict ?? [:])
	}

	public convenience init(from dict: [String: String]) {
		var localCacheImpl: LocalCache = NSClassFromString(dict["localCacheImplClass"] ?? "SqlliteCache") as! LocalCache


		if let localCacheImplClass = localCacheImpl as? LocalCache.Type {
			self.init(
					failureRateThreshold: dict["failureRateThreshold"] as!Int,
					backoffPeriodInMilliseconds: dict["backoffPeriodInMilliseconds"] as!Int,
					timeoutInMilliseconds: dict["timeoutInMilliseconds"] as!Int,
					localCache: localCacheImpl)
		} else {
			fatalError("LocalCache is not a LocalCache subtype")
		}

	}
}
