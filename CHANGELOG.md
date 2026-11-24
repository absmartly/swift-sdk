# Changelog

## 2.0.0 (unreleased)

A new API for Swift 6 over the 1.5.0 engine. Assignment, audiences, assignment rules, exposures,
goals and the publish payload retain 1.5.0 behaviour apart from holdouts (below) and the extreme
unsigned-number rounding described in [MIGRATING.md](MIGRATING.md#behaviour-notes) (a parity test replays 1.5.0's
recorded output); the `X-Agent` header is `absmartly-swift-sdk/2.0.0`. See [MIGRATING.md](MIGRATING.md) for every
1.x API and its replacement, and [SUPPORT.md](SUPPORT.md) for the 1.x support window.

**2.0.0 does not support holdouts.** Holdout data in the context payload (`holdouts`, `holdoutIds`)
is ignored, as 1.4.0 ignored it: every unit is assigned and exposed as if no holdout existed, and no
holdout exposure is published. Apps that rely on holdouts should stay on 1.5.x, which supports them
(1.5.0 is released before 2.0.0 and maintained on `release/1.x`). Holdouts come in a later 2.x
release.

### BREAKING (everyone moves)
- Holdouts are not supported (1.5.0 supports them): holdout data is ignored, so a unit a holdout would hold out is assigned and exposed normally, and no holdout exposure is published. Stay on 1.5.x if you use holdouts; they come in a later 2.x release.
- Module and pod renamed to `ABsmartly` (was module `ABSmartly`, pod `ABSmartlySwiftSDK`); the entry type is `ABsmartlyClient`. Update `import` lines and the dependency.
- `async`/`await` replaces PromiseKit: `ready()`, `publish()`, `refresh()`, `close()` and `fetchContextData()` are `async throws(ABsmartlyError)`.
- `JSONValue` replaces SwiftyJSON's `JSON` in every API (attributes, variables, goal properties, custom fields, unit values).
- `ABsmartlyClient.Configuration` replaces `ABsmartlyConfig`, `ClientConfig`, `DefaultHTTPClientConfig`, `Client`/`DefaultClient`, `ContextDataProvider` and `ContextPublisher`; a `Transport` replaces `HTTPClient`. `Scheduler`, `Clock`, `VariableParser`, `AudienceMatcher`, `Hashing` and `MurmurHash` are no longer public.
- Contexts are created with `client.context(units:...)` (awaited), `client.makeContext(units:...)` or `client.context(units:..., data:)`, instead of `ContextConfig`.
- Renamed reads and setters, following the Swift API Design Guidelines (`treatment(for:)`, `variable(_:default:)`, `overrides[...]`, `state`, ...).
- `ContextEventLogger` is replaced by an `EventLogger` closure and `context.events` (`AsyncStream`); `ContextEventLoggerEvent` is `Context.Event`, with no `.finalize` alias.
- `ABSmartlyError` (a class) is replaced by the `ABsmartlyError` enum. `localizedDescription` keeps the 1.x messages.
- Minimum platforms raised to iOS 15, macOS 12, tvOS 15, watchOS 8 (1.x: iOS 10, macOS 10.14, tvOS 10, watchOS 3); building needs Swift 6.0 / Xcode 16.
- `setUnit` throws its error (blank UID, a different UID already set, closed context) in addition to emitting the `.error` event.
- `client.context(units:...)` throws when the context data cannot be fetched instead of returning a failed context (`makeContext` still returns it).
- A custom variant-config parser (`VariableParser`) is no longer supported.
- `customFieldValue(_:in:)` returns `JSONValue?` for every field type (1.x returned `Any?`: `[String: JSON]`, `JSON`, `Double`, `Bool` or `String`).

### Changed
- The `X-Agent` header is `absmartly-swift-sdk/2.0.0`, so the collector's `agent` column shows 2.0.0 for 2.x clients.
- Variable keys shared by several experiments follow 1.5.0's final rule (the Java SDK's). Affects anyone running two or more experiments whose variants define the same key:
  - The candidates are the experiments whose variants define the key, in ascending id order.
  - The winner is the first candidate the user is in: assigned, overridden or set by an assignment rule.
  - Only the winner is exposed. A candidate that was only checked gets no exposure; a later `treatment(for:)` on it still exposes it once.
  - When the winner's variant does not define the key, `variable(_:default:)` returns the default and `variableValue(_:)` returns `nil`. A later candidate is never used.
  - `exposing: false` exposes nothing.
  - A refresh that changes only variant configs (same iteration) keeps an assignment already resolved in the context, including its variables (as in Java).

  Earlier 2.0 pre-releases and the 1.5.0 pre-release on `main` exposed every candidate checked, and fell through to a later candidate when the winner's variant lacked the key. A strict audience mismatch now gives the control variant without an exposure from a variable read.

