# Changelog

## 1.5.0 (unreleased)

### BREAKING
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
- Swift tools-version stays 5.3. `swift-crypto` (`1.0.0..<4.0.0`) is only linked on Linux; Apple platforms keep using CommonCrypto.

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
