# Changelog

## Unreleased

### Maintenance
- Document the CocoaPods dependency investigation and add a full-lint Mac script and manual
  diagnostic CI workflow. No consumer fix is implemented: Xcode 27.2 cannot build pods below
  iOS 15 / macOS 12 / watchOS 9, below the 1.x podspec's targets, so CocoaPods validation needs an
  owner decision (see docs/cocoapods-validation.md). The quick podspec check does not compile
  dependencies. Deployment targets, dependency types and publication gates are unchanged.

## 1.5.0

1.5.0 is source compatible with 1.4.0: code written against 1.4.0 compiles unchanged, with the same
PromiseKit and SwiftyJSON types, minimum platforms and Swift tools-version (5.3). It is the last 1.x
feature release. A 2.0 SDK with a new, async-first API is planned; 1.x will be maintained (bug and
security fixes, from the `release/1.x` branch) for 12 months after 2.0 ships.

### Added
- async/await overloads of every Promise-returning method, in the new `ABSmartlyAsync` module
  (`import ABSmartlyAsync`, part of the `ABSmartly` Swift Package Manager product; iOS 13, macOS 10.15,
  tvOS 13, watchOS 6): `Context.waitUntilReady()`, `refresh()`, `publish()`, `close()`, `finalize()`,
  `ABSmartlySDK.getContextData()`, `close()`, the `Client`, `ContextDataProvider`,
  `ContextEventHandler` and `HTTPClient` methods, and `DefaultHTTPClient.request`. Each awaits the existing Promise, so behaviour is
  unchanged; cancelling the calling task does not cancel the request. They are in a separate module
  because, inside an `async` function, Swift prefers an async overload, so 1.4.0 code such as
  `_ = context.publish()` there would no longer compile if they were in `ABSmartly`. Once any module
  in a build imports `ABSmartlyAsync`, the overloads are visible to all code using `ABSmartly`, so
  such code then needs `try await`, an explicit `Promise` type, or Swift 6.1's `MemberImportVisibility`
  (see the README). With Swift 6
  compilers they run in the caller's isolation (`#isolation`), so they can be awaited from
  `@MainActor` code in Swift 6 apps without Sendable diagnostics. Not available through CocoaPods.
- Holdouts, matching the JavaScript SDK. `ContextData.holdouts` and `Experiment.holdoutIds` are decoded
  (with `Experiment.holdoutType`, informational), and a unit held out by any holdout covering an
  experiment gets the control variant and values with no exposure of its own; in a three-arm holdout,
  arm 1 holds out only experiments that are not full-on. Each covering holdout publishes an ordinary
  exposure (its id, name and the unit's arm) the first time a covered experiment is read. Overrides and
  matching assignment rules still win. A payload without holdouts assigns and publishes exactly as
  before (v1.4.0 ignored holdouts). `ContextData(experiments:holdouts:)` is a new initialiser;
  `ContextData(experiments:)` and `ContextData()` are unchanged. A malformed holdout entry is ignored on
  its own.
- Assignment rules (`Experiment.assignmentRules`), matching the JavaScript SDK. The first rule whose
  `environments` and `conditions` match sets the variant: `assign` gives a fixed variant, `split`
  hashes the unit with the experiment's seed over the rule's percentages (which must sum to 100 within
  0.01). A matching rule wins over audience/`audienceStrict`, traffic eligibility, full-on and custom
  assignments; only an override beats it. Exposures carry a new `ruleOverride` flag. A split matched
  before its unit is set gives the experiment's no-unit result (the full-on variant, else 0) and is
  re-resolved when the unit is set, unless it was already exposed. Malformed rules are skipped; a split
  whose length differs from the variant count, or an out-of-bounds `assign` variant, falls back to
  normal assignment.
- `semver_eq`, `semver_gt`, `semver_gte`, `semver_lt` and `semver_lte` JSON-expression operators.
- Linux support: the SDK builds and its tests pass with Swift 5.10, 6.1 and 6.4 on Linux (CI runs 5.10 and 6.1).
  On Linux `ABSmartly.JSON` is a vendored copy of SwiftyJSON 5.0.2's `JSON` with the same API (SwiftyJSON
  itself does not compile there) and MD5 is computed in the SDK; Apple platforms are unchanged
  (SwiftyJSON `~> 5.0`, CommonCrypto). No new package dependencies.
