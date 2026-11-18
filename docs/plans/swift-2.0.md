# ABsmartly Swift SDK 2.0

Status: design approved by the owner on 2026-11-17 (every decision below is final unless marked
otherwise). Implementation lands on `feat/swift-2.0`.

## Why

A customer's iOS team ships Swift 6 apps with strict concurrency. 1.x gets in their way:

- The public API returns PromiseKit promises. They want `async`/`await`.
- 1.x types are not `Sendable`, so every use of a `Context` from a `Task` or a `@MainActor` view
  model is a strict-concurrency diagnostic.
- `JSON` is SwiftyJSON, which is unmaintained (and does not compile on Linux; 1.5.0 vendors it).

1.5.0 (branch `release/1.5.0-prep`) stays source compatible and adds `async` overloads next to the
PromiseKit API. 2.0 is the modern API: idiomatic Swift, `Sendable` throughout, no third-party
dependencies, and **the same assignment and event behaviour as 1.5.0** (javascript-sdk is the
reference, cross-sdk-tests the conformance corpus).

## Goals and non-goals

Goals:
- An API that reads like an Apple framework (API Design Guidelines naming, properties instead of
  `getX()`, `async throws` for I/O, typed errors).
- Swift 6 language mode, `-strict-concurrency=complete`, warnings as errors, every public type
  `Sendable`.
- No dependencies on Apple platforms. `swift-crypto` on Linux only (for MD5, which CryptoKit
  provides on Apple platforms).
- Behaviour parity with 1.5.0, proven by replaying recorded 1.5.0 output (see *Parity*).

Non-goals:
- Source compatibility with 1.x. There is no compat shim; `MIGRATING.md` maps every 1.x API.
- Behaviour changes. 2.0 is a re-architecture; contract fixes go to both lines together.

## Decisions (owner, 2026-11-17)

| # | Decision |
|---|---|
| 1 | Modern idiomatic API (this document), not a port of the 1.x/Java shape. |
| 2 | Brand spelling `ABsmartly` everywhere, never `ABSmartly`. Package, product, module and CocoaPods pod are all `ABsmartly`. The entry type is `ABsmartlyClient`; no type is named like the module (a type named `ABsmartly` would shadow the module, so `ABsmartly.Context` would stop resolving, and it breaks generated `.swiftinterface` files). No type prefixes: the module is the namespace. |
| 3 | Overrides: an `overrides` dictionary property, `setOverrides(_:)` for several at once, and overrides at context creation. The same shape for custom assignments. |
| 4 | Platform floor iOS 15, macOS 12, tvOS 15, watchOS 8 (and visionOS 1, Mac Catalyst 15). |
| 5 | `Context` is a `Sendable` final class with internal locking and synchronous reads, not an actor. |
| 6 | SwiftUI property wrappers (`@Treatment`, `@Variable`, `.absmartlyContext(_:)`) ship with 2.0 in a separate `ABsmartlyUI` product, so the core has no SwiftUI dependency. |
| 7 | No 1.x compat shim; `MIGRATING.md` only. |
| 8 | 1.x is supported for 12 months after 2.0 ships. |

### Remaining owner/release items

- **Nested boolean/number equality (behaviour).** 2.0 keeps 1.5.0's per-platform result (see
  *Known 1.5.0 divergences*): on Apple platforms `[true]` equals `[1]` inside an audience or rule,
  on Linux and in javascript-sdk it does not. Recommendation: keep 1.5.0 parity in 2.0.0 and change
  both lines to the JS behaviour together, so no app sees it move on the major upgrade alone.

These are release logistics, not API questions:

- **CocoaPods.** The CocoaPods trunk becomes read-only on **2026-12-02**: no new pods or versions
  can be pushed after that. The podspec (`ABsmartly.podspec`, pod `ABsmartly` 2.0.0) is kept and
  linted in CI, but a 2.0 pod can only reach trunk if 2.0 is tagged before that date. Afterwards
  2.0 is SwiftPM-only (CocoaPods users can still point a `:git` pod at the tag). The publish
  workflow's trunk step is unchanged; it will fail after the freeze, which is the visible signal.
