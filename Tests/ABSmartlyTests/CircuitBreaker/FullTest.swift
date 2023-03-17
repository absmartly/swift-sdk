import CircuitBreaker
import Foundation
import PromiseKit
import XCTest

@testable import ABSmartly

final class FullTest: XCTestCase {
	private var sdk: ABSmartlySDK!
	private var context: Context!
	func testCircuitBreaker() async {
		let expectation = XCTestExpectation()
		setupSDK()
		for (index) in 1...1 {
			print(index)
			usleep(useconds_t(50 * 1000))
			var promise = Promise<Void> { seal in
				context.track("payment", properties: ["amount": 2235, "revenue": 235])
				seal.fulfill(())
			}
			promise.done { data in
				print(data)
			}
		}
		wait(for: [expectation], timeout: 200.0)
	}

	func setupSDK() {
		do {

			let clientConfig = ClientConfig(
				// The following environment variables should be changed in:
				// Product -> Scheme -> Edit Scheme -> Run -> Arguments
				apiKey: ProcessInfo.processInfo.environment["ABSMARTLY_API_KEY"]
					?? "API_KEY",
				application: ProcessInfo.processInfo.environment["ABSMARTLY_APPLICATION"] ?? "web",
				endpoint: ProcessInfo.processInfo.environment["ABSMARTLY_ENDPOINT"] ?? "ENV_URL",
				environment: ProcessInfo.processInfo.environment["ABSMARTLY_ENVIRONMENT"] ?? "prod")

			let client = try DefaultClient(config: clientConfig)

			let localCache: LocalCache = SqlliteCache()
			let resilienceConfig = ResilienceConfig(localCache: localCache)
			resilienceConfig.backoffPeriodInMilliseconds = 3000
			let sdkConfig = ABSmartlyConfig(client: client, resilienceConfig: resilienceConfig)
			//let sdkConfig = ABSmartlyConfig(client: client)
			sdk = try ABSmartlySDK(config: sdkConfig)
			let contextConfig = ContextConfig()
			contextConfig.refreshInterval = 5
			contextConfig.setUnit(
				unitType: "user_id", uid: "123456")
			context = sdk.createContext(config: contextConfig)
			_ = context.waitUntilReady().done { context in
				let treatment = context.getTreatment("Experimentationless")

				DispatchQueue.main.async {
					if treatment == 0 {
						//self. = .blue
					} else {
						//self.backgroundColor = .orange
					}

				}
			}
		} catch {
			print(error.localizedDescription)
		}
	}

}
