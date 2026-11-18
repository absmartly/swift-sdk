// Every ```swift block in README.md, compiled as part of the test target. Generated from the
// README by scripts/readme-snippets.py; ReadmeSnippetsTest fails when a README block is missing here, so keep them in sync.
// Blocks that need UIKit, SwiftUI or AppKit only compile where those frameworks exist.
import ABSmartly
import ABSmartlyAsync
import Foundation
import PromiseKit
#if canImport(UIKit)
import UIKit
#endif
#if canImport(SwiftUI)
import SwiftUI
#endif
#if canImport(AppKit)
import Cocoa
#endif

// README block 1
@available(iOS 13, macOS 10.15, tvOS 13, watchOS 6, *)
func readmeSnippet1(sdk: ABSmartlySDK, context: Context, config: ContextConfig, contextData: ContextData) async throws {
	let sdk: ABSmartlySDK
	do {
	    sdk = try ABSmartlySDK(
	        endpoint: "https://your-company.absmartly.io/v1",
	        apiKey: "YOUR-API-KEY",
	        application: "website",
	        environment: "production"
	    )
	} catch {
	    print("Failed to initialize ABSmartly SDK: \(error.localizedDescription)")
	    return
	}
	_ = sdk
}

// README block 2
@available(iOS 13, macOS 10.15, tvOS 13, watchOS 6, *)
func readmeSnippet2(sdk: ABSmartlySDK, context: Context, config: ContextConfig, contextData: ContextData) async throws {
	let sdk = try ABSmartlySDK(
	    endpoint: "https://your-company.absmartly.io/v1",
	    apiKey: "YOUR-API-KEY",
	    application: "website",
	    environment: "production",
	    applicationVersion: "10000",   // An integer; sent as "0" otherwise
	    timeout: 5.0,           // Default: 3.0 seconds
	    retries: 5              // Default: 3
	)
	_ = sdk
}

// README block 3
@available(iOS 13, macOS 10.15, tvOS 13, watchOS 6, *)
func readmeSnippet3(sdk: ABSmartlySDK, context: Context, config: ContextConfig, contextData: ContextData) async throws {
	let clientConfig = ClientConfig(
	    apiKey: "YOUR-API-KEY",
	    application: "website",
	    endpoint: "https://your-company.absmartly.io/v1",
	    environment: "production"
	)

	let client = try DefaultClient(config: clientConfig)
	let sdkConfig = ABSmartlyConfig(client: client)
	let sdk = try ABSmartlySDK(config: sdkConfig)
	_ = clientConfig
	_ = client
	_ = sdkConfig
	_ = sdk
}

// README block 4
@available(iOS 13, macOS 10.15, tvOS 13, watchOS 6, *)
func readmeSnippet4(sdk: ABSmartlySDK, context: Context, config: ContextConfig, contextData: ContextData) async throws {
	let contextConfig = ContextConfig()
	contextConfig.setUnit(unitType: "session_id", uid: "5ebf06d8cb5d8137290c4abb64155584fbdb64d8")

	let context = sdk.createContext(config: contextConfig)
	_ = context.waitUntilReady().done { context in
	    print("ABSmartly Context ready!")
	}
	_ = contextConfig
	_ = context
}

// README block 5
@available(iOS 13, macOS 10.15, tvOS 13, watchOS 6, *)
func readmeSnippet5(sdk: ABSmartlySDK, context: Context, config: ContextConfig, contextData: ContextData) async throws {

	let context = sdk.createContext(config: config)
	try await context.waitUntilReady()
	try await context.publish()
	try await context.close()
	_ = context
}

// README block 6

@available(iOS 13, macOS 10.15, tvOS 13, watchOS 6, *)
@MainActor
final class ExperimentsModel {
    let sdk: ABSmartlySDK
    var context: Context?
    var showNewCheckout = false

    init(sdk: ABSmartlySDK) {
        self.sdk = sdk
    }