### Added
- Swift 6 language mode with complete strict concurrency; every public type is `Sendable`.
- `ABsmartlyUI`, a separate product with SwiftUI property wrappers (`@Treatment`, `@Variable`) and `.absmartlyContext(_:)`.
- Typed variables (`variable(_:default:)` for any `Decodable & Sendable`), `treatment(for:as:)` for `Int`-backed enums, `isInTreatment(_:)`.
- Atomic `setOverride(_:for:)`/`setOverrides(_:)` and `setCustomAssignment(_:for:)`/`setCustomAssignments(_:)`; `overrides`/`customAssignments` dictionary properties (a snapshot on read; assigning replaces the whole dictionary); overrides and custom assignments at context creation.
- `Context.State` and `context.state`.
- `EventLogger.osLog`. It logs what happened (event kind, experiment or goal name, error kind) publicly and the event's contents (goal properties, attributes, context data, error text) as private data, which the unified log redacts unless the device is set up to show it. The SDK's own diagnostics (malformed configs, custom fields, regex patterns, audiences) do the same: payload text is private.
- A NaN or infinite number in a goal property or attribute is published as `null`, as JavaScript's `JSON.stringify` writes it. 1.5.0 could not encode such a batch and re-queued it, so no later publish or `close()` succeeded.
- `ABsmartlyError` may gain cases in later 2.x releases; a `switch` over it needs a `default` case.
- A `refresh()` that completes while the first fetch is still pending makes the context ready, and every `ready()` caller (waiting or later) succeeds; the first fetch's late result, data or error, is ignored. If the first fetch fails first, the context stays failed and an overlapping refresh does not change it (`refresh()` on a failed context does not recover it, as before).

### Dependencies
- None linked on Apple platforms: PromiseKit, SwiftyJSON and swift-atomics are gone; MD5 comes from CryptoKit. `swift-crypto` (`3.0.0..<5.0.0`) is linked on Linux only (SwiftPM still downloads it, and swift-asn1, when resolving on Apple platforms).

### Release
- The publish workflow creates the GitHub release; 1.x tags are created with `--latest=false`. CI runs on `main` and `release/**`.
- The CocoaPods trunk is read-only from 2026-12-02. A 2.0 pod can only be published before then; afterwards 2.x is distributed through Swift Package Manager.

## 1.5.0 (unreleased)