- **Merge order.** `release/1.x` is cut from the `v1.5.0` tag; this PR merges into `main` only after
  1.5.0 ships. cross-sdk-tests' swift lane is pinned to `feat/swift-2.0` while this PR is open and
  must be re-pinned to `main` after merge.

## Coexistence with 1.x (owner policy 2026-11-17)

Both majors live in this repository, on branches:

- `main` is 2.x once 2.0 merges; tags `v2.*`. This branch (`feat/swift-2.0`) is the `next/major`
  work in progress.
- `release/1.x` is cut by the owner from the last 1.x tag (`v1.5.0`) when 2.0 merges; tags `v1.*`.
  Bug fixes only, for 12 months after 2.0.0 ships (`SUPPORT.md`).
- Fix flow: fix on `main` first, cherry-pick to `release/1.x` during the window; 1.x-only bugs go
  straight to `release/1.x`.
- CI runs on pushes and pull requests to `main` and `release/**`; a `v*` tag publishes, after the
  tag == podspec == `SDKVersion` check. The same workflow files go to `release/1.x` in a separate
  small PR once the owner has cut it.
- Registries: 2.x is the pod and module `ABsmartly`; 1.x keeps pod `ABSmartlySwiftSDK` and module
  `ABSmartly`, so the two never collide. GitHub releases for `v1.*` tags are created with
  `--latest=false`, so a 1.x patch never becomes the latest release.
- cross-sdk-tests runs a `swift` lane on this branch (2.x wrapper) and a `swift-v1` lane on 1.x
  (`release/1.x`, or `main` until that branch exists) for the whole window.
- A SwiftPM graph resolves one major version of a package, so an app cannot link 1.x and 2.x at the
  same time. The module rename (`ABSmartly` to `ABsmartly`) therefore costs nothing extra and makes
  the migration explicit: every `import ABSmartly` becomes `import ABsmartly`.

## Public API

### Setup

```swift
import ABsmartly

let client = try ABsmartlyClient(
    endpoint: URL(string: "https://acme.absmartly.io/v1")!,
    apiKey: apiKey,
    application: "ios",
    environment: .production       // ABsmartlyClient.Environment: ExpressibleByStringLiteral
)
```

`ABsmartlyClient.Configuration` (a `Sendable` struct) replaces `ClientConfig`, `ABsmartlyConfig`,
`DefaultHTTPClientConfig`, `Client`/`DefaultClient`, `ContextDataProvider` and `ContextPublisher`:

```swift
var configuration = ABsmartlyClient.Configuration(
    endpoint: url, apiKey: apiKey, application: "ios", environment: "staging")
configuration.applicationVersion = "1042"   // sent as X-Application-Version (normalised as in 1.5.0)
configuration.timeout = 3                    // seconds, per request (1.x default)
configuration.retries = 3                    // retries on 502/503 and transport errors (1.x default)
configuration.retryInterval = 0.5
configuration.transport = MyTransport()      // any Transport; URLSessionTransport by default
configuration.eventLogger = .osLog           // or .custom { context, event in ... }
let client = try ABsmartlyClient(configuration: configuration)
```

`init` throws `ABsmartlyError.invalidConfiguration` for an empty API key, application or
environment, with the 1.x messages.

`Transport` is the single extension point for networking:

```swift
public protocol Transport: Sendable {
    func send(_ request: HTTPRequest) async throws -> HTTPResponse
}
```

It replaces 1.x's `HTTPClient`, `ContextDataProvider` and `ContextPublisher`: a proxy, an offline
queue, a test double or a different HTTP stack is a `Transport`. Retries, status handling, headers
and (de)serialisation stay in the SDK, so a custom transport cannot change the wire contract by
accident.

### Creating a context

