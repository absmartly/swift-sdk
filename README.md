# A/B Smartly Swift SDK <a href="https://github.com/apple/swift-package-manager" title="Swift Package Manager compatible"><img src="https://img.shields.io/badge/Swift%20Package%20Manager-compatible-brightgreen.svg" alt="Swift Package Manager compatible" /></a>

A/B Smartly - Swift SDK for iOS, macOS and Linux applications.

## Compatibility

The A/B Smartly Swift SDK is supported on:
- iOS 10.0 or later
- macOS 10.14 or later (Swift Package Manager; 10.10 with CocoaPods)
- Linux (Swift Package Manager, Swift 5.10 or later)

The async/await API (`import ABSmartlyAsync`) needs iOS 13, macOS 10.15, tvOS 13 or watchOS 6.

### Support

1.5.0 is the last 1.x feature release. A 2.0 SDK with a new, async-first API is coming; 1.x will be
maintained (bug and security fixes, from the `release/1.x` branch) for 12 months after 2.0 ships.

| Platform    | Support    | Notes                                          |
|-------------|------------|------------------------------------------------|
| iOS         | iOS 10+    | Full support including UIDevice integration    |
| macOS       | 10.14+ (Swift Package Manager), 10.10+ (CocoaPods) | Full support |
| Linux       | Swift 5.10+ | Swift Package Manager; tested in CI with Swift 5.10 and 6.1. `JSON` is a vendored copy of SwiftyJSON's `JSON` (same API); on Apple platforms it is `SwiftyJSON.JSON` |
| Swift       | 5.3+ tools, Swift 5 language mode | Swift Package Manager (and CocoaPods, see below); builds with Swift 6 toolchains and can be used from Swift 6 apps |

## Installation

### Swift Package Manager

To install the A/B Smartly SDK using Swift Package Manager, following these steps:

- In Xcode go to: ```File -> Swift Packages -> Add Package Dependency...```

- Enter the A/B Smartly Swift SDK GitHub repository: ```https://github.com/absmartly/swift-sdk```

- Select the SDK version (latest recommended)

- Select the ABSmartly library

### Cocoapods

The latest version on the CocoaPods trunk is 1.3.4; 1.4.0 and 1.5.0 are available through Swift
Package Manager. To use CocoaPods, add the following lines to your `Podfile`:

```ruby
pod 'ABSmartlySwiftSDK', '~> 1.3'
```

To use 1.5.0 through CocoaPods before it is on the trunk, point the pod at the git tag:
`pod 'ABSmartlySwiftSDK', :git => 'https://github.com/absmartly/swift-sdk.git', :tag => 'v1.5.0'`.
On current Xcode the dependency pods do not build at their own deployment targets: SwiftyJSON 5
(macOS 10.9) fails on macOS, and PromiseKit 6 (iOS 8) needs `libarclite`, which Xcode 26 no longer
ships. Raise their deployment targets in your Podfile's `post_install` hook, or use Swift Package
Manager.

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

`ABSmartlySDK`/`ABsmartlySDK`, `ABSmartlyConfig`/`ABsmartlyConfig`, `ContextEventHandler`/`ContextPublisher`
and `DefaultContextEventHandler`/`DefaultContextPublisher` are two spellings of the same types; use either.

#### Recommended: Named Parameters

Initialize the SDK using named parameters:

```swift
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
```

#### With Optional Parameters

```swift
let sdk = try ABSmartlySDK(
    endpoint: "https://your-company.absmartly.io/v1",
    apiKey: "YOUR-API-KEY",
    application: "website",
    environment: "production",
    applicationVersion: "10000",   // An integer; sent as "0" otherwise
    timeout: 5.0,           // Default: 3.0 seconds
    retries: 5              // Default: 3
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
let sdkConfig = ABSmartlyConfig(client: client)
let sdk = try ABSmartlySDK(config: sdkConfig)
```

**SDK Options**