    func load(deviceID: String) async {
        let config = ContextConfig()
        config.setUnit(unitType: "device_id", uid: deviceID)

        let context = sdk.createContext(config: config)
        do {
            try await context.waitUntilReady()
        } catch {
            print("Context failed to initialize: \(error.localizedDescription)")
        }
        showNewCheckout = context.getTreatment("exp_new_checkout") == 1
        self.context = context
    }
}

// README block 7
@available(iOS 13, macOS 10.15, tvOS 13, watchOS 6, *)
func readmeSnippet7(sdk: ABSmartlySDK, context: Context, config: ContextConfig, contextData: ContextData) async throws {
	let contextConfig = ContextConfig()
	contextConfig.setUnit(unitType: "session_id", uid: "5ebf06d8cb5d8137290c4abb64155584fbdb64d8")

	// contextData: a ContextData received from your server
	let context = sdk.createContextWithData(config: contextConfig, contextData: contextData)
	_ = contextConfig
	_ = context
}

// README block 8
@available(iOS 13, macOS 10.15, tvOS 13, watchOS 6, *)
func readmeSnippet8(sdk: ABSmartlySDK, context: Context, config: ContextConfig, contextData: ContextData) async throws {
	let contextConfig = ContextConfig()
	contextConfig.setUnit(unitType: "session_id", uid: "5ebf06d8cb5d8137290c4abb64155584fbdb64d8")
	contextConfig.refreshInterval = 4 * 3600 // every 4 hours (in seconds)
	_ = contextConfig
}

// README block 9
@available(iOS 13, macOS 10.15, tvOS 13, watchOS 6, *)
func readmeSnippet9(sdk: ABSmartlySDK, context: Context, config: ContextConfig, contextData: ContextData) async throws {
	context.refresh().done {
	    print("Context refreshed with latest experiment data")
	}.catch { error in
	    print("Refresh failed: \(error.localizedDescription)")
	}

	// or, with `import ABSmartlyAsync`
	try await context.refresh()
}

// README block 10
@available(iOS 13, macOS 10.15, tvOS 13, watchOS 6, *)
func readmeSnippet10(sdk: ABSmartlySDK, context: Context, config: ContextConfig, contextData: ContextData) async throws {
	context.setUnit(unitType: "db_user_id", uid: "1000013")
	context.setUnits([
	    "db_user_id": "1000013"
	])
}

// README block 11
@available(iOS 13, macOS 10.15, tvOS 13, watchOS 6, *)
func readmeSnippet11(sdk: ABSmartlySDK, context: Context, config: ContextConfig, contextData: ContextData) async throws {
	let treatment = context.getTreatment("exp_test_experiment")
	if treatment == 0 {
	    // user is in control group (variant 0)
	} else {
	    // user is in treatment group
	}
	_ = treatment
}

// README block 12
@available(iOS 13, macOS 10.15, tvOS 13, watchOS 6, *)
func readmeSnippet12(sdk: ABSmartlySDK, context: Context, config: ContextConfig, contextData: ContextData) async throws {
	let defaultButtonColor: JSON = "red"
	let buttonColor = context.getVariableValue("button.color", defaultValue: defaultButtonColor)?.stringValue
	_ = defaultButtonColor
	_ = buttonColor
}

// README block 13
@available(iOS 13, macOS 10.15, tvOS 13, watchOS 6, *)
func readmeSnippet13(sdk: ABSmartlySDK, context: Context, config: ContextConfig, contextData: ContextData) async throws {
	let treatment = context.peekTreatment("exp_test_experiment")
	if treatment == 0 {
	    // user is in control group (variant 0)
	} else {
	    // user is in treatment group
	}
	_ = treatment
}

// README block 14
@available(iOS 13, macOS 10.15, tvOS 13, watchOS 6, *)
func readmeSnippet14(sdk: ABSmartlySDK, context: Context, config: ContextConfig, contextData: ContextData) async throws {
	let color = context.peekVariableValue("colorGComponent", defaultValue: 255)
	_ = color
}