```swift
// 1. Await until ready (common case); throws if the context data can't be fetched.
let context = try await client.context(units: [.deviceID: deviceID])

// 2. Create now, wait later (e.g. start at launch, await before the first screen needs it).
let context = client.makeContext(units: [.deviceID: deviceID])
try await context.ready()

// 3. Pre-fetched data from your server: synchronous, ready immediately.
let context = client.context(units: [.deviceID: deviceID], data: contextData)
```

All three take the same optional parameters:

```swift
let context = try await client.context(
    units: [.deviceID: deviceID, "user_id": userID],   // [UnitType: String]
    attributes: ["plan": "pro", "age": 42],            // [String: JSONValue]
    overrides: ["exp_banner": 1],
    customAssignments: ["exp_search": 2],
    options: Context.Options(publishDelay: 0.1, refreshInterval: 0, eventLogger: nil)
)
```

- `UnitType` is a `RawRepresentable` string struct with `.deviceID`, `.userID`, `.sessionID` and
  string-literal conversion. It is not called `Unit`: Foundation already has a `Unit` class, and
  the two would be ambiguous in every file that imports both.
- Numeric unit UIDs keep 1.5.0's behaviour (hashed like JS `toFixed(0)`) through
  `setUnit(_:to: Int)` / `setUnit(_:to: Double)`.
- `ContextData` is a public `Codable` struct, so data fetched by your own server decodes with
  `JSONDecoder`. `client.fetchContextData()` fetches it with the SDK's own request.

### Lifecycle and state

```swift
context.state            // Context.State: .loading, .ready, .failed(ABsmartlyError), .closing, .closed
try await context.ready()     // returns when ready; throws the load error if it failed
try await context.refresh()   // fetch new experiment data
try await context.publish()   // send pending exposures and goals now
try await context.close()     // publish what is pending and close; idempotent
context.pendingEventCount
```

The lifecycle is the 1.5.0 lifecycle: a failed publish re-queues its events; a failed `close()`
throws and leaves the context open with its events queued, so `publish()`/`close()` can retry;
`refresh()` on a failed context succeeds without fetching; `publish()` and `refresh()` work before
the context is ready; a negative `publishDelay` disables automatic publishing.

### Treatments and variables (the hot path)

Reads are synchronous and safe from any thread, including a SwiftUI `body`:

```swift
let variant = context.treatment(for: "exp_checkout")                    // Int; queues an exposure
let peeked  = context.treatment(for: "exp_checkout", exposing: false)   // replaces peekTreatment
if context.isInTreatment("exp_checkout") { ... }                        // variant != 0
let style = context.treatment(for: "exp_checkout", as: CheckoutVariant.self)   // RawValue == Int

let color: String = context.variable("button.color", default: "blue")
let limit = context.variable("cart.limit", default: 10)
let config: CheckoutConfig = context.variable("checkout", default: .standard)  // any Decodable
let raw: JSONValue? = context.variableValue("checkout")                  // untyped
let keys = context.variableKeys                                          // [String: [String]]
```

`variable(_:default:)` decodes the variant's value into `T: Decodable & Sendable`. `String`, `Int`,
`Double`, `Bool` and `JSONValue` take a fast path without a decoder. A value that does not decode
returns the default (and still exposes, as the 1.x `getVariableValue` did when the key existed).

Reads before the context is ready, or after it is closed, return the default (`0`, the `default:`
argument, `nil`, empty collections) and emit an `.error` event with the 1.5.0 message, exactly as
1.5.0 does. They do not throw: a `throws` on the hot path would force `try` into every view body.

### Units, attributes, overrides, custom assignments

```swift
try context.setUnit(.userID, to: userID)          // throws ABsmartlyError.unitAlreadySet / .blankUnitUID / .closed
context.units                                      // [UnitType: String]

context.setAttribute("plan", to: "pro")            // any JSONValueConvertible: String, Int, Double, Bool, arrays, dictionaries, JSONValue
context.setAttributes(["plan": "pro", "age": 42])
context.attributes                                 // [String: JSONValue], latest value per name

context.setOverride(1, for: "exp_checkout")         // one override, atomic
context.setOverrides(["exp_banner": 1, "exp_search": 2])   // several at once, atomically
context.setOverride(nil, for: "exp_banner")         // remove one
context.setCustomAssignment(2, for: "exp_checkout")
context.overrides                                  // [String: Int] snapshot; assignable (last writer wins)
context.setCustomAssignments(["exp_banner": 1])
```