| Config                  | Type                              | Required? |   Default   | Description                                                                                                                                                                   |
| :---------------------- | :-------------------------------- | :-------: | :---------: | :---------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| endpoint                | `String`                          | &#9989;   | `nil`       | The URL to your API endpoint. Most commonly `"https://your-company.absmartly.io/v1"`                                                                                         |
| apiKey                  | `String`                          | &#9989;   | `nil`       | Your API key which can be found on the Web Console.                                                                                                                           |
| application             | `String`                          | &#9989;   | `nil`       | The name of the application where the SDK is installed. Applications are created on the Web Console and should match the applications where your experiments will be running. |
| environment             | `String`                          | &#9989;   | `nil`       | The environment of the platform where the SDK is installed. Environments are created on the Web Console and should match the available environments in your infrastructure.   |
| applicationVersion      | `String`                          | &#10060;  | `"0"`       | The version of your application, as an integer (e.g. `"10203"`). The collector only accepts digits, so any other value is sent as `"0"`.                                                                                                                                            |
| timeout                 | `TimeInterval`                    | &#10060;  | `3.0`       | Network request timeout in seconds.                                                                                                                                           |
| retries                 | `UInt`                            | &#10060;  | `3`         | Number of retry attempts for failed network requests.                                                                                                                         |
| contextEventLogger      | `ContextEventLogger`              | &#10060;  | `nil`       | Callback to handle SDK events (ready, exposure, goal, etc.)                                                                                                                   |
| contextDataProvider     | `ContextDataProvider`             | &#10060;  | auto        | Custom provider for context data (advanced usage)                                                                                                                             |
| contextEventHandler     | `ContextEventHandler`             | &#10060;  | auto        | Custom handler for publishing events (advanced usage). `ContextPublisher` is the same protocol under the name other SDKs use.                                               |
| variableParser          | `VariableParser`                  | &#10060;  | auto        | Custom parser for variable values (advanced usage)                                                                                                                            |
| scheduler               | `Scheduler`                       | &#10060;  | auto        | Custom scheduler for async operations (advanced usage)                                                                                                                        |

## Creating a New Context

### Asynchronously (Recommended)

```swift
let contextConfig = ContextConfig()
contextConfig.setUnit(unitType: "session_id", uid: "5ebf06d8cb5d8137290c4abb64155584fbdb64d8")

let context = sdk.createContext(config: contextConfig)
_ = context.waitUntilReady().done { context in
    print("ABSmartly Context ready!")
}
```

### Using async/await (iOS 13+)

The async/await overloads live in the `ABSmartlyAsync` module, which is part of the `ABSmartly`
package product (Swift Package Manager only). Import it instead of (or as well as) `ABSmartly`:

```swift
import ABSmartlyAsync

let context = sdk.createContext(config: config)
try await context.waitUntilReady()
try await context.publish()
try await context.close()
```

Every Promise-returning method has an async overload with the same name: `Context.waitUntilReady()`,
`refresh()`, `publish()`, `close()` and `finalize()`, `ABSmartlySDK.getContextData()` and `close()`,
the `Client`, `ContextDataProvider`, `ContextEventHandler` and `HTTPClient` methods, and
`DefaultHTTPClient.request`. Each awaits
the Promise the existing method returns, so it does the same work and returns or throws the same
result; as with the Promise, `waitUntilReady()` does not throw when the context fails to load (check
`context.isFailed()`). The PromiseKit methods are unchanged.

A type of your own that adopts two of `Client`, `ContextDataProvider`, `ContextEventHandler` and
`HTTPClient` gets two async versions of the methods they share, so call them through one protocol:
`try await (myClient as Client).close()`.

Once any module in your build imports `ABSmartlyAsync` (your own target or a dependency), Swift makes
the async overloads visible to every file that uses `ABSmartly`, even files that only `import
ABSmartly`. Inside an `async` function Swift then prefers them, so 1.4 code there such as
`_ = context.publish()` stops compiling. Fix it with `try await context.publish()`, or keep the
Promise with an explicit type, which needs `import PromiseKit` in that file (`ABSmartly` does not
re-export it): `let promise: Promise<Void> = context.publish()`. With Swift 6.1 or
later you can instead enable the `MemberImportVisibility` upcoming feature
(`swiftSettings: [.enableUpcomingFeature("MemberImportVisibility")]`), which limits the overloads to
files that import `ABSmartlyAsync` themselves.

Cancelling the calling `Task` does not cancel the underlying request: the call still waits for the
fetch, publish or close to finish and returns its result. Check `Task.isCancelled` afterwards if you
need to.

Call the async methods from an `async` function or a `Task {}`. In synchronous code, `try await
context.waitUntilReady()` picks the Promise method and returns without waiting; the compiler warns
"no 'async' operations occur within 'await' expression" when that happens.

