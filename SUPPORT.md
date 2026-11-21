# Support policy

| Line | Status | Branch | Tags |
|---|---|---|---|
| 2.x | Active: features and fixes | `main` | `v2.*` |
| 1.x | Bug fixes until 12 months after the 2.0.0 release date | `release/1.x` | `v1.*` |

The exact 1.x end-of-support date is set when 2.0.0 is released (2.0.0 release date + 12 months).

- Fixes land on `main` first and are cherry-picked to `release/1.x` during the support window.
  Bugs that only exist in 1.x are fixed on `release/1.x` directly.
- Cross-SDK contract changes (assignment, audiences, wire format) are made in both lines.
- 1.x keeps its module (`ABSmartly`) and CocoaPods pod (`ABSmartlySwiftSDK`); 2.x is the module and
  pod `ABsmartly`. A 1.x release never becomes the repository's latest GitHub release.
- Moving from 1.x to 2.x: see [MIGRATING.md](MIGRATING.md).