// README block 15
@available(iOS 13, macOS 10.15, tvOS 13, watchOS 6, *)
func readmeSnippet15(sdk: ABSmartlySDK, context: Context, config: ContextConfig, contextData: ContextData) async throws {
	context.setOverride(experimentName: "exp_test_experiment", variant: 1)  // force variant 1 of treatment
	context.setOverrides(["exp_test_experiment": 1, "exp_another_experiment": 0])
}

// README block 16
#if canImport(UIKit) && !os(watchOS)
@available(iOS 13, macOS 10.15, tvOS 13, watchOS 6, *)
func readmeSnippet16(sdk: ABSmartlySDK, context: Context, config: ContextConfig, contextData: ContextData) async throws {
	context.setAttribute(name: "device", value: UIDevice.current.model)
	context.setAttributes([
	    "customer_age": "new_customer",
	    "screen": "product"
	])
}
#endif

// README block 17
@available(iOS 13, macOS 10.15, tvOS 13, watchOS 6, *)
func readmeSnippet17(sdk: ABSmartlySDK, context: Context, config: ContextConfig, contextData: ContextData) async throws {
	context.track("payment", properties: [
	    "item_count": 1,
	    "total_amount": 1999.99
	])
}

// README block 18
@available(iOS 13, macOS 10.15, tvOS 13, watchOS 6, *)
func readmeSnippet18(sdk: ABSmartlySDK, context: Context, config: ContextConfig, contextData: ContextData) async throws {
	context.publish().done {
	    print("All pending events published")
	}.catch { error in
	    print("Publish failed: \(error.localizedDescription)")
	}

	// or, with `import ABSmartlyAsync`
	try await context.publish()
}

// README block 19
@available(iOS 13, macOS 10.15, tvOS 13, watchOS 6, *)
func readmeSnippet19(sdk: ABSmartlySDK, context: Context, config: ContextConfig, contextData: ContextData) async throws {
	context.close().done {
	    print("Context closed")
	}.catch { error in
	    print("Close failed: \(error.localizedDescription)")
	}

	// or, with `import ABSmartlyAsync`
	try await context.close()
}

// README block 20
public class CustomEventLogger: ContextEventLogger {
    public func handleEvent(context: Context, event: ContextEventLoggerEvent) {
        switch event {
        case let .exposure(exposure):
            print("Exposed to experiment: \(exposure.name)")
        case let .goal(goal):
            print("Goal tracked: \(goal.name)")
        case let .error(error):
            print("Error: \(error.localizedDescription)")
        case .publish:
            print("Events published")
        case .ready:
            print("Context ready")
        case .refresh:
            print("Context refreshed")
        case .close:
            print("Context closed")
        }
    }
}

// README block 21
@available(iOS 13, macOS 10.15, tvOS 13, watchOS 6, *)
func readmeSnippet21(sdk: ABSmartlySDK, context: Context, config: ContextConfig, contextData: ContextData) async throws {
	// For all contexts, during SDK initialization
	let sdk = try ABSmartlySDK(
	    endpoint: "https://your-company.absmartly.io/v1",
	    apiKey: "YOUR-API-KEY",
	    application: "website",
	    environment: "production",
	    contextEventLogger: CustomEventLogger()
	)

	// OR, alternatively, during a particular context initialization
	let contextConfig = ContextConfig()
	contextConfig.eventLogger = CustomEventLogger()
	_ = sdk
	_ = contextConfig
}

// README block 22
#if canImport(SwiftUI) && canImport(UIKit) && !os(watchOS)
// ABSmartlyService.swift

@available(iOS 13, tvOS 13, *)
class ABSmartlyService: ObservableObject {
    static let shared = ABSmartlyService()

    private let sdk: ABSmartlySDK