`setUnit` is the one mutation that throws: its failures (a blank UID, a changed UID, a closed
context) are programming errors the caller can act on, and the 1.5.0 behaviour that is kept is that
the unit is left unchanged. `setAttribute` and `track` after close are ignored and emit an `.error`
event, as in 1.5.0, so they can be called from UI code without `try`. Overrides and custom
assignments are accepted after close, as in 1.5.0.

Assigning the `overrides`/`customAssignments` properties (including `overrides[key] = value`) reads
a snapshot and writes the whole dictionary back in a second critical section: last writer wins, and
the caller's expression (which may read the context) runs outside the lock. For atomic updates use
`setOverride(_:for:)`/`setOverrides(_:)` and `setCustomAssignment(_:for:)`/`setCustomAssignments(_:)`.

### Goals

```swift
context.track("purchase", properties: ["total": 19.99, "items": 2])
```

### Custom fields

```swift
context.customFieldValue("owner", in: "exp_checkout")      // JSONValue?
context.customFieldType("owner", in: "exp_checkout")       // String? ("json", "number", ...)
context.customFieldKeys(in: "exp_checkout")                // [String]
context.customFieldKeys                                     // Set<String>, across experiments
```

Values follow the 1.5.0 typing: `json` fields are parsed (objects, arrays and scalars), `number`
fields are numbers, `boolean` fields are `true` only for `"true"`, anything else is a string.

### Events

```swift
for await event in context.events {          // AsyncStream<Context.Event>, one stream per access
    switch event {
    case .ready(let data), .refresh(let data): ...
    case .exposure(let exposure): ...
    case .goal(let goal): ...
    case .publish(let event): ...
    case .close: ...
    case .error(let error): ...
    }
}
```

A global hook is configured once:

```swift
configuration.eventLogger = .osLog                          // os.Logger, subsystem "com.absmartly.sdk"
configuration.eventLogger = .custom { context, event in }   // @Sendable closure
```

- The logger is called outside the context's lock, so it may call back into the context. Threads
  are those of 1.5.0: `exposure`, `goal` and `error` on the calling thread, synchronously;
  `ready`, `refresh`, `publish` and `close` on the main thread on Apple platforms (so a logger may
  touch UIKit), and on the completing thread on Linux. The handler is `@Sendable` either way.
- Events, their order and their payloads are those of 1.5.0. `close` is the close event (1.x's
  `finalize` alias is dropped).
- Every stream finishes after the `close` event. `events` read after close returns a finished
  stream. Streams buffer without a limit; a stream nobody iterates is released when its iterator
  task ends or the stream is deallocated.

### Errors

```swift
public enum ABsmartlyError: Error, Sendable, Equatable, LocalizedError {
    case invalidConfiguration(String)     // "Missing APIKey configuration", ...
    case notReady                         // "ABsmartly Context is not yet ready."
    case closing                          // "ABsmartly Context is finalizing."
    case closed                           // "ABsmartly Context is finalized."
    case blankUnitUID(unitType: String)   // "Unit 'x' UID must not be blank."
    case unitAlreadySet(unitType: String) // "Unit 'x' UID already set."
    case httpStatus(code: Int, message: String)
    case transport(String)                // the underlying error's description
    case decoding(String)
    case cancelled
}
```

Every `async` API uses typed throws (`throws(ABsmartlyError)`), so `catch` is exhaustive. The
messages are the 1.5.0 messages (the cross-SDK error texts).

### Values

`JSONValue` replaces SwiftyJSON's `JSON`:

```swift
public enum JSONValue: Sendable, Hashable, Codable {
    case null
    case bool(Bool)
    case int(Int64)
    case double(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])
}
```

