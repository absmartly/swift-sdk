# A/B Smartly Swift SDK <a href="https://github.com/apple/swift-package-manager" alt="RxSwift on Swift Package Manager" title="RxSwift on Swift Package Manager"><img src="https://img.shields.io/badge/Swift%20Package%20Manager-compatible-brightgreen.svg" /></a>

A/B Smartly - Swift SDK for iOS and macOS applications.

## Compatibility

The A/B Smartly Swift SDK is supported on:
- iOS 10.0 or later
- macOS 10.10 or later

| Platform    | Support    | Notes                                          |
|-------------|------------|------------------------------------------------|
| iOS         | iOS 10+    | Full support including UIDevice integration    |
| macOS       | 10.10+     | Full support                                   |
| Swift       | 5.0+       | Swift Package Manager and CocoaPods supported  |

## Installation

### Swift Package Manager

To install the A/B Smartly SDK using Swift Package Manager, following these steps:

- In Xcode go to: ```File -> Swift Packages -> Add Package Dependency...```

- Enter the A/B Smartly Swift SDK GitHub repository: ```https://github.com/absmartly/swift-sdk```

- Select the SDK version (latest recommended)

- Select the ABSmartly library

### Cocoapods

To install the A/B Smartly SDK with CocoaPods, add the following lines to your `Podfile`:

```ruby
pod 'ABSmartlySwiftSDK', '~> 1.0.2'
```

Run the following command to update your Xcode project:
```
pod install
```

## Getting Started

