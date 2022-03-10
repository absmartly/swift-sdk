import UIKit
import ABSmartly


class ViewController: UIViewController {
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
        let horizontalConstraint = (NSLayoutConstraint(item: button, attribute: .centerX, relatedBy: .equal, toItem: view, attribute: .centerX, multiplier: 1, constant: 0))
        let verticalConstraint = (NSLayoutConstraint(item: button, attribute: .centerY, relatedBy: .equal, toItem: view, attribute: .centerY, multiplier: 1, constant: 0))
        let widthConstraint = (NSLayoutConstraint(item: button, attribute: .width, relatedBy: .equal, toItem: nil, attribute: .notAnAttribute, multiplier: 1, constant: 300))
        let heightConstraint = (NSLayoutConstraint(item: button, attribute: .height, relatedBy: .equal, toItem: nil, attribute: .notAnAttribute, multiplier: 1, constant: 80))
        view.addConstraints([horizontalConstraint, verticalConstraint, widthConstraint, heightConstraint])

        let options = ClientOptions(apiKey: ProcessInfo.processInfo.environment["ABSMARTLY_API_KEY"] ?? "",
                                    application: ProcessInfo.processInfo.environment["ABSMARTLY_APPLICATION"] ?? "",
                                    endpoint: ProcessInfo.processInfo.environment["ABSMARTLY_ENDPOINT"] ?? "",
                                    environment: ProcessInfo.processInfo.environment["ABSMARTLY_ENVIRONMENT"] ?? "")
        
        let sdk = ABSmartlySDK(options)
        
        let contextConfig: ContextConfig = ContextConfig()
        contextConfig.setUnit(unitType: "anonymous_id", uid: UIDevice.current.identifierForVendor?.uuidString ?? "1234789")
        
        self.button.addTarget(self, action: #selector(click), for: .touchUpInside)

        context = sdk.createContext(config: contextConfig)
        context!.waitUntilReadyAsync { [weak self] context in
            do {
                guard let context = context else { return }
                
                let treatment = try context.getTreatment("show_popunder_on_leave")
                
                DispatchQueue.main.async {
                    if treatment == 0 {
                        self!.button.backgroundColor = .blue
                    } else {
                        self!.button.backgroundColor = .orange
                    }
                    self!.view.setNeedsDisplay()
                    self!.view.layer.displayIfNeeded()
                }
            } catch {
                print("Error" + error.localizedDescription)
            }
        }
    }
    
    @objc private func click() {
        do {
            try context!.track("payment", properties: ["amount":2235, "revenue": 235])
        } catch {
            print("Error" + error.localizedDescription)
        }
    }
}
