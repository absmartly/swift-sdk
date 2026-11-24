# CocoaPods 1.x validation investigation

## Status

**Blocked; no consumer fix is implemented.** Do not enable `COCOAPODS_PUBLISH` based on this
investigation or the quick podspec check. The pod/module names, public dependency types and
1.x minimum deployment targets remain unchanged. Do not retag `v1.5.0`.

On 2026-11-24 the investigation worker had Linux with Swift 6.4.2, but neither CocoaPods nor
Xcode. `swift test` passed 667 tests. No Apple dependency build or full lint was run there.
The Xcode failures below are the previously documented release blockers, not newly reproduced
results. The new script and manual workflow collect real build evidence without overriding
any deployment targets or modifying global CocoaPods caches.

## Released dependency evidence

These are upstream **source podspecs**, inspected with git, not measurements of installed pods
or a replacement for resolving the CocoaPods spec repository on a Mac:

| Source | Immutable revision | Relevant declaration |
| --- | --- | --- |
| [SwiftyJSON 5.0.2](https://github.com/SwiftyJSON/SwiftyJSON/blob/af76cf3ef710b6ca5f8c05f3a31307d44a3c5828/SwiftyJSON.podspec) | `af76cf3ef710b6ca5f8c05f3a31307d44a3c5828` | macOS 10.9 |
| [PromiseKit 6.22.1](https://github.com/mxcl/PromiseKit/blob/8a98e31a47854d3180882c8068cc4d9381bf382d/PromiseKit.podspec) | `8a98e31a47854d3180882c8068cc4d9381bf382d` | iOS 8, including CorePromise |
| [PromiseKit 8.2.0](https://github.com/mxcl/PromiseKit/blob/2bc44395edb4f8391902a9ff7c220471882a4d07/PromiseKit.podspec) | `2bc44395edb4f8391902a9ff7c220471882a4d07` | macOS 10.13, watchOS 4 |

The existing constraints already admit SwiftyJSON 5.0.2 and PromiseKit 6.22.1. Raising just their
lower bounds does not remove the documented macOS availability and iOS `libarclite` failures.
Using only `PromiseKit/CorePromise` still retains iOS 8. PromiseKit 8 is not a compatible
substitution: the SDK pod supports macOS 10.10 and watchOS 3, and exposes PromiseKit types.
SwiftyJSON also appears in the public API (`ABSmartly.JSON` aliases `SwiftyJSON.JSON`).

[SwiftyJSON upstream PR 1134](https://github.com/SwiftyJSON/SwiftyJSON/pull/1134) was still open
when inspected. It is not a released fix and its proposed target increases must be checked
against 1.x compatibility, not copied blindly.

## Owner decision needed

Prefer compatible upstream backports/releases that fix the dependency builds. If those are not
available, maintaining corrected dependency distributions needs explicit owner approval and a
plan for preserving module/type identity, resolving other pods' dependency constraints, licensing,
updates and eventual CocoaPods distribution. No such distribution is introduced here.

Increasing this SDK's target does not change dependency pod targets. A Podfile `post_install`
override is a per-app workaround, not a durable podspec/consumer fix. Do not suppress compiler
errors, vendor dependencies into the ABSmartly module, or raise the 1.x minimums to make lint green.

## Mac reproduction and acceptance

Use separate clean checkouts for baseline `1dfbec862f6322a3948c8925857422bac369375e` and the
candidate fix. From each checkout, for **each installed Xcode 16.3 and 26 toolchain**, run:

```bash
set -o pipefail
export DEVELOPER_DIR=/Applications/Xcode_16.3.app/Contents/Developer
# Repeat with the actual installed Xcode 26 path and a distinct log filename.
bash scripts/validate-cocoapods.sh 2>&1 | tee /tmp/cocoapods-full-lint-16.3.log
swift test 2>&1 | tee /tmp/swift-tests-16.3.log
```

The baseline checkout predates the script: copy the candidate's script outside both checkouts
and run its two `pod` commands directly from the baseline directory, or run the commands below:

```bash
xcodebuild -version
swift --version
pod --version
pod spec lint ABSmartlySwiftSDK.podspec --quick --allow-warnings
pod lib lint ABSmartlySwiftSDK.podspec \
  --platforms=ios,osx,tvos,watchos --allow-warnings --verbose
```

`--quick` checks metadata only. Only the second command compiles the pod and dependencies for
all four declared platforms. `--allow-warnings` matches the existing packaging policy; it does
not suppress compilation errors. Preserve full logs and record the checkout SHA. Record any
failure before dependency compilation separately from a reproduced compiler failure.

After an approved fix, also install this checkout using `pod 'ABSmartlySwiftSDK', :path => '…'`
in real iOS, macOS, tvOS and watchOS consumer projects with no target-rewriting hooks. Build each
workspace and compile client code importing `ABSmartly`, `SwiftyJSON` and `PromiseKit`, including
assigning SDK JSON and promise results to their dependency types. Record resolved pod versions,
build settings, toolchain, destinations and logs. Verify SwiftPM with `swift test`, the Example
lockfile resolution and the Apple-platform builds already in `.github/workflows/main.yml`.
Modern Xcode's inability to build some historical minimums must be reported, not hidden by
silently changing the podspec or calling a raised-target build minimum-platform validation.

## CI scope

The manual `CocoaPods validation (manual)` workflow runs the full command on Xcode 16.3 and the
current hosted Xcode, retaining logs even on failure. It is diagnostic while the consumer fix is
blocked: it is not a replacement for a passing required packaging gate. GitHub only exposes
`workflow_dispatch` once a workflow exists on the default branch; until then use the local Mac
commands above. Do not merge this maintenance PR into main just to expose that button.
Once a compatible fix is demonstrated, make full lint an automatic PR gate. The existing quick
check remains structural only. No workflow in this investigation enables publication.
