# A/B Smartly SDK <a href="https://github.com/apple/swift-package-manager" alt="RxSwift on Swift Package Manager" title="RxSwift on Swift Package Manager"><img src="https://img.shields.io/badge/Swift%20Package%20Manager-compatible-brightgreen.svg" /></a>

A/B Smartly - Swift SDK

## Compatibility

The A/B Smartly Swift SDK is supported on macOS version 10.10 or later and iOS version 10 or later.

## Installation

### Swift Package Manager

To install the A/B Smartly SDK using Swift Package Manager, following these steps:

- In Xcode go to: ```File -> Swift Packages -> Add Package Dependency...```

- Enter the A/B Smartly Swift SDK GitHub repository: ```https://github.com/absmartly/swift-sdk```

- Select the SDK version (latest recomended)

- Select the ABSmartly library

### Cocoapods

To install the A/B Smartly SDK with CocoaPods, add the following lines to your `Podfile`:

```ruby
pod "ABSmartly"
```

Run the following command to update your Xcode project:
```
pod install
```

## Getting Started

Please follow the [installation](#installation) instructions before trying the following code:

#### Initialization

This example assumes an Api Key, an Application, and an Environment have already been created in the A/B Smartly web console.
```swift
import ABSmartly
...

let options = ClientOptions(apiKey: "YOUR_ABSMARTLY_API_KEY",
                                    application: "YOUR_APP_NAME",
                                    endpoint: "https://YOUR_SUBDOMAIN.absmartly.io/v1",
                                    environment: "YOUR_ENVIRONMENT")

let sdk = ABSmartlySDK(options)
```

#### Creating a new Context
```swift

let contextConfig: ContextConfig = ContextConfig()
contextConfig.setUnit(unitType: "session_id", uid: "5ebf06d8cb5d8137290c4abb64155584fbdb64d8")

let context = sdk.createContext(config: contextConfig)
context.waitUntilReadyAsync {  context in
    guard let context = context else {
        print("error")
        return
    }

    print("context ready")
}
```

#### Creating a new Context with pre-fetched data
When doing full-stack experimentation with A/B Smartly, we recommend creating a context only once on the server-side.
Creating a context involves a round-trip to the A/B Smartly event collector.
We can avoid repeating the round-trip on the client-side by sending the server-side data embedded in the first document, for example, by rendering it on the template.
Then we can initialize the A/B Smartly context on the client-side directly with it.

```swift
let contextConfig: ContextConfig = ContextConfig()
contextConfig.setUnit(unitType: "session_id", uid: "5ebf06d8cb5d8137290c4abb64155584fbdb64d8")

let context = sdk.createContext(config: contextConfig)
context.waitUntilReadyAsync { context in
    guard let context = context else { return }

    let anotherContextConfig: ContextConfig = ContextConfig()
    anotherContextConfig.setUnit(unitType: "session_id", uid: "5ebf06d8cb5d8137290c4abb64155584fbdb64d8")

    do {
        if let contextData = try context.getContextData() {
            let anotherContext = sdk.createContextWithData(config: anotherContextConfig, contextData: contextData)
        }
    } catch {
        print("error: " + error.localizedDescription)
    }
}
```

#### Setting context attributes
The `setAttribute()` and `setAttributes()` methods can be called before the context is ready.
```swift
try context.setAttribute(name: "decive", value: UIDevice.current.model)
try context.setAttributes(["customer_age": "new_customer", "screenName": "..."])
```

#### Selecting a treatment
```swift

  let treatment = try context.getTreatment("exp_test_experiment")

  if treatment == 0 {
      // user is in control group (variant 0)
  } else {
      // user is in treatment group
  }

```
#### Selecting a treatment variable
```swift

let variable = try context.getVariableValue(key: "my_variable", defaultValue: 10)

```

#### Tracking a goal achievement
Goals are created in the A/B Smartly web console.
```swift

try context.track("payment", properties: ["item_count": 1, "total_amount": 1999.99])

```

#### Publishing pending data
Sometimes it is necessary to ensure all events have been published to the A/B Smartly collector, before proceeding. You can explicitly call the publish() and pass complition block as argument.
```swift

try context.publish { (error: Error?) in
    if let error = error {
        print("Publishing error: " + error.localizedDescription)
        return
    }

    print("Success publish")
}

```

#### Finalizing
The `close()` and  method will ensure all events have been published to the A/B Smartly collector, like `publish()`, and will also "seal" the context, throwing an error if any method that could generate an event is called.
```swift
context.close { (error: Error?) in
    if let error = error {
        print("Closing error: " + error.localizedDescription)
        return
    }

    print("Success closed")
}
```

#### Refreshing the context with fresh experiment data
For long-running contexts, the context is usually created once when the application is first reached.
However, any experiments being tracked in your production code, but started after the context was created, will not be triggered.
To mitigate this, we can use the `refresh()` method.

The `refresh()` method pulls updated experiment data from the A/B Smartly collector and will trigger recently started experiments when `getTreatment()` is called again.
```swift

try context.refresh({ (error: Error?) in
    if let error = error {
        print("Refreshing error: " + error.localizedDescription)
        return
    }

    print("Success refresh")
})

```

#### Peek at treatment variants
Although generally not recommended, it is sometimes necessary to peek at a treatment or variable without triggering an exposure.
The A/B Smartly SDK provides a `peekTreatment()` method for that.

```swift
let treatment = try context.peekTreatment(experimentName: "exp_test_experiment")

if treatment == 0 {
    // user is in control group (variant 0)
} else {
    // user is in treatment group
}
```

##### Peeking at variables
```swift

let color = try context.peekVariableValue(key: "colorGComponent", defaultValue: 255)

```

#### Overriding treatment variants
During development, for example, it is useful to force a treatment for an experiment. This can be achieved with the `override()` and/or `overrides()` methods.
The `setOverride()` and `setOverrides()` methods can be called before the context is ready.
```swift

try context.setOverride(experimentName: "exp_test_experiment", variant: 1)  // force variant 1 of treatment
try context.setOverrides(["exp_test_experiment": 1, "exp_another_experiment": 0])

```

## About A/B Smartly
**A/B Smartly** is the leading provider of state-of-the-art, on-premises, full-stack experimentation platforms for engineering and product teams that want to confidently deploy features as fast as they can develop them.
A/B Smartly's real-time analytics helps engineering and product teams ensure that new features will improve the customer experience without breaking or degrading performance and/or business metrics.

### Have a look at our growing list of clients and SDKs:
- [Java SDK](https://www.github.com/absmartly/java-sdk)
- [JavaScript SDK](https://www.github.com/absmartly/javascript-sdk)
- [PHP SDK](https://www.github.com/absmartly/php-sdk)
- [Vue2 SDK](https://www.github.com/absmartly/vue2-sdk)
