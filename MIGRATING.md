# Migrating from 1.x to 2.0

2.0 is a new API over the 1.5.0 engine (a parity test replays recorded output against 2.0).
Ordinary assignments, exposures, goals and publishing retain their behaviour; extreme unsigned
numbers have the rounding differences listed under **Behaviour notes** below. The API changes:

- `async`/`await` instead of PromiseKit.
- Swift 6 strict concurrency: every public type is `Sendable`.
- `JSONValue` instead of SwiftyJSON's `JSON`.
- No third-party dependencies linked on Apple platforms (PromiseKit, SwiftyJSON and swift-atomics are gone; swift-crypto is linked on Linux only).
- The module is `ABsmartly` (was `ABSmartly`) and the entry type is `ABsmartlyClient`.
- Minimum iOS 15, macOS 12, tvOS 15, watchOS 8 (1.x: iOS 10). Swift 6.0 / Xcode 16 to build.

**Coming from 1.4.x?** 2.0's behaviour is 1.5.0's, so you also get every 1.5.0 behaviour change
(system attributes in audiences, shared variable keys, publish/close failure handling, custom field
typing, `X-Application-Version` normalisation and more). Read the 1.5.0 **BREAKING** and **Changed**
sections of [CHANGELOG.md](CHANGELOG.md) first; the easiest path is to upgrade to 1.5.0, check your
experiments, then move to 2.0.

1.x stays supported on the `release/1.x` branch (see [SUPPORT.md](SUPPORT.md)). You cannot use 1.x
and 2.x in the same app: a Swift package graph holds one major version of a package.

## Step by step

1. Update the dependency: `from: "2.0.0"` in SwiftPM (product `ABsmartly`), or `pod 'ABsmartly', '~> 2.0'`
   (the 1.x pod was `ABSmartlySwiftSDK`).
2. Replace `import ABSmartly` with `import ABsmartly`, and remove `import PromiseKit` and
   `import SwiftyJSON` if you only used them for the SDK.
3. Replace the SDK setup and context creation (below).
4. Rename the calls using the table. The compiler finds every one.
5. Replace `JSON` with `JSONValue`, or better, with typed `variable(_:default:)` reads.
6. Replace your `ContextEventLogger` with an `EventLogger` closure or `context.events`.

## Setup

Before (1.x):

```swift
import ABSmartly

let sdk = try ABsmartlySDK(
    endpoint: "https://your-company.absmartly.io/v1",
    apiKey: apiKey,
    application: "website",
    environment: "production")

let config = ContextConfig()
config.setUnit(unitType: "device_id", uid: deviceID)
config.setAttribute(name: "plan", value: JSON("pro"))
let context = sdk.createContext(config: config)
context.waitUntilReady().done { context in
    let variant = context.getTreatment("exp_checkout")
}
```

After (2.0):

```swift
import ABsmartly

let client = try ABsmartlyClient(
    endpoint: URL(string: "https://your-company.absmartly.io/v1")!,
    apiKey: apiKey,
    application: "website",
    environment: .production)

let context = try await client.context(
    units: [.deviceID: deviceID],
    attributes: ["plan": "pro"])
let variant = context.treatment(for: "exp_checkout")
```

## Every 1.x API and its 2.0 equivalent

### SDK and configuration