- `ClientConfig.applicationVersion` and `ClientConfig.init(apiKey:application:endpoint:environment:applicationVersion:)`.
- `ABSmartlySDK(endpoint:apiKey:application:environment:…)` convenience init, with `retries`
  defaulting to 3 like `DefaultHTTPClientConfig`.
- Cross-SDK spellings, as aliases of the 1.4.0 types (not deprecated): `ABsmartlySDK`,
  `ABsmartlyConfig`, `ContextPublisher`, `DefaultContextPublisher`, `ABSmartlyConfig.contextPublisher`
  and `init(contextDataProvider:contextPublisher:…)`.
- Numeric unit UIDs: `setUnit(unitType:uid: Int/Double)`, `setUnit(unitType:value: JSON)`,
  `getUnitValue`/`getUnitValues` keep the number type; numbers hash like the JavaScript SDK (rounded
  to an integer, so 125.75 hashes as "126"). Like JavaScript numbers, integers above 2^53 lose
  precision; pass larger IDs as strings.
- `finalize()`/`isFinalized()`/`isFinalizing()` aliases, `ContextEventLoggerEvent.finalize` (an alias
  for `.close`), `readyError()`, `getCustomFieldKeys(experimentName:)`.
- `Hashing` is public, with `hash(String)`, `hash(Double)`, `utf8Bytes`, `base64UrlNoPadding`;
  `ABSmartlyError` is public.
- A `v*` tag can publish the podspec to the CocoaPods trunk (the tag, podspec and SDK version must
  agree). The job is off until the repository variable `COCOAPODS_PUBLISH` is `true`; see the
  CocoaPods note under Compatibility.

### Changed (cross-SDK contract)
- Holdouts configured in A/B Smartly take effect (v1.4.0 ignored them; see *Added*). A unit held out by
  a holdout covering an experiment moves to the control variant, and that experiment's exposure is
  replaced by the holdout's own exposure. Experiments not covered by a holdout are unchanged; a unit
  that is not held out is assigned as before, plus one exposure per covering holdout.
- Audiences and assignment-rule conditions see the configured `application` and `environment` names
  as attributes, as in the other SDKs. An experiment with a strict audience on `environment` or
  `application` used to give every unit variant 0 (the attribute was never set); it now matches. A
  user-set attribute of the same name wins. These are evaluation-only: they are not published and not
  returned by `getAttributes()`. `app_version` is never injected.
- Audiences are re-evaluated when attributes change, as in the Java SDK (released in 1.9.0) and the
  JavaScript SDK. The system-attributes contract requires it: a user-set `environment`/`application`
  wins over the configured value even when set after the context is created, so it has to
  invalidate an assignment cached before it was set. A `setAttribute` after a treatment was read can change
  that experiment's assignment (and log a new exposure) when the audience result flips.
- The `X-Agent` header is `absmartly-swift-sdk/<version>` (was `absmartly-swift-sdk`).
- The context GET carries the same headers as the publish PUT (`X-API-Key`, `X-Agent`, `X-Application`,
  `X-Application-Version`, `X-Environment`), as the JavaScript SDK does.
- `X-Application-Version` carries `ClientConfig.applicationVersion` normalised for the collector, which
  only accepts an integer: the trimmed value when it is 1–18 ASCII digits, otherwise `"0"` (like the
  Java SDK). 1.4.0 always sent `"0"`.
- Every exposure in the publish payload carries `ruleOverride` (`false` when no assignment rule matched).
- A negative `ContextConfig.publishDelay` disables the automatic publish, matching the Java and
  JavaScript SDKs and `main`: exposures and goals stay queued until `publish()` or `close()`, which
  still send them. 1.4.0 scheduled the publish with the negative delay, so it published right after
  the first event of each batch (events arriving while that publish was pending joined it). Apps on
  1.4.0 that set `publishDelay` to `-1` now call `publish()` themselves.