It is expressible by every literal, has typed accessors (`stringValue`, `intValue`, `doubleValue`,
`boolValue`, `arrayValue`, `objectValue`, `subscript(key)`, `subscript(index)`) and conversions from
`String`, `Bool`, the integer and floating-point types, arrays and dictionaries
(`JSONValueConvertible`).

Integers and doubles are separate cases on purpose:
- 1.5.0 keeps integers above 2^53 exact (SwiftyJSON stores an `NSNumber`); so does 2.0.
- Switchback cluster values (planned, see below) follow java-sdk: whole-number integers give a
  cluster value, **every floating-point value gives none**. That rule needs the distinction.
- Comparisons in audiences and rules treat both as numbers, as 1.5.0 and JS do.

### Public models

`ContextData`, `Experiment`, `ExperimentVariant`, `CustomFieldValue`, `ExperimentApplication`,
`Exposure`, `Goal` and `PublishEvent` (with `PublishEvent.Unit` and `PublishEvent.Attribute`) are
`Sendable`, `Equatable` structs. Decoding is lenient per field exactly as 1.5.0 (a missing or
wrong-typed field takes its default; only `name` is required), and unknown fields at every level are
ignored.

### SwiftUI (`ABsmartlyUI`)

```swift
import ABsmartlyUI

WindowGroup { RootView().absmartlyContext(context) }

struct CheckoutButton: View {
    @Treatment("exp_checkout") var variant                       // exposes on read
    @Variable("button.color", default: "blue") var color: String
    var body: some View { ... }
}
```

The wrappers read the context from the environment and re-render when it becomes ready or
refreshes. Without a context in the environment they return `0` / the default.

## Implementation

### Concurrency model: a `Sendable` final class, not an actor

`treatment(for:)` and `variable(_:default:)` are called from `View.body`, `tableView(_:cellForRowAt:)`
and other synchronous UI code, many times per frame. An actor would make every one of them `await`,
which SwiftUI `body` cannot do, and would hop executors on the hottest path. So:

- `Context` is `final class Context: Sendable`. Its mutable state is one value-type struct
  (`ContextState`) guarded by one lock, so every read and write is a single short critical section.
  1.5.0 used a recursive lock, three more locks and six atomics; 2.0 has one lock per context.
- The lock is `os_unfair_lock` on Apple platforms and `pthread_mutex_t` on Linux, both
  heap-allocated so they never move (`Internal/Locked.swift`). `Synchronization.Mutex` needs
  iOS 18 / macOS 15 and `OSAllocatedUnfairLock` iOS 16, both above the floor; they wrap the same
  primitives.
- No user code runs under the lock: the event logger, the event streams and the transport are all
  called after the critical section. There is no recursive locking.
- Cached assignments are reference types mutated in place under the lock, as in 1.5.0, so a cached
  read neither copies nor writes back. Measured on Linux, release build, 200k cached reads (no rules,
  no audience, already exposed): `treatment` 209 ns/op (1.5.0: 275), peek 155 (257),
  `variableValue` 332 (465). A work-counter test (`revalidationCount`) pins that ordinary cached
  reads never re-evaluate rules or audiences.
- I/O (`ready`, `refresh`, `publish`, `close`) is `async`. Timers (auto-publish, auto-refresh) are
  `Task`s with `Task.sleep`.

The assignment engine (`ContextState`'s methods: rules, audiences, traffic, custom assignments,
cache revalidation) is a direct port of 1.5.0's `Context` logic onto value types. Experiment data
is indexed once per `ContextData` into an immutable `DataIndex` (variables parsed, rules parsed,
custom fields typed), built outside the lock and swapped in.

### Networking

`URLSessionTransport` uses `URLSession.data(for:)` (iOS 15+, swift-corelibs-foundation on Linux)
with the 1.x timeout. The SDK builds the request (`{endpoint}/context?application=…&environment=…`,
headers `X-API-Key`, `X-Agent: absmartly-swift-sdk/2.0.0`, `X-Application`,
`X-Application-Version` normalised as in 1.5.0, `X-Environment`, `Content-Type`), retries 502/503
and transport errors `retries` times with `retryInterval` between attempts (the 1.5.0 policy, for
GET and PUT alike; whether PUT should stop retrying on 502/503, as the cross-SDK contract now asks,
is tracked for both lines together rather than changed only in 2.0), maps
non-2xx statuses to `.httpStatus` and decodes with `JSONDecoder`.

