import Foundation
import XCTest

@testable import ABSmartly

final class DefaultHTTPClientTest: XCTestCase {
	func testCreatable() throws {
		let config = DefaultHTTPClientConfig()
		config.retries = 4
		let httpClient = DefaultHTTPClient(config: config)
		_ = httpClient.close()
	}
}