### Fixed
- Variable keys shared by several experiments. This affects anyone running two or more experiments
  whose variants define the same variable key. Unreleased builds of `main` after 1.4.0 exposed every
  experiment they checked for a key, recording users in experiments they never saw. They also took the
  value from a later experiment when the winner's variant lacked the key, which biases the winner's
  results. 1.4.0 itself exposed only the winner and did neither. The rule now applied, matching the
  Java SDK:
  - A key's candidates are the experiments whose variants define it, in ascending id order.
  - The winner is the first candidate the user is in: assigned, overridden or selected by an
    assignment rule. When no candidate qualifies, the first held-out candidate supplies its control
    value (see Holdouts). Otherwise `getVariableValue` returns the default.
  - When the winner's variant does not define the key, the default is returned. A later candidate is
    never used because of the variant the user got.
  - Only the winner is exposed. Candidates that were checked but did not win get no exposure; a later
    `getTreatment` on one still exposes it once. Each holdout covering a checked candidate publishes
    its own exposure, as in Java. `peekVariableValue` exposes nothing.
  - As in Java, a refresh that changes only variant configs (same experiment iteration) keeps an
    assignment already resolved in the context, including its variables. If that winner's variant
    did not define the key before the refresh, `getVariableValue` still returns the default.

  Compared with 1.4.0, a candidate won by an assignment rule now counts as the winner, and holdouts
  apply.
- `setOverride` with a negative variant no longer crashes `getTreatment` or `getVariableValue`
  (1.4.0 trapped with an index out of range). The override is returned and exposed; a variable read
  gives the default.
- A `json` custom field holding valid non-object JSON (array, number, string, boolean) is returned as
  `JSON` by `getCustomFieldValue`; 1.4.0 returned `nil` because the `VariableParser` only accepts objects.
  `null` returns `nil`. Objects and invalid JSON still go through the configured `VariableParser`, and
  the field gets whatever it returns (the default parser returns `nil` for invalid JSON, which is now
  also logged with the field and experiment name). A custom `VariableParser` is no longer called for
  non-object or `null` JSON custom fields.
  A `boolean` custom field keeps 1.4.0's coercion (`Bool(value)`: only `"true"`/`"false"`).
- `Context` methods no longer crash the app on misuse (reading before ready, writing after close, a
  blank or changed unit): 1.4.0 hit a `precondition`. Reads return a default (`0`, `nil`, the
  `defaultValue`, empty collections), writes are ignored, and an `.error` event with the 1.4.0 message
  is logged. `setOverride(s)`/`setCustomAssignment(s)` are accepted after close, as before.
- `publish()` and `close()` reject when the collector answers with a non-2xx status; 1.4.0 reported the
  failed publish as success and dropped its events. Failed events are re-queued, and a failed `close()`
  leaves the context open with one automatic publish scheduled for them (a single attempt; after
  that `publish()`, `close()` or the next event retries) (1.4.0 marked it closed with the events
  lost). With a negative `publishDelay` nothing is retried automatically, neither on the failed
  `close()` nor on the next event: call `publish()` or `close()` again. A failed `close()` does not itself restart the refresh timer. A refresh already in flight
  can restart it if it succeeds after the close rejects, and a later successful explicit refresh
  can restart it too.
  `getContextData()` rejects a non-2xx response with an HTTP error instead of a decoding error.
- MurmurHash3 read past the end of a key with a 3-byte tail (an out-of-bounds read). The SDK only
  hashes 22- and 12-byte keys, so variant assignment is unchanged.
- `ABSmartlyConfig.contextEventLogger` is used for every context whose `ContextConfig.eventLogger` is
  unset, as documented in 1.4.0's README; 1.4.0 stored it but never used it.
- `DefaultScheduler` runs its callbacks on a private utility queue instead of the main queue, so
  timers no longer block or wait for the main thread.