From a `@MainActor` view model or an actor, the calls run in the caller's isolation, so they compile
without Sendable warnings in Swift 6 apps:

```swift
import ABSmartlyAsync

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
        // waitUntilReady() does not throw when the data fails to load; the context is then ready
        // and failed, and every treatment is the control variant.
        _ = try? await context.waitUntilReady()
        if context.isFailed() {
            print("Context failed to load: \(context.readyError()?.localizedDescription ?? "unknown error")")
        }
        showNewCheckout = context.getTreatment("exp_new_checkout") == 1
        self.context = context
    }
}
```

### With Pre-fetched Data

When doing full-stack experimentation with A/B Smartly, we recommend creating a context only once on the server-side. Creating a context involves a round-trip to the A/B Smartly event collector. We can avoid repeating the round-trip on the client-side by sending the server-side data embedded with other application data. Then we can initialize the A/B Smartly context directly with it.

```swift
let contextConfig = ContextConfig()
contextConfig.setUnit(unitType: "session_id", uid: "5ebf06d8cb5d8137290c4abb64155584fbdb64d8")

// contextData: a ContextData received from your server
let context = sdk.createContextWithData(config: contextConfig, contextData: contextData)
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

// or, with `import ABSmartlyAsync`
try await context.refresh()
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
let defaultButtonColor: JSON = "red"
let buttonColor = context.getVariableValue("button.color", defaultValue: defaultButtonColor)?.stringValue
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

The configured `application` and `environment` names are always available to audience filters and
assignment-rule conditions as the `application` and `environment` attributes, so experiments can be
targeted by them without setting anything. A user-set attribute of the same name wins, even when set
after the context is created. These attributes are evaluation-only: they are not sent on the publish
payload (the collector adds them server-side) and are not returned by `getAttributes()`.

Audience filters and rule conditions can compare versions with `semver_eq`, `semver_gt`, `semver_gte`,
`semver_lt` and `semver_lte` (a leading `v` and build metadata are ignored, and a release ranks above
its pre-releases).

### Assignment Rules

Experiments can carry ordered assignment rules, set up in the A/B Smartly dashboard. The first rule
whose environments and conditions match decides the variant: an `assign` rule sets a fixed variant, and
a `split` rule spreads matching units over the variants by its percentages (hashed with the
experiment's own seed). A matching rule wins over the audience, traffic allocation, full-on and custom
assignments; only `setOverride` beats it. Its exposures carry `ruleOverride: true` and are kept out of
the experiment's analysis.

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

// or, with `import ABSmartlyAsync`
try await context.publish()
```

### Finalizing

The `close()` method will ensure all events have been published to the A/B Smartly collector, like `publish()`, and will also "seal" the context, after which any method that could generate an event is ignored and logs an `error` event.

```swift
context.close().done {
    print("Context closed")
}.catch { error in
    print("Close failed: \(error.localizedDescription)")
}

// or, with `import ABSmartlyAsync`
try await context.close()
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
```

**Usage:**

```swift
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

### Using with SwiftUI (iOS 15+)

```swift
// ABSmartlyService.swift
import Combine
import Foundation
import ABSmartlyAsync

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
import SwiftUI
import ABSmartlyAsync

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
```

### Using with UIKit (iOS 10+)

```swift
// ExperimentViewController.swift
import UIKit
import ABSmartly
import PromiseKit

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
```

### Using with macOS AppKit

```swift
// AppDelegate.swift
import Cocoa
import ABSmartly
import PromiseKit

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
```

## Advanced Request Configuration

### Cancellation

The SDK's Promises cannot be cancelled: a context load, refresh, publish or close always runs to
completion. If the result is no longer needed (for example the screen went away), ignore it.

### iOS 13+ async/await and Task Cancellation

The async methods do not respond to task cancellation: a cancelled task still waits for the context
to load (or the publish/close to finish) and gets its result. To stop work after a cancelled load,
check `Task.isCancelled` yourself:

```swift
import ABSmartlyAsync

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
```

Usage:

```swift
let manager = ExperimentManager(sdk: sdk)
manager.loadExperiment(deviceId: "device-123")
// later, e.g. when the screen goes away:
manager.cancelLoad()
```

### Timeout Override

Override the default timeout:

```swift
let sdk = try ABSmartlySDK(
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
let sdkConfig = ABSmartlyConfig(client: client)
let sdk = try ABSmartlySDK(config: sdkConfig)
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
