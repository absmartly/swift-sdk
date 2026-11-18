# 1.x test suite port

Every 1.x test file was ported to swift-testing against the 2.0 API except
`SwiftyJSONCompatibilityTest.swift` (see below). This records, per file, what a
1.x test maps to and the tests that were not ported (or only partly), with the reason. It replaces
the porting notes that used to head each test file.

## `ABsmartlyClientTests.swift`

Ported from 1.x ABSmartlySDKTest.swift and ContextConfigTest.swift.

Not ported: ABsmartlySDKTest.testThrowsWithInvalidConfig — 2.0 has no `Client` to leave out ("Missing
  Client instance"): the client is the SDK itself, and the transport defaults to URLSessionTransport.
Not ported: ABsmartlySDKTest.testClose — 2.0's client has no close(); contexts are closed individually
  and the transport has no lifecycle.
Not ported: ABsmartlySDKTest.testBackwardsCompatibility — ClientConfig/DefaultClient/ABsmartlyConfig were
  replaced by ABsmartlyClient.Configuration by design (no 1.x compat shim, decision 7).
ContextConfig no longer exists: its tests are ported to the creation parameters that replace it.

## `ConcurrencyTests.swift`

Port of the 1.x ConcurrencyTests.swift (7 tests) to the 2.0 API. Work that 1.x dispatched onto a
concurrent DispatchQueue runs in a task group here, which spreads it over the cooperative pool's
threads in the same way. Every test is ported.

## `ConnectionTests.swift`

Ported from 1.x DefaultClientTest.swift (the SDK's request building, status handling and
(de)serialisation, now `Connection`) and the retry part of DefaultHTTPClientTest.swift
(`DefaultHTTPClient.retry`, now `Connection.send`'s loop over the `Transport`).

Not ported: DefaultClientTest.testClose — neither the client nor the transport has a close() in 2.0.
Not ported: DefaultHTTPClientTest.testRetryStaticMethod as a static generic helper — 2.0 has no
  PromiseKit `retry(times:delay:body:)`; the same assertions (fail twice, succeed on attempt 3) are
  `retriesTransportErrorsUntilSuccess`.

## `ContextAssignmentRulesTests.swift`

Port of the 1.x ContextAssignmentRulesTest.swift (30 tests) to the 2.0 API.

Partly ported:
- testSameOutcomeRevalidationIsNotRepeated, its `matcher.evaluations` counts — 1.x injected a
  subclassed `AudienceMatcher` to count audience evaluations; 2.0's matcher is a stateless enum
  with no injection point, by design. The observable assertions (same variant, peek and variable
  on every read, a single exposure across an unrelated attribute change and a refresh whose rules
  changed without changing the outcome) are ported.

## `ContextTests.swift`

Port of the 1.x ContextTest.swift (151 tests) to the 2.0 API. The tests are split over
ContextTests.swift, ContextTests+Treatments.swift, ContextTests+Publishing.swift,
ContextTests+Refresh.swift and ContextTests+Behaviour.swift, all in the `ContextTests` suite.

Mapping: 1.x's pending/fulfilled/rejected data promise is a context loaded through the
`FakeTransport` (a `Gate` holds the GET open; a thrown `TestError(message)` arrives as
`.transport(message)`); the publish handler mock is the PUTs the transport records; the scheduler
mock is real timers with short delays; the logger mock is `LoggedEvents`.

Not ported (or only partly ported):
- testJsonCustomFieldObjectUsesConfiguredVariableParser — 2.0 has no pluggable VariableParser by
  design (custom fields and variables are parsed by the SDK).
- testCompletionEventsAreDeliveredOnTheMainThread — needs `Context.deliversEventsOnMainThread`
  flipped to true, a process-wide test hook that every `Harness` resets to false; swift-testing
  runs suites in parallel, so flipping it would race with every other suite.
- testCloseEventKeepsItsCaseName, its `ContextEventLoggerEvent.finalize == .close` assertion — the
  `.finalize` alias is dropped in 2.0 by design. The `.close` delivery part is ported.
- testNumericUnitsKeepTheirTypeAndHashLikeJavaScript, its `setUnit(unitType:value: JSON(true))`
  assertions ("must be a string or a number") — 2.0's `setUnit` only accepts String, Int and
  Double, so a non-string, non-number UID cannot be expressed. The rest is ported.
- testHashingHelpers, its `Hashing.utf8Bytes` assertion — the helper is gone in 2.0 (hashing uses
  `String.utf8`). The base64url assertions are ported.

## `ErrorTests.swift`

Ported from 1.x PublicErrorFormattingTest.swift: formats SDK errors the way an app does, through
the public API only (no `@testable`). On Linux with Swift 6.0 and 6.1, `localizedDescription`
crashed for class-based errors; 2.0's error is an enum, and transport errors that are classes are
read safely when wrapped.

Not ported: PublicErrorFormattingTest.testLocalizedDescriptionOfABSmartlyError's `ABSmartlyError("…")`
  initialiser and `errorMessage` property — 2.0's `ABsmartlyError` is an enum with fixed cases; the
  formatting assertions are ported per case in ErrorTests.swift.

## `JSONValueTests.swift`

Ported from 1.x JSONComparisonTest.swift (SwiftyJSON `JSON` equality, now `JSONValue`), plus the
`JSONValue` type's own tests.

Not ported: the ordering assertions (<, >, <=, >=) of JSONComparisonTest.testNumberOrdering,
  testParsedValuesCompareLikeLiterals, testBoolIsNotANumber, testBoolComparisons and
  testStringComparisons — `JSONValue` is not `Comparable` by design (SwiftyJSON's operators were only
  kept for 1.x source compatibility; the SDK orders values with the expression evaluator's own
  comparison, covered by the JsonExpr tests). Their equality assertions are ported in JSONValueTests.swift.
Not ported: JSONComparisonTest's `.type` checks (`.number`/`.bool`) as such — `JSONValue` has cases
  instead of a type enum; mapped to case checks.

## `ModelTests.swift`

Ported from 1.x ContextDataDeserializerTest.swift, ContextEventSerializerTest.swift and
DefaultVariableParserTest.swift.

Not ported: ContextDataDeserializerTest.testApplicationIsAReferenceType (the `AnyObject` half) — 1.x
  kept `Application` a class for source compatibility; 2.0's `ExperimentApplication` is a `Sendable`
  struct by design. Its equality assertion is ported in `applicationEquality`.
DefaultVariableParser is internal to `DataIndex` in 2.0; its tests go through `JSONValue(parsing:)`
(the parser it uses) and through a context's variables.

## `URLSessionTransportTests.swift`

Ported from 1.x DefaultHTTPClientTest.swift and HTTPIntegrationTest.swift: `URLSessionTransport`
(1.x DefaultHTTPClient) over a real `URLSession`, with a `URLProtocol` stub and a real local HTTP
server on 127.0.0.1.

Not ported: DefaultHTTPClientTest.testCloseInvalidatesSession — `URLSessionTransport` has no close();
  the SDK has no client-wide shutdown in 2.0 (contexts close individually).
Not ported: DefaultHTTPClientTest.testRetryStaticMethod — retries moved out of the transport into the
  SDK (`Connection`); ported as ConnectionTests.retriesTransportErrorsUntilSuccess.
DefaultHTTPClientTest.testDefaultHTTPResponse maps to `HTTPResponse`, which has no status message or
  content type in 2.0 (the SDK derives the message from the code); the remaining fields are checked.

## `Hashing/MD5Tests.swift`

Ported from 1.x Internal/MD5Test.swift. 1.x had `Hashing.hash(_:) -> String` and
`Hashing.hashBytes(_:) -> [UInt8]`; 2.0 has only `Hashing.hashUnit(_:) -> [UInt8]` (the ASCII
bytes of the base64url MD5), so `hash` is that decoded as a string.

## `Hashing/MurmurHashTests.swift`

Ported from 1.x Internal/MurmurHashTest.swift.

## `Hashing/VariantAssignerTests.swift`

Ported from 1.x VariantAssignerTest.swift.

## `JsonExpr/AudienceMatcherTests.swift`

Ported from 1.x AudienceMatcherTest.swift. 1.x's `evaluate` took the audience string; 2.0 parses
it once (`parseAudience`) and evaluates the parsed filter.

## `JsonExpr/ExprEvaluatorTests.swift`

Ported from 1.x JsonExpr/ExprEvaluatorTest.swift. 1.x injected mock operators into the evaluator;
in 2.0 the operators are a switch in `ExprEvaluator.apply`, so the dispatch tests evaluate real
expressions and observe whether an argument was evaluated through `evaluationProbe`. 1.x's
`numberConvert` and `stringConvert` returned `JSON.null` for "no value"; 2.0 returns nil.

## `JsonExpr/JsonExprTests.swift`

Ported from 1.x JsonExpr/JsonExprTest.swift.

## `JsonExpr/Operators/BinaryOperatorNullSafetyTests.swift`

Ported from 1.x JsonExpr/Operators/BinaryOperatorNullSafetyTest.swift. Where 1.x asserted
`result.boolValue` is false, the result is also pinned to null, which is what 1.5.0 returns.

## `JsonExpr/Operators/CombinatorTests.swift`

Ported from 1.x JsonExpr/Operators/AndCombinatorTest.swift and OrCombinatorTest.swift. 1.x counted
the mock evaluator's `evaluate` and `booleanConvert` calls; here short-circuiting is checked by
putting an `evaluationProbe` after the deciding item and asserting it was never evaluated.

## `JsonExpr/Operators/ComparisonOperatorTests.swift`

Ported from 1.x JsonExpr/Operators/EqualsOperatorTest.swift, GreaterThanOperatorTest.swift,
GreaterThanOrEqualOperatorTest.swift, LessThanOperatorTest.swift and
LessThanOrEqualOperatorTest.swift. 1.x also asserted the mock evaluator's `evaluate` and
`compare` call counts and arguments; those are internals of the switch in 2.0. What they pinned
is kept: a null left operand stops before the right one is evaluated (checked with an
`evaluationProbe`), and each result comes from comparing the two operands.

## `JsonExpr/Operators/InOperatorTests.swift`

Ported from 1.x JsonExpr/Operators/InOperatorTest.swift. 1.x also asserted the mock evaluator's
`evaluate`, `stringConvert` and `compare` call counts and arguments (internals of 2.0's switch);
the results are asserted unchanged, and an array haystack's early exit on the first match is
checked by result only.

## `JsonExpr/Operators/MatchOperatorTests.swift`

Ported from 1.x JsonExpr/Operators/MatchOperatorTest.swift.

## `JsonExpr/Operators/SemverOperatorTests.swift`

Ported from 1.x JsonExpr/Operators/SemverOperatorTest.swift.

Not ported: testNumberConversionIsLocaleIndependent — it set the 1.x evaluator's public
`formatter.locale` to ar_EG/fa_IR/de_DE; 2.0's formatter is a private implementation detail with
no way to change its locale. `jsNumberString` (what semver uses for numbers) never touches a
formatter, and `numberConversionMatchesJavaScript` pins its output.

## `JsonExpr/Operators/UnaryOperatorTests.swift`

Ported from 1.x JsonExpr/Operators/NotOperatorTest.swift, NullOperatorTest.swift,
ValueOperatorTest.swift and VarOperatorTest.swift. 1.x's mock evaluator returned "abc" for the
path "a/b/c"; here the variables hold that value. "evaluate is not called" (value, var) is
checked by passing an `evaluationProbe` as the argument.

## `PerformanceTests.swift`

Ported from 1.x PerformanceTests.swift. 1.x wrapped each workload in XCTest's `measure`, which
runs the block 10 times and reports timings without asserting on them. swift-testing has no
`measure`, so each workload runs 10 times (`measured`) under a generous 10 s bound, which only a
pathological regression (or a hang) would hit; the 1.x assertions on the results are kept.

## `SwiftyJSONCompatibilityTest.swift` (1.x, 2 tests)

Not ported: both tests checked that `ABSmartly.JSON` was SwiftyJSON's `JSON` on Apple platforms (so
  apps could pass SwiftyJSON values to the SDK). 2.0 replaces `JSON` with its own `JSONValue` and
  depends on no SwiftyJSON, so there is no interop to test; `JSONValueTests.swift` covers `JSONValue`.
