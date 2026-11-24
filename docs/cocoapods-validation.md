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

These are hard build errors, not warnings: the probe pods were linted with `--allow-warnings` and
still failed. Exact lines from the run logs (SDK, macOS; dependency-free probe, iOS):

```text
error: The macOS deployment target 'MACOSX_DEPLOYMENT_TARGET' is set to 10.10, but the range of supported deployment target versions is 12.0 to 27.2.x. (in target 'ABSmartlySwiftSDK' from project 'Pods')
error: The iOS Simulator deployment target 'IPHONEOS_DEPLOYMENT_TARGET' is set to 10.0, but the range of supported deployment target versions is 15.0 to 27.2.x. (in target 'ProbeSDKTargets' from project 'Pods')
```

So on Xcode 27.2 no dependency change (newer releases, pinned forks or vendored code) can make
`pod lib lint` pass while the podspec declares the 1.x targets. The iOS lint in runs 1 and 2
also crashed in CocoaPods' simulator lookup (fourflusher, the simulator picker) before building,
differently in each run (see "Mac reproduction and acceptance"); that is a tooling problem on the validating Mac, not a podspec defect.

### Consumers versus lint and trunk

**Existing pod users can build 1.x on Xcode 27.2 today.** Mac run 3 (reported by the coordinator
as the same SHA and toolchain; its log bundle has the install/build logs but no environment file
or Podfile) installed the **unchanged** podspec from a checkout with trunk dependencies (PromiseKit 6.18.1,
SwiftyJSON 5.0.2, SwiftAtomics/SwiftAtomicsShims 1.0.2) into a consumer Podfile with the common
`post_install` hook that raises every pod target below the app's platform to it (run 3 set
them unconditionally; with these pods, all below the floor, that is the same build):

```ruby
post_install do |installer|
  installer.pods_project.targets.each do |target|
    target.build_configurations.each do |config|
      # Only raise: a pod that already needs a newer OS keeps its own target.
      if Gem::Version.new(config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] || '0') < Gem::Version.new('15.0')
        config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '15.0'
      end
    end
  end
end
```

`pod install` and an `xcodebuild` of the SDK target with all dependencies succeeded on iOS 15,
macOS 12 and watchOS 9 (0 errors; tvOS not run, no runtime installed). So with the 1.x targets the
blocker is lint and trunk publication, not consumer builds.

**Lint and trunk cannot pass with released dependencies.** Mac run 2 linted a copy of the podspec
raised to the floor (iOS 15, macOS 12, tvOS 15, watchOS 9) against the trunk dependencies. macOS
and watchOS reached the build and failed **only** on the dependency pods, each built at its own
declared target (PromiseKit, SwiftAtomics, SwiftAtomicsShims at macOS 10.10 / watchOS 2.0 or 3.0;
SwiftyJSON at macOS 10.13 / watchOS 4.0). CocoaPods does not lift a dependency to its dependent's
target, and lint runs no consumer hooks, so a podspec only lints on Xcode 27.2 if **every pod in
its graph** declares targets at or above the floor.

No trunk release of any dependency does: SwiftyJSON 5.0.2 (iOS 12, macOS 10.13, tvOS 9, watchOS 4),
PromiseKit 6.18.1, the newest 6.x on trunk (iOS 8, macOS 10.10, tvOS 9, watchOS 2), PromiseKit 8.2.0
(iOS 10, macOS 10.13, tvOS 10, watchOS 4), SwiftAtomics / SwiftAtomicsShims 1.0.2 (iOS 10,
macOS 10.10, tvOS 10, watchOS 3). `pod trunk push` resolves dependencies from trunk only, and a
podspec cannot depend on a git URL or commit, so no change to this repository alone can make a
trunk push pass. Linting against locally raised dependency specs (Mac run step C) can at most show
that the SDK compiles at the floor; it can never stand in for a trunk push. It has not shown even
that yet: in run 2 step C failed before building (`No podspec found for SwiftAtomics.podspec`, a
script naming bug), and in run 3 it built but every platform ended in `BUILD FAILED` with
`Unable to resolve module dependency: 'PromiseKit' / 'Atomics' / 'SwiftyJSON'` in the SDK target.
Run 3 included the raised specs with `:path`, so CocoaPods looked for their sources next to the
spec files and built empty dependency frameworks; the next run uses `:podspec`, which downloads
the sources from each spec's git tag. Until a step C passes, a fully raised graph is expected,
not demonstrated, to lint.

### Options for the owner

1. **Publish a 1.x pod at Xcode's floor.** Raise the CocoaPods-only targets (SwiftPM unchanged)
   **and**, before trunk goes read-only, get every dependency pod onto trunk at the floor:
   - **SwiftAtomics / SwiftAtomicsShims:** a 1.0.3 with raised targets. Its trunk source is
     `marcioapm/swift-atomics`, so it is likely in ABsmartly's reach (trunk ownership unconfirmed;
     it also changes the pod for its other users).
   - **SwiftyJSON 5.x and PromiseKit 6.x:** only their maintainers can push new versions under those
     names. The alternative is ABsmartly-owned forks under new pod names that keep the module names
     `SwiftyJSON` and `PromiseKit` (public types unchanged); an app that also uses the real pods then
     has two pods for one module and fails to build, and ABsmartly maintains the forks.
   - Vendoring the dependency sources into the `ABSmartly` module would change the public types,
     so it is ruled out.

   Expected gain (not yet demonstrated; see step C above): pod users get a lint-validated pod
   without a Podfile hook. Cost: apps below the raised
   targets cannot take it; the dependency publishing above, before 2026-12-02.