- A context whose first load failed recovers when a later `refresh()` succeeds (`isFailed()` false,
  `readyError()` nil); 1.4.0 installed the refreshed data but kept the context failed and silently
  discarded every exposure and goal. Exposures made while it was failed (without experiment data)
  are dropped on recovery and the next read exposes the user's actual variant once, so a logger can
  see an `.exposure` event that is never published. Goals tracked or re-queued while it is failed
  are kept for recovery: no automatic publish is scheduled for a failed context (in 1.4.0 any event
  on it started one that discarded the queue). An explicit `publish()` or `close()` of a failed
  context still discards the queue, as in 1.4.0. Until the context recovers or the queue is
  discarded, those events stay in memory and are counted by `getPendingCount()`.
  A refresh that completes while the initial load is still pending makes the context ready,
  settling `waitUntilReady()` and logging `.ready` once.
  Swift-specific: the JavaScript SDK does not refresh a failed context at all.
- No exposures after close; `refresh()` joins an in-flight refresh; `close()` waits for in-flight
  publishes; a pending automatic publish keeps the context alive until it is sent.
- A refresh whose fetch completes after `close()` has started is discarded: it installs no data, does
  not make a failed context ready, and logs no `.refresh` or `.error` event, so its result cannot
  change the context after `close()` has resolved. A refresh that installed its data before `close()`
  started is not undone, and its `.refresh` event may still reach the logger after `.close`.
- Work no longer runs on the main queue (timers, HTTP retries, publish recovery); `ready`, `refresh`,
  `publish`, `close` and `error` events from asynchronously completed work still reach the
  `ContextEventLogger` on the main thread on Apple platforms, as in 1.4.0. As in 1.4.0, events raised
  synchronously by a call (`exposure`, `goal`, misuse errors, `close` of an idle context, and the
  events of a context created with data that was already loaded or failed) reach the logger on the
  calling thread.
- An audience of `null` or `{}` is treated as no audience without logging an error.
- `match` gives up after 100ms (returning null) on patterns that backtrack exponentially.
- A failed automatic refresh reports one `.error` event (it was reported twice on main).
- A request keeps its `DefaultHTTPClient` alive until it settles, as in 1.4.0, so dropping the client
  mid-request no longer leaves the Promise pending forever (main-era regression).
- The HTTP request timeout uses `connectionRequestTimeout`; data races and crashes under concurrent
  use.
- No compiler warnings in the SDK with Swift 5.10–6.4 toolchains.

### Compatibility notes
- Checked on Linux before release: the 1.4.0 test suite and an app written against the 1.4.0 README
  compile unchanged against 1.5.0 (the 1.4.0 tests that fail are the contract changes above), and
  `swift-api-digester` found no source-breaking change in 1.4.0's public API and no ABI break,
  comparing library-evolution builds of 1.4.0 and 1.5.0. Building 1.4.0 on Linux needed local shims
  (CommonCrypto, OSLog, FoundationNetworking, the vendored JSON) that are not in the repository, so
  this is not reproducible from the repo alone. Apple ABI was not measured.
- On Linux, `ABSmartlyError` subclasses `NSError`, because Foundation in Swift 6.0 and 6.1 crashes
  when `localizedDescription` is read on a class-based error that is not an `NSError`
  ([swift-corelibs-foundation#5221](https://github.com/swiftlang/swift-corelibs-foundation/issues/5221)).
- The declared minimum platforms are unchanged (iOS 10, macOS 10.14 for Swift Package Manager / 10.10
  for CocoaPods, tvOS 10, watchOS 3). Current Xcode cannot build for watchOS below 5, so CI builds
  watchOS at 5.0 and iOS/tvOS at the package minimums.
- CocoaPods: `pod lib lint` / `pod trunk push` currently fail on Xcode 16.3 and 26 while building
  the dependency pods, before the SDK is compiled: SwiftyJSON 5 declares macOS 10.9 (availability
  errors) and, on Xcode 26, PromiseKit 6's iOS 8 target needs the removed `libarclite`. The SDK
  itself builds for every Apple platform with Swift Package Manager. So the `v1.5.0` tag does not
  publish 1.5.0 to the CocoaPods trunk: the publish job's trunk push is off (`COCOAPODS_PUBLISH`),
  and that switch only affects tags pushed after it is set. A 1.5.x pod needs the dependency pods to
  validate on the publishing Xcode; raising this podspec's own targets does not change theirs.
- Toolchains 5.9 and later read `Package@swift-5.9.swift`, which is identical to `Package.swift` except
  that the SwiftyJSON dependency also names Mac Catalyst and visionOS.
