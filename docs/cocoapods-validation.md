# CocoaPods 1.x validation investigation

## Status

**Blocked on an owner decision; no consumer fix is implemented.** Do not enable
`COCOAPODS_PUBLISH` based on this investigation or the quick podspec check. The pod/module names,
public dependency types and 1.x minimum deployment targets remain unchanged. Do not retag `v1.5.0`.

### Primary blocker: current Xcode's deployment-target floor

Mac run on `d089977cc3aa1ae61e8d657e8b1feff125a6f957` (2026-11-24; Xcode 27.2 build 27B52,
macOS 26.6.2, Swift 6.4.2, CocoaPods 1.17.0): `swift test` passed 670 tests and
`pod spec lint --quick` passed, but every `pod lib lint` failed. Xcode 27.2 rejects deployment
targets below its supported range, for this SDK and for dependency-free probe pods alike:

| Platform | 1.x podspec declares | Xcode 27.2 supported range |
| --- | --- | --- |
| iOS | 10.0 | 15.0 to 27.2.x |
| macOS | 10.10 | 12.0 to 27.2.x |
| watchOS | 3.0 | 9.0 to 27.2.x |
| tvOS | 10.0 | not measured (no tvOS simulator runtime installed) |

So on Xcode 27.2 no dependency change (newer releases, pinned forks or vendored code) can make
`pod lib lint` pass while the podspec declares the 1.x targets. The iOS lint in that run also
crashed in CocoaPods' simulator lookup (fourflusher could not parse `simctl list -j` output)
before building; that is a tooling problem on the validating Mac, not a podspec defect.

### Options for the owner

1. **Raise only the CocoaPods deployment targets in a 1.x release** to the validating Xcode's
   floor (iOS 15, macOS 12, watchOS 9, tvOS to be measured). SwiftPM keeps iOS 10 / macOS 10.14 /
   tvOS 10 / watchOS 3, and the public API is unchanged. Pod users whose apps target lower OS
   versions cannot take the new pod and stay on trunk 1.3.4. Whether the trunk dependency pods
   (declared below the floor) then lint is still to be measured.
2. **Lint and publish on an older Xcode** that still accepts the 1.x targets. The podspec is
   unchanged, but this still hits the secondary dependency blocker below, depends on hosted
   runners keeping that Xcode, and ships a pod that current Xcode cannot lint.
3. **Stop shipping 1.x through CocoaPods.** Trunk stays at 1.3.4, 1.x is SwiftPM-only, and pod
   users must move to SwiftPM for 1.4.0+.

CocoaPods trunk becomes read-only on 2026-12-02, so options 1 and 2 also need an owner-authorized
publication before then.

### Secondary blocker: dependency pods on older Xcode

The previously documented failures (SwiftyJSON 5 availability errors on macOS, PromiseKit 6's iOS 8
target needing the removed `libarclite`) were reported on Xcode 16.3 and 26 and were not re-run
here. They matter for option 2, and possibly for option 1 if CocoaPods does not lift dependency
targets to the SDK's raised ones.

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

## Dependency remediation (older Xcode)

Prefer compatible upstream backports/releases that fix the dependency builds. If those are not
available, maintaining corrected dependency distributions needs explicit owner approval and a
plan for preserving module/type identity, resolving other pods' dependency constraints, licensing,
updates and eventual CocoaPods distribution. No such distribution is introduced here.

Increasing this SDK's target does not change dependency pod targets. A Podfile `post_install`
override is a per-app workaround, not a durable podspec/consumer fix. Do not suppress compiler
errors, vendor dependencies into the ABSmartly module, or raise the 1.x minimums to make lint green
without the owner choosing option 1.

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