### Hashing

MD5 comes from CryptoKit's `Insecure.MD5` on Apple platforms and from swift-crypto's identical API
on Linux; MurmurHash3 and the variant assigner are ported unchanged. (1.x used CommonCrypto's
`CC_MD5`, deprecated since iOS 13, which would fail a warnings-as-errors build.)

### JSON parsing

Audience, rule and variable JSON is parsed with `JSONSerialization` (the parser 1.5.0's SwiftyJSON
used) and numbers are classified the way SwiftyJSON did, so `-0.0` keeps its sign and integers
beyond `Int64` become doubles exactly as in 1.5.0. `JSONDecoder` differs on both and is only used
for the typed models (`ContextData`) and `JSONValue`'s `Codable` conformance.

### JSON expressions

The evaluator and operators are ported onto `JSONValue` with 1.5.0's semantics, including its
differences from JS. They are listed in *Known 1.5.0 divergences* and stay out of 2.0 so that 2.0's
behaviour is exactly 1.5.0's. Each will be fixed in both lines at the same time.

### Holdouts and switchbacks

- **Holdouts** are being added to 1.x on `feat/holdouts`. When they land on `main`, `main` is
  merged into this branch and the 1.x holdout logic is ported into `ContextState` (the
  `Assignment` value already has room for the holdout fields, and exposures queue the holdout
  exposures first, as in javascript-sdk).
- **Switchbacks** come later, following java-sdk `SWITCHBACK.md` (R33, cluster-defined). The
  design leaves room for them:
  - `Experiment` decoding is field-name based and ignores unknown fields, so the switchback fields
    (`randomizationType`, `switchbackClusters`, ...) can be added without a decoder change.
  - The assignment pipeline in `ContextState.assign` is a straight sequence of steps that matches
    the switchback precedence table (override, rules, strict audience, full-on, traffic,
    custom assignment, draw), so the switchback branch is a different final step.
  - Every read takes its time from the injected `TimeSource`, as the switchback period index needs.
  - Cluster values use java-sdk main's rule: a non-empty string as-is, a whole-number **integer**
    (`JSONValue.int`) as base-10 text, and nothing for every floating-point value, boolean, null,
    object or array.

## Toolchain, platforms and packaging

- `swift-tools-version: 6.0`, Swift 6 language mode, complete strict concurrency, warnings as
  errors in CI (`-warnings-as-errors`).
- Platforms: iOS 15, macOS 12, tvOS 15, watchOS 8, visionOS 1, Mac Catalyst 15; Linux.
  - Why 15: it is the first release with `URLSession`'s async API and back-deployed concurrency
    without shims; iOS 13–14 have under 1% of active devices, and the customer that asked for 2.0
    targets iOS 15+.
- Products: `ABsmartly` (core) and `ABsmartlyUI` (SwiftUI wrappers; compiled only where SwiftUI is
  available).
- Dependencies: none on Apple platforms. `swift-crypto` (`3.0.0..<5.0.0`) on Linux only, as a
  conditional target dependency.
- CocoaPods: `ABsmartly.podspec`, pod `ABsmartly` 2.0.0, `swift_versions = '6.0'`, same floors.
  See *Remaining owner/release items* about the trunk freeze.
- Version: `2.0.0`. The tag, the podspec and `SDKVersion.version` must agree (publish workflow
  check, unchanged).

### CI

- macOS (Xcode 16.x and the latest Xcode): `swift build` and `swift test` with
  `-Xswiftc -warnings-as-errors` (strict concurrency is implied by the Swift 6 language mode), and
  `xcodebuild` builds of both products for iOS, tvOS, watchOS and visionOS simulators.
- Linux (`swift:6.0` and the latest `swift` image): `swift build` and `swift test` with warnings as
  errors.