2. **Lint and publish on an older Xcode** that still accepts the 1.x targets, podspec unchanged.
   Still hits the secondary dependency blocker below and depends on runners keeping that Xcode.
   Consumers on current Xcode use the hook above, which run 3 showed works.
3. **Stop publishing 1.x to trunk; document the consumer path.** Trunk stays at 1.3.4. 1.x is
   supported through SwiftPM, and pod users can take 1.5.x from the git tag
   (`pod 'ABSmartlySwiftSDK', :git => 'https://github.com/absmartly/swift-sdk.git', :tag => 'v1.5.0'`)
   with the hook above, which run 3 measured on iOS, macOS and watchOS. No publication needed.

CocoaPods trunk becomes read-only on 2026-12-02, so options 1 and 2 need an owner-authorized
publication (for option 1, including the dependency pods) before then.

### Secondary blocker: dependency pods on older Xcode

The previously documented failures (SwiftyJSON 5 availability errors on macOS, PromiseKit 6's iOS 8
target needing the removed `libarclite`) were reported on Xcode 16.3 and 26 and were not re-run
here. They matter for option 2. For option 1 they are superseded: run 2 measured that CocoaPods does
not lift dependency targets, so the dependency pods need raised trunk releases either way.

## Released dependency evidence

These are upstream **source podspecs**, inspected with git, not measurements of installed pods
or a replacement for resolving the CocoaPods spec repository on a Mac:

| Source | Immutable revision | Relevant declaration |
| --- | --- | --- |
| [SwiftyJSON 5.0.2](https://github.com/SwiftyJSON/SwiftyJSON/blob/af76cf3ef710b6ca5f8c05f3a31307d44a3c5828/SwiftyJSON.podspec) | `af76cf3ef710b6ca5f8c05f3a31307d44a3c5828` | macOS 10.9 |
| SwiftyJSON 5.0.2 (CocoaPods trunk) | trunk spec `SwiftyJSON/5.0.2` | iOS 12, macOS 10.13, tvOS 9, watchOS 4 (differs from the git tag; so with the 1.x targets the resolver picks 5.0.1, which declares macOS 10.9, for iOS, macOS and watchOS, as Mac runs 1 and 2 installed; tvOS, where 5.0.2's tvOS 9 fits, got 5.0.2) |
| [PromiseKit 6.22.1](https://github.com/mxcl/PromiseKit/blob/8a98e31a47854d3180882c8068cc4d9381bf382d/PromiseKit.podspec) | `8a98e31a47854d3180882c8068cc4d9381bf382d` | iOS 8, including CorePromise (GitHub only; see below) |
| PromiseKit 6.18.1 (CocoaPods trunk) | trunk spec, installed in the Mac run | iOS 8, watchOS 2 (Mac run: `PromiseKit` target built at watchOS 2.0) |
| SwiftAtomics 1.0.2 (CocoaPods trunk) | trunk spec `SwiftAtomics/1.0.2` | iOS 10, macOS 10.10, tvOS 10, watchOS 3 |
| [PromiseKit 8.2.0](https://github.com/mxcl/PromiseKit/blob/2bc44395edb4f8391902a9ff7c220471882a4d07/PromiseKit.podspec) | `2bc44395edb4f8391902a9ff7c220471882a4d07` | macOS 10.13, watchOS 4 |

The newest PromiseKit 6.x on the CocoaPods trunk is 6.18.1, which is what `~> 6.8` resolves to for
pod users (the Mac run installed it); 6.19 to 6.22.1 were released on GitHub only. SwiftAtomics
1.0.2 is the only trunk version and declares exactly the 1.x targets, so it is below Xcode 27.2's
floor too. The existing constraints already admit SwiftyJSON 5.0.2 and PromiseKit 6.18.1. Raising just their
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

CocoaPods 1.17.0 (fourflusher 2.3.1) crashed reading the simulator list before building iOS:
run 1 failed in `JSON.parse` on non-JSON lines in `xcrun simctl list -j devices` output
(`unexpected token at end of stream 'Install'`), and run 2, with those lines stripped but no
trailing newline, failed appending the nil `$INPUT_RECORD_SEPARATOR` (`no implicit conversion of
nil into String`). For iOS/tvOS lint, put `scripts/xcrun-simctl-json.sh` first on `PATH` as
`xcrun`: for `simctl list ... -j` it prints only the JSON object, ending in a newline, and passes
every other call through. It changes how the simulator list is read, not what is built. It is unit-tested
(`scripts/test-validate-cocoapods.py`) but has not yet been used in a full `pod lib lint` run.

```bash
mkdir -p /tmp/xcrun-shim && cp scripts/xcrun-simctl-json.sh /tmp/xcrun-shim/xcrun
export PATH="/tmp/xcrun-shim:$PATH"
```

macOS and watchOS lint do not look up a simulator and are unaffected.

Use separate clean checkouts for baseline `1dfbec862f6322a3948c8925857422bac369375e` and the
candidate fix. From each checkout, for **each installed Xcode 16.3, 26 and 27.2 toolchain**, run:

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
