#!/usr/bin/env bash
# Run on a Mac with Xcode and CocoaPods installed. No publishing or target overrides.
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
cd "$root"

if [[ $(uname -s) != Darwin ]]; then
  echo 'Full CocoaPods validation requires macOS and Xcode.' >&2
  exit 1
fi

xcodebuild -version
swift --version
pod --version

# This checks metadata only; the lib lint below must also pass.
pod spec lint ABSmartlySwiftSDK.podspec --quick --allow-warnings
pod lib lint ABSmartlySwiftSDK.podspec \
  --platforms=ios,osx,tvos,watchos --allow-warnings --verbose