- `pod lib lint` on macOS.

## Parity with 1.5.0

Behaviour parity is proven, not asserted:

1. **Recorded 1.5.0 output.** `Tools/ParityRecorder` is a small package that depends on swift-sdk
   at the pinned 1.5.0 commit. It runs a deterministic probe (fixed clock, fake transport) over the
   test fixtures: a UID sweep (ASCII, padded, accented, CJK, emoji, numeric, negative, > 2^53,
   floats) across every fixture experiment, `getTreatment`/`peekTreatment`/variables/custom
   fields, assignment rules, audiences, overrides, custom assignments, refresh, the event sequence,
   the GET/PUT headers and the normalised publish body. It writes
   `Tests/ABsmartlyTests/Resources/parity/*.json`.
2. **2.0 replays it.** `ParityTests` runs the same probe on 2.0 and compares it with the recording.
   Any difference fails, apart from the documented intended ones (`X-Agent` version, renamed
   event/API names).
3. **cross-sdk-tests.** The companion PR moves the swift wrapper to the 2.0 API and pins the swift
   lane to `feat/swift-2.0`; every scenario the 1.5.0 lane passes must pass on 2.0.
4. **Ported unit tests.** The 1.x test suite is ported to swift-testing against the new API.

## Known 1.5.0 divergences from javascript-sdk (kept in 2.0, fixed later in both lines)

- `booleanConvert` truncates numbers to integers, so `0.5` is false (JS: true).
- `numberConvert` of a string uses `Double(_:)`, not JS `parseFloat` (`"5abc"` is null, JS 5).
- A multi-key JSON expression object evaluates the first key in dictionary order (JS: insertion
  order). The backend only produces single-key objects.
- When two arrays or objects are compared (`eq` of `[true]` and `[1]`), on Apple platforms only a
  boolean element equals the number 0/1, because 1.5.0 compared Foundation collections and Apple
  Foundation equates them. On Linux, and in javascript-sdk (`isEqualsDeep`), such elements never
  compare equal. Single-value comparisons and `in` items convert the right-hand value to the
  left-hand value's type (booleans to 0/1 against a number, numbers to a boolean against a boolean)
  on every platform, as JS does (`in([true], 1)` is true, `in([2], true)` is false), apart from
  the fractional-number truncation listed above. Whether 2.0
  should move to the JS behaviour for nested comparisons on every platform is listed under owner
  decisions.

## Known 2.0 difference from 1.5.0

- An integer literal from 2^63 to 2^64−1 inside an audience or rule (e.g. `9223372036854775808`)
  is converted to text as `"9223372036854776000"`. 1.5.0 on Linux prints it as a negative number
  (a Foundation `NSNumber` formatting bug), on Apple platforms as the unsigned value. Only `match`,
  `in` and string equality see the text; numeric comparisons are unchanged. The backend does not
  produce such literals.
- An integer literal outside the `Int64` range is stored as a `Double`, so inside arrays and objects
  two such neighbouring values (e.g. `18446744073709551615` and `18446744073709551614`) compare
  equal; 1.5.0 kept Foundation's exact `NSNumber`. The backend does not produce such literals.

## Migration

See `MIGRATING.md` for the full table. The short version:

| 1.x | 2.0 |
|---|---|
| `import ABSmartly` | `import ABsmartly` |
| `ABsmartlySDK(endpoint:apiKey:application:environment:)` | `ABsmartlyClient(endpoint:apiKey:application:environment:)` |
| `sdk.createContext(config:)` + `waitUntilReady()` | `try await client.context(units:...)` |
| `context.getTreatment("e")` / `peekTreatment` | `context.treatment(for: "e")` / `treatment(for: "e", exposing: false)` |
| `context.getVariableValue("k", defaultValue: JSON("x"))?.string` | `context.variable("k", default: "x")` |
| `context.publish().done { }` | `try await context.publish()` |
| `JSON` (SwiftyJSON) | `JSONValue` |
| `ContextEventLogger` | `context.events` / `Configuration.eventLogger` |