| 1.x | 2.0 |
|---|---|
| `ABsmartlySDK` / `ABSmartlySDK` / `AbsmartlySDK` | `ABsmartlyClient` |
| `ABsmartlySDK(endpoint:apiKey:application:environment:applicationVersion:timeout:retries:contextEventLogger:...)` | `ABsmartlyClient(endpoint:apiKey:application:environment:applicationVersion:eventLogger:)`; `timeout`/`retries` on `ABsmartlyClient.Configuration` |
| `ABsmartlySDK(config: ABsmartlyConfig)` | `ABsmartlyClient(configuration: ABsmartlyClient.Configuration)` |
| `ABsmartlyConfig` / `ABSmartlyConfig` / `AbsmartlyConfig` | `ABsmartlyClient.Configuration` |
| `ABsmartlyConfig.contextEventLogger` | `Configuration.eventLogger` |
| `ABsmartlyConfig.contextDataProvider`, `.contextPublisher`, `.contextEventHandler`, `.client` | `Configuration.transport` (a custom `Transport`); the SDK keeps building and decoding the requests |
| `ABsmartlyConfig.variableParser`, `VariableParser`, `DefaultVariableParser` | Removed: variant configs are parsed as JSON objects (1.x's default). Decode variables into your own types with `variable(_:default:)` |
| `ABsmartlyConfig.scheduler`, `Scheduler`, `DefaultScheduler`, `ScheduledHandle`, `DefaultScheduledHandle` | Removed: timers are internal `Task`s |
| `ClientConfig(apiKey:application:endpoint:environment:applicationVersion:)` | `ABsmartlyClient.Configuration(endpoint:apiKey:application:environment:)` + `.applicationVersion` |
| `ClientConfig(from: Data)` (plist), `ClientConfig(from: [String: String])` | Removed: build a `Configuration` from your own plist values |
| `Client`, `DefaultClient(config:)`, `DefaultClient(config:httpClient:)` | `ABsmartlyClient` (+ `Configuration.transport`) |
| `Client.getApplication()`, `.getEnvironment()` | `client.configuration.application`, `.environment` |
| `HTTPClient`, `DefaultHTTPClient`, `Response`, `DefaultHTTPResponse` | `Transport`, `URLSessionTransport`, `HTTPRequest`, `HTTPResponse` |
| `DefaultHTTPClientConfig.connectionRequestTimeout` / `.connectionResourceTimeout` | `Configuration.timeout` |
| `DefaultHTTPClientConfig.retries`, `.retryInterval` | `Configuration.retries`, `.retryInterval` |
| `ContextDataProvider`, `DefaultContextDataProvider` | `client.fetchContextData()`, or a custom `Transport` |
| `ContextPublisher`, `ContextEventHandler`, `DefaultContextPublisher`, `DefaultContextEventHandler` | A custom `Transport` (handles the `PUT`) |
| `sdk.getContextData()` (Promise) | `try await client.fetchContextData()` |
| `sdk.close()` | Not needed: the client owns no resources beyond its `URLSession` |
| `Clock`, `DefaultClock` | Removed (internal) |
| `Hashing.hash(_:)`, `Hashing.utf8Bytes`, `Hashing.base64UrlNoPadding`, `MurmurHash` | Removed (internal) |
| `AudienceMatcher`, `JsonExpr` | Removed (internal) |

### Creating a context

| 1.x | 2.0 |
|---|---|
| `sdk.createContext(config:)` + `waitUntilReady()` | `try await client.context(units:attributes:overrides:customAssignments:options:)` |
| `sdk.createContext(config:)` (not awaited) | `client.makeContext(units:...)`, then `try await context.ready()` |
| `sdk.createContextWithData(config:contextData:)` | `client.context(units:..., data:)` |
| `ContextConfig()` | Parameters of `context(...)` and `Context.Options` |
| `ContextConfig.setUnit(unitType:uid:)` (String, Int, Double), `.setUnit(unitType:value:)`, `.setUnits(units:)` | `units: [UnitType: String]`; numeric UIDs with `context.setUnit(_:to:)` |
| `ContextConfig.setAttribute(name:value:)`, `.setAttributes(attributes:)` | `attributes: [String: JSONValue]` |
| `ContextConfig.setOverride(experimentName:variant:)`, `.setOverrides(overrides:)` | `overrides: [String: Int]` |
| `ContextConfig.setCustomAssignment(experimentName:variant:)`, `.setCustomAssignments(assignments:)` | `customAssignments: [String: Int]` |
| `ContextConfig.publishDelay`, `.refreshInterval`, `.eventLogger` | `Context.Options(publishDelay:refreshInterval:eventLogger:)` |

### Context lifecycle

| 1.x | 2.0 |
|---|---|
| `context.waitUntilReady()` (Promise) | `try await context.ready()` |
| `isReady()` | `context.state.isSettled` (ready or failed), or `context.state == .ready` |
| `isFailed()` | `if case .failed = context.state` |
| `readyError()` | `if case .failed(let error) = context.state` |
| `isClosing()` / `isFinalizing()` | `context.state == .closing` |
| `isClosed()` / `isFinalized()` | `context.state == .closed` |
| `publish()` (Promise) | `try await context.publish()` |
| `refresh()` (Promise) | `try await context.refresh()` |
| `close()` / `finalize()` (Promise) | `try await context.close()` |
| `getPendingCount()` (UInt) | `context.pendingEventCount` (Int) |

### Reads

| 1.x | 2.0 |
|---|---|
| `getTreatment(_:)` | `treatment(for:)` |
| `peekTreatment(_:)` | `treatment(for:exposing: false)` |
| `getVariableValue(_:defaultValue:) -> JSON?` | `variable(_:default:) -> T` (typed), or `variableValue(_:) -> JSONValue?` |
| `peekVariableValue(_:defaultValue:)` | `variable(_:default:exposing: false)`, `variableValue(_:exposing: false)` |
| `getVariableKeys()` | `variableKeys` |
| `getExperiments()` | `experiments` |
| `getContextData()` | `contextData` |
| `getCustomFieldValue(experimentName:key:) -> Any?` | `customFieldValue(_:in:) -> JSONValue?` |
| `getCustomFieldValueType(experimentName:key:)` | `customFieldType(_:in:)` |
| `getCustomFieldKeys(experimentName:)` | `customFieldKeys(in:)` |
| `getCustomFieldKeys()` | `customFieldKeys` |

### Units, attributes, overrides, goals

| 1.x | 2.0 |
|---|---|
| `setUnit(unitType:uid:)` (String/Int/Double), `setUnit(unitType:value:)` | `try setUnit(_:to:)` (String/Int/Double); throws instead of only logging |
| `setUnits(_:)` | `try setUnits(_:)` |
| `getUnit(unitType:)`, `getUnits()` | `units[unitType]`, `units` |
| `getUnitValue(unitType:)`, `getUnitValues()` | `unitValues[unitType]`, `unitValues` |
| `setAttribute(name:value:)` | `setAttribute(_:to:)` (any `JSONValueConvertible`) |
| `setAttributes(_:)` | `setAttributes(_:)` |
| `getAttribute(name:)`, `getAttributes()` | `attribute(_:)`, `attributes` |
| `setOverride(experimentName:variant:)`, `getOverride(experimentName:)` | `setOverride(variant, for: name)` (atomic), `overrides[name]` |
| `setOverrides(_:)` | `setOverrides(_:)` |
| `setCustomAssignment(experimentName:variant:)`, `getCustomAssignment(experimentName:)` | `setCustomAssignment(variant, for: name)` (atomic), `customAssignments[name]` |
| `setCustomAssignments(_:)` | `setCustomAssignments(_:)` |
| `track(_:properties: [String: JSON]?)` | `track(_:properties: [String: JSONValue]?)` |

### Events

| 1.x | 2.0 |
|---|---|
| `ContextEventLogger.handleEvent(context:event:)` | `EventLogger { context, event in }` (`@Sendable` closure), or `for await event in context.events` |
| `ContextEventLoggerEvent` | `Context.Event` |
| `.ready(data:)`, `.refresh(data:)` | `.ready(ContextData)`, `.refresh(ContextData)` |
| `.publish(event:)`, `.exposure(exposure:)`, `.goal(goal:)` | `.publish(PublishEvent)`, `.exposure(Exposure)`, `.goal(Goal)` |
| `.close` / `.finalize` | `.close` |
| `.error(error: Error)` | `.error(ABsmartlyError)` |

Delivery threads are unchanged: `exposure`, `goal` and `error` on the calling thread; `ready`,
`refresh`, `publish` and `close` on the main thread on Apple platforms.

### Models and values

| 1.x | 2.0 |
|---|---|
| `JSON` (SwiftyJSON) | `JSONValue` (`.string`, `.int`, `.double`, `.bool`, `.array`, `.object`, `.null`; literal-expressible) |
| `json.string`, `json.int`, `json.double`, `json.bool`, `json.array`, `json.dictionary` | `stringValue`, `intValue`, `doubleValue`, `boolValue`, `arrayValue`, `objectValue` |
| `json["key"]`, `json[0]` | `value["key"]`, `value[0]` (optional) |
| `ContextData` (class) | `ContextData` (struct) |
| `Experiment`, `ExperimentVariant`, `CustomFieldValue` | Same names, now structs with public initializers; `applications` and `customFieldValues` are non-optional (empty when absent) |
| `Application` | `ExperimentApplication` |
| `Exposure`, `PublishEvent` | Same names (structs) |
| `GoalAchievement` | `Goal` |
| `Unit`, `Attribute` (publish payload) | `PublishEvent.Unit`, `PublishEvent.Attribute` |
| `ABSmartlyError` (class, `errorMessage`) | `ABsmartlyError` (enum); `localizedDescription` keeps the 1.x messages |

## Behaviour notes

Assignment and publishing retain 1.5.0 behaviour apart from these extreme-number differences
(see also the note for 1.4.x users at the top):

- `UInt64`/`UInt` attributes above `Int64.max` are stored as doubles: `12345678901234567890` is
  published as `1.2345678901234567e+19`, not the exact integer. String operators see the double's
  text, rather than 1.5.0's exact `NSNumber` formatting.
- Unsigned integer literals from 2^63 to 2^64−1 in audiences/rules are also doubles. Neighbouring
  values can compare equal inside collections and string operators can see different text.
  Decimal-parsed literals still retain their exact nested-comparison and truthiness semantics.
  See [the design's numeric differences](docs/plans/swift-2.0.md#known-20-difference-from-150).

These API-level differences are also worth knowing:

- `setUnit` throws as well as emitting the `.error` event (1.x only emitted it). The unit is left
  unchanged, as before.
- `customFieldValue(_:in:)` returns `JSONValue?` for every field type: `number` fields are
  `.double`, `boolean` fields `.bool`, `json` fields the parsed value (objects included; 1.x returned
  `[String: JSON]` for objects), text fields `.string`.
- `client.context(units:...)` (the awaited form) throws when the data cannot be fetched instead of
  returning a failed context. Use `makeContext` to keep the failed context (reads return defaults).
- A custom `VariableParser` can no longer change how variant configs are parsed.
