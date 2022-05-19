# A/B Smartly SDK <a href="https://github.com/apple/swift-package-manager" alt="RxSwift on Swift Package Manager" title="RxSwift on Swift Package Manager"><img src="https://img.shields.io/badge/Swift%20Package%20Manager-compatible-brightgreen.svg" /></a>

A/B Smartly - Swift SDK

## Compatibility

The A/B Smartly Swift SDK is supported on macOS version 10.10 or later and iOS version 10 or later.

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

Please follow the [installation](#installation) instructions before trying the following code:

#### Initialization

Import the SDK into your application:

```swift
import ABSmartly
```


Initialize the client and the SDK
```swift
let sdk: ABSmartlySDK
do {
    let clientConfig = ClientConfig(
        apiKey: ProcessInfo.processInfo.environment["ABSMARTLY_API_KEY"] ?? "",
        application: ProcessInfo.processInfo.environment["ABSMARTLY_APPLICATION"] ?? "",
        endpoint: ProcessInfo.processInfo.environment["ABSMARTLY_ENDPOINT"] ?? "",
        environment: ProcessInfo.processInfo.environment["ABSMARTLY_ENVIRONMENT"] ?? ""))

    let client = try DefaultClient(config: clientConfig)
    let sdkConfig = ABSmartlyConfig(client: client)
    sdk = try ABSmartlySDK(config: sdkConfig)
} catch {
    print(error.localizedDescription)
    return
}
```

#### Creating a new Context
```swift
let contextConfig: ContextConfig = ContextConfig()
contextConfig.setUnit(unitType: "device_id", uid: UIDevice.current.identifierForVendor!.uuidString))

let context = sdk.createContext(config: contextConfig)
context.waitUntilReady().done { context in
    print("context ready")
}
```

#### Creating a new Context with pre-fetched data
When doing full-stack experimentation with A/B Smartly, we recommend creating a context only once on the server-side.
Creating a context involves a round-trip to the A/B Smartly event collector.
We can avoid repeating the round-trip on the client-side by sending the server-side data embedded with other application data.
Then we can initialize the A/B Smartly context directly with it.

```swift
let contextConfig: ContextConfig = ContextConfig()
contextConfig.setUnit(unitType: "device_id", uid: UIDevice.current.identifierForVendor!.uuidString)

let context = sdk.createContextWithData(config: anotherContextConfig, contextData: contextData)
```

#### Setting extra units for a context
You can add additional units to a context by calling the `setUnit()` or the `setUnits()` method.
This method may be used for example, when a user logs in to your application, and you want to use the new unit type to the context.
Please note that **you cannot override an already set unit type** as that would be a change of identity, and will crash your application. In this case, you must create a new context instead.
The `setUnit()` and `setUnits()` methods can be called before the context is ready.

```swift
context.setUnit(unitType: "db_user_id", uid: "1000013");
context.setUnits([
    "db_user_id": "1000013"
]);
```

#### Setting context attributes
The `setAttribute()` and `setAttributes()` methods can be called before the context is ready.
```swift
context.setAttribute(name: "device", value: UIDevice.current.model)
context.setAttributes(["customer_age": "new_customer", "screen": "product"])
```

#### Selecting a treatment
```swift
let treatment = context.getTreatment("exp_test_experiment")
if treatment == 0 {
    // user is in control group (variant 0)
} else {
    // user is in treatment group
}
```

#### Selecting a treatment variable
```swift
let variable = context.getVariableValue("my_variable", defaultValue: 10)
```

#### Tracking a goal achievement
Goals are created in the A/B Smartly web console.
```swift
context.track("payment", properties: ["item_count": 1, "total_amount": 1999.99])
```

#### Publishing pending data
Sometimes it is necessary to ensure all events have been published to the A/B Smartly collector, before proceeding. You can explicitly call the `publish()` method.
```swift
context.publish().done {
    print("all pending events published")
}
```

#### Finalizing
The `close()` methods will ensure all events have been published to the A/B Smartly collector, like `publish()`, and will also "seal" the context, throwing an error if any method that could generate an event is called.
```swift
context.close().done {
    print("context closed")
}
```

#### Refreshing the context with fresh experiment data
For long-running contexts, the context is usually created once when the application is first reached.
However, any experiments being tracked in your production code, but started after the context was created, will not be triggered.
To mitigate this, we can use the `setRefreshInterval()` method on the context config.

```swift
let contextConfig: ContextConfig = ContextConfig()
contextConfig.setUnit(unitType: "device_id", uid: UIDevice.current.identifierForVendor!.uuidString)
contextConfig.refreshInterval = 4 * 3600; // every 4 hours
```

Alternatively, the `refresh()` method can be called manually.

```swift
context.refresh().done {
    print("refreshed")
}
```


#### Using a custom Event Logger
The A/B Smartly SDK can be instantiated with an event logger used for all contexts.
In addition, an event logger can be specified when creating a particular context, in the `ContextConfig`.
```swift
// example implementation
public class CustomEventLogger : ContextEventLogger {
    public func handleEvent(context: Context, event: ContextEventLoggerEvent) {
        switch event {
        case let .exposure(exposure):
            print("exposed to experiment: \(exposure.name)")
        case let .goal(goal):
            print("goal tracked: \(goal.name)")
        case let .error(error):
            print("error: ", error.localizedDescription)
        case let .publish(event):
            break
        case let .ready(data):
            break
        case let .refresh(data):
            break
        case .close:
            break
        }
    }
}

// for all contexts, during sdk initialization
let absmartlyConfig = ABSmartlyConfig()
absmartlyConfig.contextEventLogger = CustomEventLogger()

// OR, alternatively, during a particular context initialization
let contextConfig = ContextConfig()
contextConfig.eventLogger = CustomEventLogger()
```

The event data depends on the type of event.
Currently, the SDK logs the following events:

|   event    | when                                                       | data                                                   |
|:----------:|------------------------------------------------------------|--------------------------------------------------------|
|  `error`   | `Context` receives an error                                | `Error` object                                         |
|  `ready`   | `Context` turns ready                                      | `ContextData` used to initialize the context           |
| `refresh`  | `Context.refresh()` method succeeds                        | `ContextData` used to refresh the context              |
| `publish`  | `Context.publish()` method succeeds                        | `PublishEvent` sent to the A/B Smartly event collector |
| `exposure` | `Context.getTreatment()` method succeeds on first exposure | `Exposure` enqueued for publishing                     |
|   `goal`   | `Context.track()` method succeeds                          | `GoalAchievement` enqueued for publishing              |
|  `close`   | `Context.close()` method succeeds the first time           | `nil`                                                    |

#### Peek at treatment variants
Although generally not recommended, it is sometimes necessary to peek at a treatment or variable without triggering an exposure.
The A/B Smartly SDK provides a `peekTreatment()` method for that.

```swift
let treatment = context.peekTreatment(experimentName: "exp_test_experiment")

if treatment == 0 {
    // user is in control group (variant 0)
} else {
    // user is in treatment group
}
```

##### Peeking at variables
```swift
let color = context.peekVariableValue("colorGComponent", defaultValue: 255)
```

#### Overriding treatment variants
During development, for example, it is useful to force a treatment for an experiment. This can be achieved with the `override()` and/or `overrides()` methods.
The `setOverride()` and `setOverrides()` methods can be called before the context is ready.
```swift
context.setOverride(experimentName: "exp_test_experiment", variant: 1)  // force variant 1 of treatment
context.setOverrides(["exp_test_experiment": 1, "exp_another_experiment": 0])
```

## About A/B Smartly
**A/B Smartly** is the leading provider of state-of-the-art, on-premises, full-stack experimentation platforms for engineering and product teams that want to confidently deploy features as fast as they can develop them.
A/B Smartly's real-time analytics helps engineering and product teams ensure that new features will improve the customer experience without breaking or degrading performance and/or business metrics.

### Have a look at our growing list of clients and SDKs:
- [Java SDK](https://www.github.com/absmartly/java-sdk)
- [JavaScript SDK](https://www.github.com/absmartly/javascript-sdk)
- [PHP SDK](https://www.github.com/absmartly/php-sdk)
- [Swift SDK](https://www.github.com/absmartly/swift-sdk)
- [Vue2 SDK](https://www.github.com/absmartly/vue2-sdk)
