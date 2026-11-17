import ABsmartly
import Foundation
import UIKit

@MainActor
final class ViewController: UIViewController {
	private let button = UIButton()
	private var context: Context?

	override func viewDidLoad() {
		super.viewDidLoad()

		view.backgroundColor = .white
		button.backgroundColor = .gray
		button.setTitle("Start", for: .normal)
		button.layer.cornerRadius = 40

		view.addSubview(button)

		button.translatesAutoresizingMaskIntoConstraints = false
		NSLayoutConstraint.activate([
			button.centerXAnchor.constraint(equalTo: view.centerXAnchor),
			button.centerYAnchor.constraint(equalTo: view.centerYAnchor),
			button.widthAnchor.constraint(equalToConstant: 300),
			button.heightAnchor.constraint(equalToConstant: 80),
		])
		button.addTarget(self, action: #selector(click), for: .touchUpInside)

		// The following environment variables should be changed in:
		// Product -> Scheme -> Edit Scheme -> Run -> Arguments
		let environment = ProcessInfo.processInfo.environment
		let client: ABsmartlyClient
		do {
			client = try ABsmartlyClient(
				endpoint: URL(string: environment["ABSMARTLY_ENDPOINT"] ?? "") ?? URL(fileURLWithPath: "/"),
				apiKey: environment["ABSMARTLY_API_KEY"] ?? "",
				application: environment["ABSMARTLY_APPLICATION"] ?? "",
				environment: .init(rawValue: environment["ABSMARTLY_ENVIRONMENT"] ?? ""))
		} catch {
			print(error.localizedDescription)
			return
		}

		let deviceID = UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString
		Task {
			do {
				let context = try await client.context(
					units: ["anonymous_id": deviceID + "1"],
					options: Context.Options(refreshInterval: 5))
				self.context = context
				let treatment = context.treatment(for: "exp_with_variables")
				button.backgroundColor = treatment == 0 ? .blue : .orange
			} catch {
				print(error.localizedDescription)
			}
		}
	}

	@objc private func click() {
		context?.track("payment", properties: ["amount": 2235, "revenue": 235])
	}
}
