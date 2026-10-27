# Changelog

## 1.5.0 (unreleased)

### BREAKING
- `ContextEventHandler` renamed to `ContextPublisher` (`contextEventHandler:` init kept).
- Read methods return safe defaults instead of throwing; standardized error messages.
- JSON expr `in` operator is haystack-first (CONTAINS semantics); `eq(null, null)` returns null.

### Added
- Numeric unit UIDs: `setUnit(unitType:uid: Int/Double)`, `setUnit(unitType:value: JSON)`, `getUnitValue`/`getUnitValues` keep the number type; numbers hash like the JavaScript SDK (rounded to an integer, so 125.75 hashes as "126").
- `Hashing.utf8Bytes`, `Hashing.base64UrlNoPadding`, `Hashing.hash(Double)`.
- `finalize`/`isFinalized`/`isFinalizing` aliases, `readyError`.

### Fixed
- The `ready` / `error` event is logged before the context reports ready or failed, like the JavaScript SDK.
- No exposures after close; failed final flush keeps the context retryable; refresh joins in-flight promise; close awaits in-flight publishes.
- Request timeout; HTTP retry and publish recovery off the main queue; numeric 0/1 coercion in JSON custom fields; astral/multibyte hashing.