    private init() {
        sdk = try! ABSmartlySDK(
            endpoint: "https://your-company.absmartly.io/v1",
            apiKey: ProcessInfo.processInfo.environment["ABSMARTLY_API_KEY"] ?? "",
            application: "ios-app",
            environment: "production"
        )
    }

    func createContext(deviceId: String) async throws -> Context {
        let contextConfig = ContextConfig()
        contextConfig.setUnit(unitType: "device_id", uid: deviceId)

        let context = sdk.createContext(config: contextConfig)
        try await context.waitUntilReady()

        return context
    }
}

// ContentView.swift

@available(iOS 15, tvOS 15, *)
struct ContentView: View {
    @StateObject private var absmartly = ABSmartlyService.shared
    @State private var context: Context?
    @State private var buttonColor: Color = .blue

    var body: some View {
        VStack {
            Button("Click Me") {
                context?.track("button_clicked")
            }
            .foregroundColor(buttonColor)
            .padding()
        }
        .task {
            do {
                let deviceId = UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString
                let loaded = try await absmartly.createContext(deviceId: deviceId)
                // The load keeps going after the view disappears (cancellation does not stop it),
                // so close a context that arrives too late instead of keeping it.
                if Task.isCancelled {
                    try? await loaded.close()
                    return
                }
                context = loaded
                // Map the experiment's value to a system colour; anything else keeps the default.
                switch loaded.getVariableValue("button.color", defaultValue: "blue")?.stringValue {
                case "red": buttonColor = .red
                case "green": buttonColor = .green
                default: buttonColor = .blue
                }
            } catch {
                print("Failed to initialize ABSmartly: \(error)")
            }
        }
        .onDisappear {
            _ = context?.close()
        }
    }
}
#endif

// README block 23
#if canImport(UIKit) && !os(watchOS)
// ExperimentViewController.swift

class ExperimentViewController: UIViewController {
    private var sdk: ABSmartlySDK!
    private var context: Context?

    override func viewDidLoad() {
        super.viewDidLoad()

        do {
            sdk = try ABSmartlySDK(
                endpoint: "https://your-company.absmartly.io/v1",
                apiKey: "YOUR-API-KEY",
                application: "ios-app",
                environment: "production"
            )
        } catch {
            print("Failed to initialize SDK: \(error)")
            return
        }

        let contextConfig = ContextConfig()
        contextConfig.setUnit(unitType: "device_id", uid: UIDevice.current.identifierForVendor?.uuidString ?? "")

        context = sdk.createContext(config: contextConfig)
        context?.waitUntilReady().done { [weak self] ctx in
            self?.setupExperiment(context: ctx)
        }.catch { error in
            print("Context failed: \(error)")
        }
    }

    private func setupExperiment(context: Context) {
        let treatment = context.getTreatment("button_experiment")
        let buttonTitle = context.getVariableValue("button.title", defaultValue: "Click Me")

        if treatment == 1 {
            let backgroundColor = context.getVariableValue("button.background", defaultValue: "#007AFF")
        }
    }

    deinit {
        _ = context?.close()
    }
}
#endif

// README block 24
#if canImport(AppKit)
// AppDelegate.swift

