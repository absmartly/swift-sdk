# Changelog

## 2.2.0 (unreleased)

Switchback experiments, matching the Java SDK (java-sdk#15, 1.10.0) and the JavaScript SDK
(javascript-sdk#69, 1.14.1). The `X-Agent` header is `absmartly-swift-sdk/2.2.0`. A payload without
switchbacks is served and published exactly as in 2.1.0.

### Added
- Switchback experiments (R33, cluster-defined). An experiment with `randomizationType: "switchback"` is served by cluster and time: the first context unit, in `switchbackClusters` order, whose attribute path gives a value serves it, and the variant is the balanced-block draw for that raw cluster key and the period `floorDiv(now - switchbackStartAt, switchbackPeriodMs)`. Units that disagree, a value outside `switchbackClusterValues`, a missing value, no linked unit, a time before `switchbackStartAt` or an unservable schedule (an anchor that is unset, not hour aligned or out of range, a period that is not positive, fewer than two arms) give control with no exposure on the normal draw path. Overrides still win; with an eligible cluster, rules, a strict audience and full-on are evaluated even before the anchor or on an unservable schedule.
- Precedence: an override, then a matching assignment rule (a split rule randomizes over the serving unit), then a strict audience mismatch, then full-on, then traffic (on the serving unit), then a custom assignment, then the draw. Exposure flags are those of a unit experiment in the same case. Holdouts never apply to a switchback.
- One exposure per experiment and period, stamped with the clock reading that chose the period (a read takes one reading); an assignment re-resolved within the period (an override or custom assignment change, or a rule or audience result that changes after `setAttribute`) publishes its own, and a period older than the two remembered exposes again. The cluster is read once per period, from the latest attribute set at or before the read. The two most recent periods stay cached.
- A refresh keeps a switchback's cached periods while its identity (id, iteration, the ordered cluster map, `switchbackClusterValues`, `switchbackStartAt`, `switchbackPeriodMs`, `switchbackDesignType`) is unchanged; seed, split and the analysis-only fields are not identity.
- `Experiment` fields `randomizationType` (now public), `switchbackClusters` (`[SwitchbackCluster]`, in declared order), `switchbackClusterValues`, `switchbackStartAt`, `switchbackPeriodMs`, `switchbackCarryoverDurationMs`, `switchbackBurnInDurationMs`, `switchbackBurnOutDurationMs`, `switchbackDesignType` and `switchbackEstimand`, all optional. A field of the wrong shape is nil on its own; an integer or boolean allow-list entry is compared by its text, as in Java and JavaScript, and an allow-list that is not an array, or has another kind of entry, drops the cluster map with it, so the switchback serves only control.
- Malformed switchback input is handled more strictly than in Java and JavaScript, which the backend's payloads never trigger: a `switchbackClusters` object with a repeated key (`"a"` twice, or `"a"` and `"\u0061"`) or a repeated member, and an allow-list with a floating-point, `null` or out-of-range entry, both drop the cluster map, so the switchback serves only control. Java and JavaScript keep the last repeated value and skip or stringify such entries.
- `ContextData(json:)` decodes the body of `GET /context` keeping each `switchbackClusters` object in its JSON key order; the SDK's own fetch uses it. `JSONDecoder().decode(ContextData.self, from:)` still works but cannot see that order, so a switchback with more than one linked unit type decoded that way has no cluster map and cannot draw: it serves control, though an override still applies (and logs an error). Encoding writes the cluster map as an ordered array, which round-trips through any decoder.
- `Diagnostics.switchbackVariant(clusterUnit:periodIndex:seed:armCount:)` and `Diagnostics.switchbackPermutation(clusterUnit:cycleIndex:seed:armCount:)` (`@_spi(Diagnostics)`), the platform's schedule draw, for conformance tooling.

### Changed
- In a context whose data has a switchback, a floating-point attribute value is published with its float syntax (`3.0`, not `3`), so the Collector reads the same non-value the SDK served; matching of cluster values, allow-lists and paths is exact (by UTF-8 bytes, as in Java and JavaScript), so canonically equivalent but differently encoded strings are different clusters. Contexts without switchbacks publish exactly as in 2.1.0.
- Apps on 2.1.x whose payload contains switchback experiments: 2.1.x served them as unit experiments (a sticky assignment from `split`/`seedHi`/`seedLo` on `unitType`); 2.2.0 serves the cluster's variant for the current period and publishes under the serving unit, once per period, so assignments and exposure counts for those experiments change.
- The `X-Agent` header is `absmartly-swift-sdk/2.2.0`, so the collector's `agent` column shows 2.2.0 for these clients.

## 2.1.0 (2026-11-27)

**Distribution: Swift Package Manager only.** No CocoaPods release is published for 2.1.0.
The last available CocoaPods version is `ABSmartlySwiftSDK` 1.3.4 (legacy 1.x), not `ABsmartly`
2.0.0 or 2.1.0. Install 2.1.0 through SwiftPM to use holdouts and the 2.x API.

Holdouts, matching 1.5.0 and the JavaScript SDK. The `X-Agent` header is `absmartly-swift-sdk/2.1.0`.
2.0.0 ignored the payload's holdout data; 2.1.0 applies it, so apps on 1.5.x that rely on holdouts
can move to 2.x.

### Added
- Holdouts. `ContextData.holdouts` lists the holdouts and `Experiment.holdoutIds` the ones covering each experiment (`Experiment.holdoutType` is informational: arms come from the holdout's `split`). A unit held out by any covering holdout gets control (variant `0`) and its control variables, and the experiment publishes no exposure of its own; each covering holdout publishes its own exposure (its name and arm) once per arm, the first time an exposing read meets it, even when the unit is not held out. Arm 0 holds the unit out; in a three-arm holdout, arm 1 holds out only experiments that are not full-on.
- An override or a matching assignment rule still wins over a holdout, and the experiment's own exposure is still published; a custom assignment does not.
- Peeking (`exposing: false`) publishes nothing, holdout exposures included.
- `variable(_:default:)` and `variableValue(_:)`: when no candidate experiment wins a shared key and the unit is held out of one, the first held-out candidate's control value is returned (nil, or the default, when its control does not define the key). The holdouts of every candidate visited publish their exposures.
- A refresh keeps a unit's holdout arms and exposures while the holdout's iteration is unchanged (a same-iteration seed or split edit changes nothing); a new iteration, or a change in which holdouts cover an experiment, re-resolves it.
- Holdouts never apply to a switchback experiment (`randomizationType: "switchback"`).
- A malformed holdout entry, a holdout with an empty or missing `split`, or a malformed or unknown id in `holdoutIds` is ignored on its own.
- `ContextData(experiments:holdouts:)` and `Experiment(...holdoutIds:holdoutType:)` initializers.

### Changed
- Apps on 2.0.x whose context payload contains holdouts: a held-out unit now gets control for each covered experiment, and the holdout's exposure replaces that experiment's own, so assignments and exposure counts change. 2.0.0 ignored the holdout data.
- The `X-Agent` header is `absmartly-swift-sdk/2.1.0`, so the collector's `agent` column shows 2.1.0 for these clients.

## 2.0.0 (2026-11-25)

A new API for Swift 6 over the 1.5.0 engine. Assignment, audiences, assignment rules, exposures,
goals and the publish payload retain 1.5.0 behaviour apart from holdouts (below) and the extreme
unsigned-number rounding described in [MIGRATING.md](MIGRATING.md#behaviour-notes) (a parity test replays 1.5.0's
recorded output); the `X-Agent` header is `absmartly-swift-sdk/2.0.0`. See [MIGRATING.md](MIGRATING.md) for every
1.x API and its replacement, and [SUPPORT.md](SUPPORT.md) for the 1.x support window.

**2.0.0 does not support holdouts.** Holdout data in the context payload (`holdouts`, `holdoutIds`)
is ignored, as 1.4.0 ignored it: every unit is assigned and exposed as if no holdout existed, and no
holdout exposure is published. Apps that rely on holdouts should stay on 1.5.x, which supports them
(released, and maintained on `release/1.x`). Holdouts come in a later 2.x
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
- A NaN or infinite number in a goal property or attribute is published as `null`, as JavaScript's `JSON.stringify` writes it. Affects apps that track such values: the collector now receives the goal or attribute with a `null` value. 1.5.0 could not encode such a batch and re-queued it, so no later publish or `close()` of that context succeeded. This applies to the SDK's own encoding (the publish payload and `JSONValue.description`); encoding a `JSONValue` with your own `JSONEncoder` follows its `nonConformingFloatEncodingStrategy`.
- A `boolean` custom field is `true` only for exactly `"true"` and `false` for anything else (including `"TRUE"`), as in JavaScript; 1.5.0 returned no value for text other than exactly `"true"` or `"false"`.
- `ABsmartlyError` may gain cases in later 2.x releases; a `switch` over it needs a `default` case.
- A failed context's `contextData` is an empty `ContextData`, as in JavaScript (1.5.0's `getContextData()` returns `nil`).
- `close()` succeeds only once nothing is queued or in flight: an automatic publish that starts while it closes is waited for and its batch sent (as in 1.5.0). When the final publish fails, the reopened context schedules its usual automatic publish to retry the re-queued events (a negative `publishDelay` still needs `publish()` or `close()`). A goal tracked once `close()` has started is rejected with an `.error` event instead of being left queued.
- A refresh whose fetch completes after `close()` has started installs nothing and logs no event, whether the fetch succeeds or fails (a failure is still thrown to the caller), as in 1.5.0.
- `refresh()` on a failed context succeeds without fetching, and the context stays failed, as in the Java and JavaScript SDKs (1.5.0 fetches again and can recover it). A negative `publishDelay` disables automatic publishing, as in 1.5.0; `publish()` and `close()` still send.
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
- `EventLogger.osLog`. It logs what happened (event kind, error kind, HTTP status) publicly and everything from the payload or the caller (experiment, goal and field names, goal properties, attributes, context data, error text) as private data, which the unified log redacts unless the device is set up to show it. The SDK's own diagnostics (malformed configs, custom fields, regex patterns, audiences) do the same.
- A `refresh()` that completes while the first fetch is still pending makes the context ready, and every `ready()` caller (waiting or later) succeeds; the first fetch's late result, data or error, is ignored. If the first fetch fails first, the context stays failed and an overlapping refresh does not change it (`refresh()` on a failed context does not recover it, as before).

### Dependencies
- None linked on Apple platforms: PromiseKit, SwiftyJSON and swift-atomics are gone; MD5 comes from CryptoKit. `swift-crypto` (`3.0.0..<5.0.0`) is linked on Linux only (SwiftPM still downloads it, and swift-asn1, when resolving on Apple platforms).

### Release
- The publish workflow creates the GitHub release; 1.x tags are created with `--latest=false`. CI runs on `main` and `release/**`.
- The CocoaPods trunk is read-only from 2026-12-02. A 2.0 pod can only be published before then; afterwards 2.x is distributed through Swift Package Manager.

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
