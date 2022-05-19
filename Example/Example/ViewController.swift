import ABSmartly
import Foundation
import OSLog
import UIKit

class ViewController: UIViewController {
	private let button = UIButton()
	private var sdk: ABSmartlySDK?
	private var context: Context!

	override func viewDidLoad() {
		super.viewDidLoad()

		view.backgroundColor = .white
		button.backgroundColor = .gray
		button.setTitle("Start", for: .normal)
		button.layer.cornerRadius = 40

		view.addSubview(button)

		button.translatesAutoresizingMaskIntoConstraints = false
		let horizontalConstraint =
			(NSLayoutConstraint(
				item: button, attribute: .centerX, relatedBy: .equal, toItem: view, attribute: .centerX, multiplier: 1,
				constant: 0))
		let verticalConstraint =
			(NSLayoutConstraint(
				item: button, attribute: .centerY, relatedBy: .equal, toItem: view, attribute: .centerY, multiplier: 1,
				constant: 0))
		let widthConstraint =
			(NSLayoutConstraint(
				item: button, attribute: .width, relatedBy: .equal, toItem: nil, attribute: .notAnAttribute,
				multiplier: 1, constant: 300))
		let heightConstraint =
			(NSLayoutConstraint(
				item: button, attribute: .height, relatedBy: .equal, toItem: nil, attribute: .notAnAttribute,
				multiplier: 1, constant: 80))
		view.addConstraints([horizontalConstraint, verticalConstraint, widthConstraint, heightConstraint])

		let clientConfig = ClientConfig(
			// The following environment variables should be changed in:
			// Product -> Scheme -> Edit Scheme -> Run -> Arguments
			apiKey: ProcessInfo.processInfo.environment["ABSMARTLY_API_KEY"] ?? "",
			application: ProcessInfo.processInfo.environment["ABSMARTLY_APPLICATION"] ?? "",
			endpoint: ProcessInfo.processInfo.environment["ABSMARTLY_ENDPOINT"] ?? "",
			environment: ProcessInfo.processInfo.environment["ABSMARTLY_ENVIRONMENT"] ?? "")

		do {
			let client = try DefaultClient(config: clientConfig)

			let sdkConfig = ABSmartlyConfig(client: client)
			sdk = try ABSmartlySDK(config: sdkConfig)
		} catch {
			print(error.localizedDescription)
			return
		}

		let contextConfig = ContextConfig()
		contextConfig.refreshInterval = 5
		contextConfig.setUnit(
			unitType: "anonymous_id", uid: UIDevice.current.identifierForVendor!.uuidString + "1")

		self.button.addTarget(self, action: #selector(click), for: .touchUpInside)

		context = sdk!.createContext(config: contextConfig)
		_ = context.waitUntilReady().done { context in
			let treatment = context.getTreatment("exp_with_variables")

			DispatchQueue.main.async {
				if treatment == 0 {
					self.button.backgroundColor = .blue
				} else {
					self.button.backgroundColor = .orange
				}

				self.view.setNeedsDisplay()
				self.view.layer.displayIfNeeded()
			}
		}
	}

	@objc private func click() {
		context.track("payment", properties: ["amount": 2235, "revenue": 235])
	}
}
