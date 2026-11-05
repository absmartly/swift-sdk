# Changelog

## 1.5.0 (unreleased)

### BREAKING
- `ContextEventHandler` renamed to `ContextPublisher` (`contextEventHandler:` init kept).
- Standardized error messages.
- JSON expr `in` operator is haystack-first (CONTAINS semantics); `eq(null, null)` returns null.

### Compatibility
- `Context` methods keep their v1.4.0 non-throwing signatures. Misuse that used to hit a `precondition` (reading before ready, writing after close, an invalid or changed unit) no longer crashes: reads return a default (`0`, `nil`, the `defaultValue`, empty collections), writes are ignored, and an `.error` event is logged.
- Swift tools-version stays 5.3. `swift-crypto` (`1.0.0..<4.0.0`) is only linked on Linux; Apple platforms keep using CommonCrypto.

### Added
- `ClientConfig.applicationVersion`.
- `ContextEventLoggerEvent.finalize`, an alias for `.close`.
- Numeric unit UIDs: `setUnit(unitType:uid: Int/Double)`, `setUnit(unitType:value: JSON)`, `getUnitValue`/`getUnitValues` keep the number type; numbers hash like the JavaScript SDK (rounded to an integer, so 125.75 hashes as "126").
- `Hashing.utf8Bytes`, `Hashing.base64UrlNoPadding`, `Hashing.hash(Double)`.
- `finalize`/`isFinalized`/`isFinalizing` aliases, `readyError`.

### Fixed
- The `error` event for a failed load is logged before the context reports failed, like the JavaScript SDK. The `ready` event is still logged after the context is ready, so reads from a logger's `ready` handler work.
- No exposures after close; failed final flush keeps the context retryable; refresh joins in-flight promise; close awaits in-flight publishes.
- Request timeout; HTTP retry and publish recovery off the main queue; numeric 0/1 coercion in JSON custom fields; astral/multibyte hashing.
