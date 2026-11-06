# Changelog

## 2.0.0 (unreleased)

### BREAKING
- Requires Swift 6.1 (Xcode 16.3) or later: the package's tools-version is 6.1 (the code still builds in the Swift 5 language mode). Minimum deployment targets are now iOS 12, tvOS 12, macOS 10.14 and watchOS 4 (were iOS 10, tvOS 10, watchOS 3; the podspec had macOS 10.10). On Linux, `swift-crypto` 3.x is required.
- A variable key shared by several experiments resolves like the JavaScript SDK. The experiments are walked in ascending id order; `getVariableValue` exposes every experiment it visits (an unassigned one with `assigned: false`), and the value comes from the first experiment that is assigned or overridden and whose variant defines the key. v1.4.0 used the first assigned or overridden experiment even when its variant lacked the key (returning the default) and exposed only that experiment. Callers of a key whose lowest-id experiment's variant lacks it now get a later experiment's value, and more exposures can be queued. `getVariableValue` also exposes an experiment whose audience mismatch in strict mode yields the control variant, as `getTreatment` does.
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

### Compatibility
- `getCustomFieldValue` returns the v1.4.0 types: `[String: JSON]` from the configured `VariableParser` for a `json` object (other JSON values as `JSON`), `Double` for `number`, `Bool` for `boolean`.
- `ready`, `refresh`, `publish` and `close` events reach the `ContextEventLogger` on the main thread on Apple platforms, as in v1.4.0. The work itself runs off the main thread.
- `publish()` and `refresh()` work before the context is ready, as in v1.4.0.
- A pending automatic publish keeps the context alive until it is sent, so a `track()` followed by dropping the context still publishes.
- `Context` methods keep their v1.4.0 non-throwing signatures. Misuse that used to hit a `precondition` (reading before ready, writing after close, an invalid or changed unit) no longer crashes: reads return a default (`0`, `nil`, the `defaultValue`, empty collections), writes are ignored, and an `.error` event is logged. Overrides and custom assignments (`setOverride(s)`, `setCustomAssignment(s)`) are still accepted after close, as in v1.4.0.
- `swift-crypto` is only linked on Linux; Apple platforms keep using CommonCrypto.

### Added
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