class AppDelegate: NSObject, NSApplicationDelegate {
    private var sdk: ABSmartlySDK!
    private var context: Context?

    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            sdk = try ABSmartlySDK(
                endpoint: "https://your-company.absmartly.io/v1",
                apiKey: "YOUR-API-KEY",
                application: "macos-app",
                environment: "production"
            )
        } catch {
            print("Failed to initialize SDK: \(error)")
            return
        }

        let contextConfig = ContextConfig()
        let machineId = getMachineIdentifier()
        contextConfig.setUnit(unitType: "machine_id", uid: machineId)

        context = sdk.createContext(config: contextConfig)
        context?.waitUntilReady().done { [weak self] ctx in
            self?.runExperiment(context: ctx)
        }.catch { error in
            print("Context failed: \(error)")
        }
    }

    private func getMachineIdentifier() -> String {
        // A random ID kept for this installation.
        if let id = UserDefaults.standard.string(forKey: "absmartly_machine_id") {
            return id
        }
        let id = UUID().uuidString
        UserDefaults.standard.set(id, forKey: "absmartly_machine_id")
        return id
    }

    private func runExperiment(context: Context) {
        let featureEnabled = context.getTreatment("new_feature") == 1

        if featureEnabled {
            let featureConfig = context.getVariableValue("feature.config", defaultValue: [:])
        }

        context.track("app_launched")
    }

    func applicationWillTerminate(_ notification: Notification) {
        _ = context?.close()
    }
}
#endif

// README block 25

@available(iOS 13, macOS 10.15, tvOS 13, watchOS 6, *)
class ExperimentManager {
    private let sdk: ABSmartlySDK
    private var loadTask: Task<Void, Never>?

    init(sdk: ABSmartlySDK) {
        self.sdk = sdk
    }

    func loadExperiment(deviceId: String) {
        loadTask?.cancel()  // a newer load replaces an unfinished one
        loadTask = Task {
            let contextConfig = ContextConfig()
            contextConfig.setUnit(unitType: "device_id", uid: deviceId)

            let context = sdk.createContext(config: contextConfig)
            do {
                try await context.waitUntilReady()
            } catch {
                print("Context failed: \(error)")
                return
            }
            if Task.isCancelled {
                try? await context.close()  // the screen went away while loading
                return
            }
            handleExperiment(context: context)
        }
    }

    func cancelLoad() {
        loadTask?.cancel()
    }

    private func handleExperiment(context: Context) {
        let treatment = context.getTreatment("experiment_name")
        print("treatment \(treatment)")
    }
}

// README block 26
@available(iOS 13, macOS 10.15, tvOS 13, watchOS 6, *)
func readmeSnippet26(sdk: ABSmartlySDK, context: Context, config: ContextConfig, contextData: ContextData) async throws {
	let manager = ExperimentManager(sdk: sdk)
	manager.loadExperiment(deviceId: "device-123")
	// later, e.g. when the screen goes away:
	manager.cancelLoad()
	_ = manager
}

// README block 27
@available(iOS 13, macOS 10.15, tvOS 13, watchOS 6, *)
func readmeSnippet27(sdk: ABSmartlySDK, context: Context, config: ContextConfig, contextData: ContextData) async throws {
	let sdk = try ABSmartlySDK(
	    endpoint: "https://your-company.absmartly.io/v1",
	    apiKey: "YOUR-API-KEY",
	    application: "ios-app",
	    environment: "production",
	    timeout: 10.0  // 10 seconds instead of default 3 seconds
	)
	_ = sdk
}

// README block 28
@available(iOS 13, macOS 10.15, tvOS 13, watchOS 6, *)
func readmeSnippet28(sdk: ABSmartlySDK, context: Context, config: ContextConfig, contextData: ContextData) async throws {
	let httpClientConfig = DefaultHTTPClientConfig()
	httpClientConfig.connectionResourceTimeout = 10.0
	httpClientConfig.connectionRequestTimeout = 10.0

	let httpClient = DefaultHTTPClient(config: httpClientConfig)
	let clientConfig = ClientConfig(
	    apiKey: "YOUR-API-KEY",
	    application: "ios-app",
	    endpoint: "https://your-company.absmartly.io/v1",
	    environment: "production"
	)

	let client = try DefaultClient(config: clientConfig, httpClient: httpClient)
	let sdkConfig = ABSmartlyConfig(client: client)
	let sdk = try ABSmartlySDK(config: sdkConfig)
	_ = httpClientConfig
	_ = httpClient
	_ = clientConfig
	_ = client
	_ = sdkConfig
	_ = sdk
}