Please follow the [installation](#installation) instructions before trying the following code.

### Initialization

This example assumes an API Key, an Application, and an Environment have been created in the A/B Smartly web console.

Import the SDK into your application:

```swift
import ABSmartly
```

#### Recommended: Named Parameters

Initialize the SDK using named parameters:

```swift
let sdk: ABsmartlySDK
do {
    sdk = try ABsmartlySDK(
        endpoint: "https://your-company.absmartly.io/v1",
        apiKey: "YOUR-API-KEY",
        application: "website",
        environment: "production"
    )
} catch {
    print("Failed to initialize ABSmartly SDK: \(error.localizedDescription)")
    return
}
```

#### With Optional Parameters

```swift
let sdk = try ABsmartlySDK(
    endpoint: "https://your-company.absmartly.io/v1",
    apiKey: "YOUR-API-KEY",
    application: "website",
    environment: "production",
    applicationVersion: "1.0.0",
    timeout: 5.0,           // Default: 3.0 seconds
    retries: 3              // Default: 5
)
```

#### Alternative: Using Configuration Objects

For use cases with custom providers or handlers:

```swift
let clientConfig = ClientConfig(
    apiKey: "YOUR-API-KEY",
    application: "website",
    endpoint: "https://your-company.absmartly.io/v1",
    environment: "production"
)

let client = try DefaultClient(config: clientConfig)
let sdkConfig = ABsmartlyConfig(client: client)
let sdk = try ABsmartlySDK(config: sdkConfig)
```

**SDK Options**

| Config                  | Type                              | Required? |   Default   | Description                                                                                                                                                                   |
| :---------------------- | :-------------------------------- | :-------: | :---------: | :---------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| endpoint                | `String`                          | &#9989;   | `nil`       | The URL to your API endpoint. Most commonly `"https://your-company.absmartly.io/v1"`                                                                                         |
| apiKey                  | `String`                          | &#9989;   | `nil`       | Your API key which can be found on the Web Console.                                                                                                                           |
| application             | `String`                          | &#9989;   | `nil`       | The name of the application where the SDK is installed. Applications are created on the Web Console and should match the applications where your experiments will be running. |
| environment             | `String`                          | &#9989;   | `nil`       | The environment of the platform where the SDK is installed. Environments are created on the Web Console and should match the available environments in your infrastructure.   |
| applicationVersion      | `String`                          | &#10060;  | `"0"`       | The version of your application.                                                                                                                                              |
| timeout                 | `TimeInterval`                    | &#10060;  | `3.0`       | Network request timeout in seconds.                                                                                                                                           |
| retries                 | `UInt`                            | &#10060;  | `5`         | Number of retry attempts for failed network requests.                                                                                                                         |
| contextEventLogger      | `ContextEventLogger`              | &#10060;  | `nil`       | Callback to handle SDK events (ready, exposure, goal, etc.)                                                                                                                   |
| contextDataProvider     | `ContextDataProvider`             | &#10060;  | auto        | Custom provider for context data (advanced usage)                                                                                                                             |
| contextEventHandler     | `ContextEventHandler`             | &#10060;  | auto        | Custom handler for publishing events (advanced usage)                                                                                                                         |
| variableParser          | `VariableParser`                  | &#10060;  | auto        | Custom parser for variable values (advanced usage)                                                                                                                            |
| scheduler               | `Scheduler`                       | &#10060;  | auto        | Custom scheduler for async operations (advanced usage)                                                                                                                        |

## Creating a New Context

### Asynchronously (Recommended)

```swift
let contextConfig = ContextConfig()
contextConfig.setUnit(unitType: "session_id", uid: "5ebf06d8cb5d8137290c4abb64155584fbdb64d8")

let context = sdk.createContext(config: contextConfig)
context.waitUntilReady().done { context in
    print("ABSmartly Context ready!")
}.catch { error in
    print("Context failed to initialize: \(error.localizedDescription)")
}
```

### Using async/await (iOS 13+)

```swift
let contextConfig = ContextConfig()
contextConfig.setUnit(unitType: "session_id", uid: "5ebf06d8cb5d8137290c4abb64155584fbdb64d8")

let context = sdk.createContext(config: contextConfig)
do {
    try await context.waitUntilReady()
    print("ABSmartly Context ready!")
} catch {
    print("Context failed to initialize: \(error.localizedDescription)")
}
```

### With Pre-fetched Data

When doing full-stack experimentation with A/B Smartly, we recommend creating a context only once on the server-side. Creating a context involves a round-trip to the A/B Smartly event collector. We can avoid repeating the round-trip on the client-side by sending the server-side data embedded with other application data. Then we can initialize the A/B Smartly context directly with it.

```swift
let contextConfig = ContextConfig()
contextConfig.setUnit(unitType: "session_id", uid: "5ebf06d8cb5d8137290c4abb64155584fbdb64d8")

let context = sdk.createContext(config: contextConfig)
try await context.waitUntilReady()

let anotherContextConfig = ContextConfig()
anotherContextConfig.setUnit(unitType: "session_id", uid: "another-user-id")

let anotherContext = sdk.createContextWithData(config: anotherContextConfig, contextData: context.getContextData())
```

### Refreshing the Context with Fresh Experiment Data

For long-running contexts, the context is usually created once when the application is first started. However, any experiments being tracked in your production code, but started after the context was created, will not be triggered.

To mitigate this, we can use the `refreshInterval` property on the context config:

```swift
let contextConfig = ContextConfig()
contextConfig.setUnit(unitType: "session_id", uid: "5ebf06d8cb5d8137290c4abb64155584fbdb64d8")
contextConfig.refreshInterval = 4 * 3600 // every 4 hours (in seconds)
```

Alternatively, the `refresh()` method can be called manually. The `refresh()` method pulls updated experiment data from the A/B Smartly collector and will trigger recently started experiments when `getTreatment()` is called again.

```swift
context.refresh().done {
    print("Context refreshed with latest experiment data")
}.catch { error in
    print("Refresh failed: \(error.localizedDescription)")
}
```

### Setting Extra Units

You can add additional units to a context by calling the `setUnit()` or `setUnits()` methods. This is useful when a user logs in to your application and you want to associate a new unit type with the context.

Please note that **you cannot override an already set unit type** as that would be a change of identity. In this case, you must create a new context instead.

The `setUnit()` and `setUnits()` methods can be called before the context is ready.

```swift
context.setUnit(unitType: "db_user_id", uid: "1000013")
context.setUnits([
    "db_user_id": "1000013"
])
```

## Basic Usage

### Selecting a Treatment

```swift
let treatment = context.getTreatment("exp_test_experiment")
if treatment == 0 {
    // user is in control group (variant 0)
} else {
    // user is in treatment group
}
```

### Treatment Variables

```swift
let defaultButtonColor = "red"
let buttonColor = context.getVariableValue("button.color", defaultValue: defaultButtonColor)
```

### Peek at Treatment Variants

Although generally not recommended, it is sometimes necessary to peek at a treatment or variable without triggering an exposure. The A/B Smartly SDK provides a `peekTreatment()` method for that.

```swift
let treatment = context.peekTreatment("exp_test_experiment")
if treatment == 0 {
    // user is in control group (variant 0)
} else {
    // user is in treatment group
}
```

#### Peeking at Variables

```swift
let color = context.peekVariableValue("colorGComponent", defaultValue: 255)
```

### Overriding Treatment Variants

During development, for example, it is useful to force a treatment for an experiment. This can be achieved with the `setOverride()` and/or `setOverrides()` methods.

The `setOverride()` and `setOverrides()` methods can be called before the context is ready.

```swift
context.setOverride(experimentName: "exp_test_experiment", variant: 1)  // force variant 1 of treatment
context.setOverrides(["exp_test_experiment": 1, "exp_another_experiment": 0])
```

## Advanced

### Context Attributes

The `setAttribute()` and `setAttributes()` methods can be called before the context is ready.

```swift
context.setAttribute(name: "device", value: UIDevice.current.model)
context.setAttributes([
    "customer_age": "new_customer",
    "screen": "product"
])
```

### Tracking Goals

Goals are created in the A/B Smartly web console.

```swift
context.track("payment", properties: [
    "item_count": 1,
    "total_amount": 1999.99
])
```

### Publishing Pending Data

Sometimes it is necessary to ensure all events have been published to the A/B Smartly collector before proceeding. You can explicitly call the `publish()` method.

```swift
context.publish().done {
    print("All pending events published")
}.catch { error in
    print("Publish failed: \(error.localizedDescription)")
}
```

### Finalizing

The `close()` method will ensure all events have been published to the A/B Smartly collector, like `publish()`, and will also "seal" the context, throwing an error if any method that could generate an event is called.

```swift
context.close().done {
    print("Context closed")
}.catch { error in
    print("Close failed: \(error.localizedDescription)")
}
```

### Custom Event Logger

The A/B Smartly SDK can be instantiated with an event logger used for all contexts. In addition, an event logger can be specified when creating a particular context in the `ContextConfig`.

```swift
public class CustomEventLogger: ContextEventLogger {
    public func handleEvent(context: Context, event: ContextEventLoggerEvent) {
        switch event {
        case let .exposure(exposure):
            print("Exposed to experiment: \(exposure.name)")
        case let .goal(goal):
            print("Goal tracked: \(goal.name)")
        case let .error(error):
            print("Error: \(error.localizedDescription)")
        case let .publish(event):
            print("Events published")
        case let .ready(data):
            print("Context ready")
        case let .refresh(data):
            print("Context refreshed")
        case .close:
            print("Context closed")
        }
    }
}
```

**Usage:**

```swift
// For all contexts, during SDK initialization
let sdk = try ABsmartlySDK(
    endpoint: "https://your-company.absmartly.io/v1",
    apiKey: "YOUR-API-KEY",
    application: "website",
    environment: "production",
    contextEventLogger: CustomEventLogger()
)

// OR, alternatively, during a particular context initialization
let contextConfig = ContextConfig()
contextConfig.eventLogger = CustomEventLogger()
```

**Event Types**

The data parameter depends on the type of event. Currently, the SDK logs the following events:

| Event      | When                                               | Data                                      |
| ---------- | -------------------------------------------------- | ----------------------------------------- |
| `error`    | Context receives an error                          | `Error` object                            |
| `ready`    | Context turns ready                                | `ContextData` used to initialize          |
| `refresh`  | `refresh()` method succeeds                        | `ContextData` used to refresh             |
| `publish`  | `publish()` method succeeds                        | `PublishEvent` sent to collector          |
| `exposure` | `getTreatment()` succeeds on first exposure        | `Exposure` enqueued for publishing        |
| `goal`     | `track()` method succeeds                          | `GoalAchievement` enqueued for publishing |
| `close`    | `close()` method succeeds the first time           | `nil`                                     |

## Platform-Specific Examples

### Using with SwiftUI (iOS 13+)

```swift
// ABSmartlyService.swift
import Foundation
import ABSmartly

class ABSmartlyService: ObservableObject {
    static let shared = ABSmartlyService()

    private let sdk: ABsmartlySDK

    private init() {
        sdk = try! ABsmartlySDK(
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
import SwiftUI
import ABSmartly

struct ContentView: View {
    @StateObject private var absmartly = ABSmartlyService.shared
    @State private var context: Context?
    @State private var buttonColor: String = "blue"

    var body: some View {
        VStack {
            Button("Click Me") {
                context?.track("button_clicked")
            }
            .foregroundColor(Color(buttonColor))
            .padding()
        }
        .task {
            do {
                let deviceId = UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString
                context = try await absmartly.createContext(deviceId: deviceId)

                let treatment = context?.getTreatment("button_test")
                buttonColor = context?.getVariableValue("button.color", defaultValue: "blue") ?? "blue"
            } catch {
                print("Failed to initialize ABSmartly: \(error)")
            }
        }
        .onDisappear {
            context?.close()
        }
    }
}
```

### Using with UIKit (iOS 10+)

```swift
// ExperimentViewController.swift
import UIKit
import ABSmartly
import PromiseKit

class ExperimentViewController: UIViewController {
    private var sdk: ABsmartlySDK!
    private var context: Context?

    override func viewDidLoad() {
        super.viewDidLoad()

        do {
            sdk = try ABsmartlySDK(
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
        context?.close()
    }
}
```

### Using with macOS AppKit

```swift
// AppDelegate.swift
import Cocoa
import ABSmartly
import PromiseKit

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate {
    private var sdk: ABsmartlySDK!
    private var context: Context?

    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            sdk = try ABsmartlySDK(
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
        let platformExpert = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPlatformExpertDevice"))
        defer { IOObjectRelease(platformExpert) }

        guard let serialNumber = IORegistryEntryCreateCFProperty(
            platformExpert,
            kIOPlatformSerialNumberKey as CFString,
            kCFAllocatorDefault,
            0
        ).takeRetainedValue() as? String else {
            return UUID().uuidString
        }

        return serialNumber
    }

    private func runExperiment(context: Context) {
        let featureEnabled = context.getTreatment("new_feature") == 1

        if featureEnabled {
            let featureConfig = context.getVariableValue("feature.config", defaultValue: [:])
        }

        context.track("app_launched")
    }

    func applicationWillTerminate(_ notification: Notification) {
        context?.close()
    }
}
```

## Advanced Request Configuration

### PromiseKit Cancellation (iOS 10+)

The Swift SDK uses PromiseKit for async operations. You can cancel promises:

```swift
import ABSmartly
import PromiseKit

class ExperimentLoader {
    private var sdk: ABsmartlySDK!
    private var contextPromise: Promise<Context>?

    func loadExperiment(deviceId: String) {
        let contextConfig = ContextConfig()
        contextConfig.setUnit(unitType: "device_id", uid: deviceId)

        let context = sdk.createContext(config: contextConfig)
        contextPromise = context.waitUntilReady()

        contextPromise?.done { ctx in
            print("Context ready!")
        }.catch { error in
            if error is CancellableError {
                print("Context loading cancelled")
            } else {
                print("Context failed: \(error.localizedDescription)")
            }
        }
    }

    func cancelLoad() {
        contextPromise?.cancel()
        print("Cancelling context load...")
    }
}
```

### iOS 13+ async/await with Task Cancellation

```swift
import ABSmartly

class ExperimentManager {
    private var sdk: ABsmartlySDK!
    private var contextTask: Task<Context, Error>?

    func loadExperiment(deviceId: String) {
        contextTask = Task {
            let contextConfig = ContextConfig()
            contextConfig.setUnit(unitType: "device_id", uid: deviceId)

            let context = sdk.createContext(config: contextConfig)
            try await context.waitUntilReady()

            return context
        }

        Task {
            do {
                let context = try await contextTask!.value
                print("Context ready!")
                await handleExperiment(context: context)
            } catch is CancellationError {
                print("Context loading cancelled")
            } catch {
                print("Context failed: \(error)")
            }
        }
    }

    func cancelLoad() {
        contextTask?.cancel()
        print("Cancelling context load...")
    }

    private func handleExperiment(context: Context) async {
        let treatment = context.getTreatment("experiment_name")
    }
}
```

### Timeout Override

Override the default timeout:

```swift
let sdk = try ABsmartlySDK(
    endpoint: "https://your-company.absmartly.io/v1",
    apiKey: "YOUR-API-KEY",
    application: "ios-app",
    environment: "production",
    timeout: 10.0  // 10 seconds instead of default 3 seconds
)
```

For full control over the HTTP client configuration:

```swift
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
let sdkConfig = ABsmartlyConfig(client: client)
let sdk = try ABsmartlySDK(config: sdkConfig)
```

## About A/B Smartly

**A/B Smartly** is the leading provider of state-of-the-art, on-premises, full-stack experimentation platforms for engineering and product teams that want to confidently deploy features as fast as they can develop them.
A/B Smartly's real-time analytics helps engineering and product teams ensure that new features will improve the customer experience without breaking or degrading performance and/or business metrics.

### Have a look at our growing list of clients and SDKs:
- [JavaScript SDK](https://www.github.com/absmartly/javascript-sdk)
- [Java SDK](https://www.github.com/absmartly/java-sdk)
- [PHP SDK](https://www.github.com/absmartly/php-sdk)
- [Swift SDK](https://www.github.com/absmartly/swift-sdk) (this package)
- [Vue2 SDK](https://www.github.com/absmartly/vue2-sdk)
- [Vue3 SDK](https://www.github.com/absmartly/vue3-sdk)
- [React SDK](https://www.github.com/absmartly/react-sdk)
- [Python3 SDK](https://www.github.com/absmartly/python3-sdk)
- [Go SDK](https://www.github.com/absmartly/go-sdk)
- [Ruby SDK](https://www.github.com/absmartly/ruby-sdk)
- [.NET SDK](https://www.github.com/absmartly/dotnet-sdk)
- [Dart SDK](https://www.github.com/absmartly/dart-sdk)
- [Flutter SDK](https://www.github.com/absmartly/flutter-sdk)
