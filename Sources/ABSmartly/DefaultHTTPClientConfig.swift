import Foundation

public class DefaultHTTPClientConfig {
	public init() {
	}

	public var connectionResourceTimeout: TimeInterval = 3.0
	public var connectionRequestTimeout: TimeInterval = 3.0
	public var retryInterval: TimeInterval = 0.5
	public var retries: UInt = 3
}
