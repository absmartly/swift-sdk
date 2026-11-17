# ABsmartly Swift SDK <a href="https://github.com/apple/swift-package-manager" title="Swift Package Manager compatible"><img src="https://img.shields.io/badge/Swift%20Package%20Manager-compatible-brightgreen.svg" alt="Swift Package Manager compatible" /></a>

The ABsmartly SDK for iOS, macOS, tvOS, watchOS, visionOS and Linux: `async`/`await`, Swift 6 strict
concurrency (every public type is `Sendable`) and no third-party dependencies.

> **Using 1.x?** This is 2.x. The 1.x line (module `ABSmartly`, PromiseKit API) is maintained on the
> [`release/1.x`](https://github.com/absmartly/swift-sdk/tree/release/1.x) branch, with bug fixes
> for 12 months after 2.0.0 (see [SUPPORT.md](SUPPORT.md)). To move to 2.x, follow
> [MIGRATING.md](MIGRATING.md).

## Compatibility

| Platform | Minimum |
|---|---|
| iOS / iPadOS | 15.0 |
| macOS | 12.0 |
| Mac Catalyst | 15.0 |
| tvOS | 15.0 |
| watchOS | 8.0 |
| visionOS | 1.0 |
| Linux | Swift 6.0 |

Building needs Swift 6.0 or later (Xcode 16 or later).

## Installation

### Swift Package Manager

```swift
dependencies: [
    .package(url: "https://github.com/absmartly/swift-sdk.git", from: "2.0.0")
],
targets: [
    .target(name: "App", dependencies: [
        .product(name: "ABsmartly", package: "swift-sdk"),
        // Optional: SwiftUI property wrappers
        .product(name: "ABsmartlyUI", package: "swift-sdk"),
    ])
]
```

In Xcode: **File → Add Package Dependencies…**, enter `https://github.com/absmartly/swift-sdk.git`
and choose the `ABsmartly` (and optionally `ABsmartlyUI`) product.

### CocoaPods

```ruby
pod 'ABsmartly', '~> 2.0'        # core
pod 'ABsmartly/UI', '~> 2.0'     # with the SwiftUI property wrappers
```

The CocoaPods trunk stops accepting new versions on 2026-12-02. Releases after that are published
for Swift Package Manager only.

## Getting started

### Initialization

```swift
import ABsmartly

let client = try ABsmartlyClient(
    endpoint: URL(string: "https://your-company.absmartly.io/v1")!,
    apiKey: apiKey,
    application: "website",
    environment: .production
)
```

Create one client and keep it for the lifetime of the app. It is `Sendable`, so you can share it
between tasks and actors.

#### Advanced configuration

```swift
var configuration = ABsmartlyClient.Configuration(
    endpoint: URL(string: "https://your-company.absmartly.io/v1")!,
    apiKey: apiKey,
    application: "website",
    environment: "staging")
configuration.applicationVersion = "1042"
configuration.timeout = 3
configuration.retries = 3
configuration.transport = transport
configuration.eventLogger = .custom { context, event in
    print("ABsmartly event: \(event)")
}
let client = try ABsmartlyClient(configuration: configuration)
```

`transport` is any type conforming to `Transport` (one `async` method that sends an `HTTPRequest`).
Use it to route requests through your own networking stack; the SDK still builds the requests,
retries and decodes the responses.

## Creating a context

There are three ways to create a context:

```swift
// 1. Await until ready (common case); throws if the context data can't be fetched
let context = try await client.context(units: [.deviceID: deviceID])

// 2. Create now, wait later (e.g. start at launch, await before the first screen needs it)
let context = client.makeContext(units: [.deviceID: deviceID])
try await context.ready()

// 3. Pre-fetched data from your server: synchronous, ready immediately
let context = client.context(units: [.deviceID: deviceID], data: contextData)
```

`contextData` is a `ContextData` (it is `Codable`): fetch it on your server, or with
`try await client.fetchContextData()`.

All three take the same optional arguments:

```swift
let context = try await client.context(
    units: [.deviceID: deviceID, .userID: "user-42"],
    attributes: ["plan": "pro", "age": 42],
    overrides: ["exp_banner": 1],
    options: Context.Options(publishDelay: 0.1, refreshInterval: 300)
)
```

Unit types are `UnitType` values: `.deviceID`, `.userID`, `.sessionID`, or any string literal
(`"email"`).

### Synchronous reads, asynchronous network

- **Reads stay synchronous**: `treatment(for:)`, `variable(_:default:)`, `track(_:properties:)` and
  the other reads never `await`, so you can call them from a SwiftUI `body`, a table view cell or any
  thread.
- **Network calls are `async`**: `ready()`, `refresh()`, `publish()` and `close()`.
- **`Context` is `Sendable`**: store it in a `@MainActor` view model or pass it into a `Task` without
  warnings in Swift 6.

```swift
@MainActor
final class CheckoutModel: ObservableObject {
    @Published var showExpressCheckout = false
    private let context: Context

    init(context: Context) {
        self.context = context
        showExpressCheckout = context.treatment(for: "exp_checkout") == 2
    }

    func purchase(total: Double) {
        context.track("purchase", properties: ["total": .double(total)])
        Task { try? await context.publish() }
    }
}
```

### State

```swift
switch context.state {
case .loading: print("loading")
case .ready: print("ready")
case .failed(let error): print("failed: \(error)")
case .closing, .closed: print("closed")
}
```

A context whose data could not be fetched is `.failed`: its reads return the control variant and
the defaults, and it publishes nothing.

## Basic usage

### Treatments

```swift
let variant = context.treatment(for: "exp_checkout")
if variant == 1 {
    // show the new checkout
}
```

The first read of an experiment queues an exposure, which is published automatically. To read
without exposing ("peek"):

```swift
let peeked = context.treatment(for: "exp_checkout", exposing: false)
```

Helpers:

```swift
if context.isInTreatment("exp_checkout") {
    // variant != 0
}
let style = context.treatment(for: "exp_checkout", as: CheckoutVariant.self)   // enum CheckoutVariant: Int
```

### Variables

```swift
let color: String = context.variable("button.color", default: "blue")
let limit = context.variable("cart.limit", default: 10)
let config: CheckoutConfig = context.variable("checkout", default: .standard)   // any Decodable
let raw: JSONValue? = context.variableValue("checkout")
```

Reading a variable exposes the experiment that provides it. Pass `exposing: false` to peek.

### Overrides

Overrides force a variant, for example in QA builds. Set them at creation, one at a time, or several
at once:

```swift
let context = client.context(
    units: [.deviceID: deviceID], overrides: ["exp_checkout": 1, "exp_banner": 2], data: contextData)
context.overrides["exp_checkout"] = 2
context.setOverrides(["exp_banner": 1, "exp_search": 2])
context.overrides["exp_banner"] = nil
context.customAssignments["exp_search"] = 1
```

### Attributes and units

```swift
context.setAttribute("plan", to: "pro")
context.setAttributes(["age": 42, "country": "PT"])
try context.setUnit(.userID, to: "user-42")
```

Audiences and assignment rules evaluate the attributes, plus the configured `application` and
`environment` names (an attribute you set with the same name wins). `setUnit` throws
`ABsmartlyError.blankUnitUID`, `.unitAlreadySet` or `.closed`, and leaves the unit unchanged.

### Goals

```swift
context.track("purchase", properties: ["total": 19.99, "items": 2])
```

### Publishing, refreshing and closing

```swift
try await context.publish()
try await context.refresh()
try await context.close()
```

Exposures and goals are published `publishDelay` seconds after they are queued (0.1 s by default; a
negative value disables it). `close()` publishes whatever is pending; call it when the user's session
ends. A failed publish keeps the events queued for the next one.

## Events

```swift
for await event in context.events {
    switch event {
    case .ready: seen.append("ready")
    case .exposure(let exposure): seen.append("exposure \(exposure.name)")
    case .goal(let goal): seen.append("goal \(goal.name)")
    case .error(let error): seen.append("error \(error)")
    case .refresh, .publish: break
    case .close: seen.append("close")
    }
}
```

Each access to `context.events` returns a new stream, which finishes after the context closes. To
see the events of every context, set `configuration.eventLogger` (`.osLog` writes them to the unified
log).

## Errors

The `async` APIs throw `ABsmartlyError` (typed throws), so `catch` sees the cases directly:

```swift
do {
    let context = try await client.context(units: [.deviceID: deviceID])
    _ = context.treatment(for: "exp_checkout")
} catch .httpStatus(let code, _) {
    print("ABsmartly is unavailable (\(code)); using defaults")
} catch {
    print("ABsmartly failed: \(error.localizedDescription)")
}
```

Reads never throw. A read before the context is ready, or after it is closed, returns the default
and emits an `.error` event.

## SwiftUI

The `ABsmartlyUI` product adds property wrappers that read the context from the environment:

```swift
import ABsmartlyUI

RootView().absmartlyContext(context)

struct CheckoutButton: View {
    @Treatment("exp_checkout") var variant
    @Variable("button.color", default: "blue") var color: String

    var body: some View {
        Button(variant == 1 ? "Buy now" : "Buy") {}
    }
}
```

Views re-render when the context becomes ready or refreshes. Without a context, or before it is
ready, the wrappers return `0` and the default.

Every snippet in this README is compiled by `Tests/ABsmartlyUITests/DocSnippetTests.swift`.

## About ABsmartly

**ABsmartly** is the leading provider of state-of-the-art, on-premises, full-stack experimentation platforms for engineering and product teams that want to confidently deploy features as fast as they can develop them.
ABsmartly's real-time analytics helps engineering and product teams ensure that new features will improve the customer experience without breaking or degrading performance and/or business metrics.

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