### BREAKING
- Audiences and assignment-rule conditions always evaluate the configured `application` (its name) and `environment` (its name) attributes, with no opt-in. This changes assignment for running experiments: a unit whose experiment has Audience enforced (strict) and an `environment`/`application` condition currently gets variant 0 (the condition never matched because the SDK did not supply the attribute). After upgrading, that condition matches and the unit is randomised normally. Those experiments are broken today; this fixes them, but the change in assignment is intentional and called out here. System values are applied first and user-set attributes overlay them, so a `setAttribute("environment", …)` (even after the context is created) still wins and invalidates a cached assignment. Values that are `nil` or empty are left out of the evaluation map. These attributes are not sent on the publish payload (the collector already adds them server-side) and are not reported by `getAttributes()`/`getAttribute(name:)`. `app_version`/`applicationVersion` is never injected into audience evaluation; only a user-set `app_version` attribute is evaluated. `ClientConfig.applicationVersion` stays a `String`, so the public API stays backward compatible.
- A variable key shared by several experiments: the candidates are the experiments whose variants define it, by ascending id; the first one the user is in (assigned, overridden or set by an assignment rule) wins, and only it is exposed. When its variant lacks the key the default is returned; a later candidate is never used. `peekVariableValue` exposes nothing. v1.4.0 did not count a rule-assigned candidate as the winner. (Final rule from swift-sdk#14, `release/1.5.0-prep`.)
- `ContextEventHandler` renamed to `ContextPublisher`. Source-compatible: `ContextEventHandler` is a typealias and the `contextEventHandler:` init is kept. Only binary (ABI) consumers are affected.
- Standardized error messages.
- Audiences are re-evaluated when attributes change: a `setAttribute` after a treatment was read can change that experiment's assignment (and log a new exposure) when the audience result flips.
- `publish()` and `close()` reject when the collector answers with a non-2xx status (v1.4.0 treated any response as success). A failed `close()` leaves the context open with its events queued, so `publish()`/`close()` can retry; v1.4.0 marked it closed.
- A negative `publishDelay` disables automatic publishing; events are only sent by `publish()` or `close()`.
- A failed context: `getContextData()` returns an empty `ContextData` instead of `nil`, and `refresh()` succeeds without fetching (v1.4.0 fetched again).
- `getCustomFieldValue`/`getCustomFieldValueType` called before the context is ready or after it is closed log an `.error` event (they still return `nil`).
- A `boolean` custom field is `true` only for the exact string `"true"`; any other value, including `"TRUE"`, returns `false` (v1.4.0 returned `nil` for anything but `"true"`/`"false"`).
- A `json` custom field holding an array or a scalar returns it as `JSON` (v1.4.0 returned `nil`, since the `VariableParser` only accepts objects).
- `getContextData()` rejects a non-2xx response with `ABSmartlyHTTPError` (v1.4.0 tried to decode the body and rejected with a decoding error).

### Dependencies
- Apple platforms are unchanged: the SDK still depends on SwiftyJSON (`~> 5.0`, Swift Package Manager and CocoaPods) and `ABSmartly.JSON` is still `SwiftyJSON.JSON`, so `SwiftyJSON.JSON` values can be passed to the SDK and its results stored in `SwiftyJSON.JSON` variables as before.
- On Linux, where SwiftyJSON does not compile with Linux Foundation, `ABSmartly.JSON` is a vendored copy of SwiftyJSON 5.0.2's `JSON` with the same API (`SwiftyJSONError` is vendored too), and SwiftyJSON is not linked.

### Compatibility
- `getCustomFieldValue` returns the v1.4.0 types: `[String: JSON]` from the configured `VariableParser` for a `json` object (other JSON values as `JSON`), `Double` for `number`, `Bool` for `boolean`.
- `ready`, `refresh`, `publish` and `close` events reach the `ContextEventLogger` on the main thread on Apple platforms, as in v1.4.0. The work itself runs off the main thread.
- `publish()` and `refresh()` work before the context is ready, as in v1.4.0.
- A pending automatic publish keeps the context alive until it is sent, so a `track()` followed by dropping the context still publishes.
- `Context` methods keep their v1.4.0 non-throwing signatures. Misuse that used to hit a `precondition` (reading before ready, writing after close, an invalid or changed unit) no longer crashes: reads return a default (`0`, `nil`, the `defaultValue`, empty collections), writes are ignored, and an `.error` event is logged. Overrides and custom assignments (`setOverride(s)`, `setCustomAssignment(s)`) are still accepted after close, as in v1.4.0.
- Swift tools-version stays 5.3. Toolchains 5.9 and later read `Package@swift-5.9.swift`, which is identical except that the SwiftyJSON dependency also names Mac Catalyst and visionOS (those platform conditions need a newer tools-version). `swift-crypto` (`1.0.0..<4.0.0`) is only linked on Linux; Apple platforms keep using CommonCrypto.
- Linux is supported: the SDK builds and its tests pass with Swift 5.10, 6.1 and 6.4 on Linux, and CI runs them on every change. Before, SwiftyJSON did not compile with Linux Foundation.
- On Linux, `ABSmartlyError` (and the internal HTTP error) subclass `NSError`, because Foundation in Swift 6.0 and 6.1 crashes when `localizedDescription` is read on a class-based error that is not an `NSError` ([swift-corelibs-foundation#5221](https://github.com/swiftlang/swift-corelibs-foundation/issues/5221)). `errorMessage`, `localizedDescription` and `is`/`as?` casts are unchanged. Apple platforms are not affected.

### Changed
- Holdouts configured in A/B Smartly now take effect in the Swift SDK (v1.4.0 ignored them; see *Added*). A unit held out by a holdout covering an experiment moves to the control variant, and that experiment's exposure is replaced by the holdout's own exposure. Experiments not covered by a holdout are unchanged; a unit that is not held out is assigned as before, plus one exposure per covering holdout.
- The `X-Application-Version` header is normalised for the collector, which binds it as an integer and rejects anything else with HTTP 400: the configured value is trimmed and sent as-is when it is 1–18 ASCII digits, otherwise as `"0"` (like the Java SDK). `ClientConfig.applicationVersion` keeps the caller's value. v1.4.0 sent the raw value on publish, so a dotted version such as `"2.4.1"` made every publish fail.
- The context GET carries the same headers as the publish PUT (`X-API-Key`, `X-Agent`, `X-Application`, `X-Application-Version`, `X-Environment`), as the JavaScript SDK sends on every request.
- Every exposure in the publish payload carries `ruleOverride` (`false` when no assignment rule matched), as the JavaScript SDK serialises it.

### Added
- Holdouts, matching the JavaScript SDK. `ContextData.holdouts` and `Experiment.holdoutIds` are decoded (with `Experiment.holdoutType`, informational), and a unit held out by any holdout covering an experiment gets the control variant and values with no exposure of its own; in a three-arm holdout, arm 1 holds out only experiments that are not full-on. Each covering holdout publishes an ordinary exposure (its id, name and the unit's arm) the first time a covered experiment is read. Overrides and matching assignment rules still win. A payload without holdouts assigns and publishes exactly as before. `ContextData(experiments:holdouts:)` is a new initialiser; `ContextData(experiments:)` and `ContextData()` are unchanged. A malformed holdout entry is ignored on its own.
- Assignment rules (`Experiment.assignmentRules`), matching the JavaScript SDK. The first rule whose `environments` and `conditions` match sets the variant: `assign` gives a fixed variant, `split` hashes the unit with the experiment's seed over the rule's percentages (which must sum to 100 within 0.01). A matching rule wins over audience/`audienceStrict`, traffic eligibility, full-on and custom assignments; only an override beats it. Exposures carry a new `ruleOverride` flag. A split matched before its unit is set gives the experiment's no-unit result (the full-on variant, else 0) and is re-resolved when the unit is set, unless it was already exposed. Malformed rules are skipped; a split whose length differs from the variant count, or an out-of-bounds `assign` variant, falls back to normal assignment.
- `semver_eq`, `semver_gt`, `semver_gte`, `semver_lt` and `semver_lte` JSON-expression operators.
- The `X-Agent` header is `absmartly-swift-sdk/<version>` (was `absmartly-swift-sdk`).
- Tags `v*` publish the podspec to the CocoaPods trunk (the tag, podspec and SDK version must agree). Swift Package Manager keeps resolving releases from the tag.
- `ClientConfig.applicationVersion`.
- `ABsmartlySDK(endpoint:apiKey:application:environment:…)` convenience init. Its `contextEventLogger` is used for every context whose `ContextConfig.eventLogger` is unset, and `retries` defaults to 3, like `DefaultHTTPClientConfig`.
- `ContextEventLoggerEvent.finalize`, an alias for `.close`.
- Numeric unit UIDs: `setUnit(unitType:uid: Int/Double)`, `setUnit(unitType:value: JSON)`, `getUnitValue`/`getUnitValues` keep the number type; numbers hash like the JavaScript SDK (rounded to an integer, so 125.75 hashes as "126").
- `Hashing.utf8Bytes`, `Hashing.base64UrlNoPadding`, `Hashing.hash(Double)`.
- `finalize`/`isFinalized`/`isFinalizing` aliases, `readyError`.

### Fixed
- The `error` event for a failed load is logged before the context reports failed, like the JavaScript SDK. The `ready` event is still logged after the context is ready, so reads from a logger's `ready` handler work.
- No exposures after close; refresh joins in-flight promise; close awaits in-flight publishes.
- An audience of `null` or `{}` is treated as no audience without logging an error.
- `match` gives up after 100ms (returning null) on patterns that backtrack exponentially, e.g. `^(a|aa)+$`, and rejects nested unbounded quantifiers such as `(a+)+`.
- Request timeout; HTTP retry and publish recovery off the main queue; astral/multibyte hashing.
