#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ "$(uname -s)" != Darwin ]]; then
  echo "iOS builds require macOS and Xcode with an iOS SDK." >&2
  exit 1
fi
mkdir -p artifacts
plutil -lint iOS/MiniRadio.xcodeproj/project.pbxproj iOS/Info.plist iOS/PrivacyInfo.xcprivacy iOS/MiniRadio-CarPlay.entitlements
mac_sdk="$(xcrun --sdk macosx --show-sdk-path)"
xcrun --sdk macosx swift -sdk "$mac_sdk" -target "$(uname -m)-apple-macosx13.0" \
  scripts/make-icon.swift iOS/Assets.xcassets/AppIcon.appiconset --ios
mode="${1:-device}"
if [[ "$mode" == device || "$mode" == carplay ]]; then
  build_kind="ios-device"
  package_name="MiniRadio-iOS-0.3.0-unsigned.ipa"
  signing_options=(CARPLAY_ENTITLEMENTS=)
  if [[ "$mode" == carplay ]]; then
    build_kind="ios-carplay-device"
    package_name="MiniRadio-iOS-0.3.0-CarPlay-unsigned.ipa"
    signing_options=(CARPLAY_ENTITLEMENTS=MiniRadio-CarPlay.entitlements)
  fi
  xcodebuild -project iOS/MiniRadio.xcodeproj -scheme MiniRadio-iOS -configuration Release \
    -destination 'generic/platform=iOS' -derivedDataPath "artifacts/$build_kind" \
    -jobs 2 CODE_SIGNING_ALLOWED=NO "${signing_options[@]}" build
  mkdir -p "artifacts/$build_kind-package/Payload"
  ditto "artifacts/$build_kind/Build/Products/Release-iphoneos/MiniRadio.app" "artifacts/$build_kind-package/Payload/MiniRadio.app"
  (cd "artifacts/$build_kind-package" && ditto -c -k --keepParent Payload "../$package_name")
  (cd artifacts && shasum -a 256 "$package_name" > "$build_kind-SHA256SUMS")
  if [[ "$mode" == device ]]; then cp "artifacts/$build_kind-SHA256SUMS" artifacts/iOS-SHA256SUMS; fi
elif [[ "$mode" == simulator ]]; then
  xcodebuild -project iOS/MiniRadio.xcodeproj -scheme MiniRadio-iOS -configuration Debug \
    -destination 'generic/platform=iOS Simulator' -derivedDataPath artifacts/ios-simulator -jobs 2 build
else
  echo "Usage: scripts/build-ios.sh [device|simulator|carplay]" >&2
  exit 1
fi
