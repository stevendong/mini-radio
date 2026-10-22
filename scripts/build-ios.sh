#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ "$(uname -s)" != Darwin ]]; then
  echo "iOS builds require macOS and Xcode with an iOS SDK." >&2
  exit 1
fi
mkdir -p artifacts
plutil -lint iOS/MiniRadio.xcodeproj/project.pbxproj iOS/Info.plist iOS/PrivacyInfo.xcprivacy
mac_sdk="$(xcrun --sdk macosx --show-sdk-path)"
xcrun --sdk macosx swift -sdk "$mac_sdk" -target "$(uname -m)-apple-macosx13.0" \
  scripts/make-icon.swift iOS/Assets.xcassets/AppIcon.appiconset --ios
mode="${1:-device}"
if [[ "$mode" == device ]]; then
  xcodebuild -project iOS/MiniRadio.xcodeproj -scheme MiniRadio-iOS -configuration Release \
    -destination 'generic/platform=iOS' -derivedDataPath artifacts/ios-device \
    -jobs 2 CODE_SIGNING_ALLOWED=NO build
  mkdir -p artifacts/ios-package/Payload
  ditto artifacts/ios-device/Build/Products/Release-iphoneos/MiniRadio.app artifacts/ios-package/Payload/MiniRadio.app
  (cd artifacts/ios-package && ditto -c -k --keepParent Payload ../MiniRadio-iOS-0.1.0-unsigned.ipa)
  (cd artifacts && shasum -a 256 MiniRadio-iOS-0.1.0-unsigned.ipa > iOS-SHA256SUMS)
elif [[ "$mode" == simulator ]]; then
  xcodebuild -project iOS/MiniRadio.xcodeproj -scheme MiniRadio-iOS -configuration Debug \
    -destination 'generic/platform=iOS Simulator' -derivedDataPath artifacts/ios-simulator -jobs 2 build
else
  echo "Usage: scripts/build-ios.sh [device|simulator]" >&2
  exit 1
fi
