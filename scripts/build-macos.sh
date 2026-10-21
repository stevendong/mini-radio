#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ "$(uname -s)" != Darwin ]]; then
  echo "This script needs macOS 13+ and Xcode command line tools." >&2
  exit 1
fi
export MACOSX_DEPLOYMENT_TARGET=13.0
mkdir -p artifacts
app="$PWD/artifacts/Mini Radio.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
for arch in arm64 x86_64; do
  swift build -c release --product MiniRadio --arch "$arch" --jobs 2
  bin_dir="$(swift build -c release --arch "$arch" --show-bin-path)"
  cp "$bin_dir/MiniRadio" "artifacts/MiniRadio-$arch"
done
lipo -create artifacts/MiniRadio-arm64 artifacts/MiniRadio-x86_64 -output "$app/Contents/MacOS/MiniRadio"
cp Resources/Info.plist "$app/Contents/Info.plist"
swift scripts/make-icon.swift artifacts/AppIcon.iconset
iconutil -c icns artifacts/AppIcon.iconset -o "$app/Contents/Resources/AppIcon.icns"
plutil -lint "$app/Contents/Info.plist" Resources/MiniRadio.entitlements
codesign --force --sign - --entitlements Resources/MiniRadio.entitlements "$app"
codesign --verify --deep --strict --verbose=2 "$app"
lipo -verify_arch arm64 x86_64 "$app/Contents/MacOS/MiniRadio"
ditto -c -k --sequesterRsrc --keepParent "$app" artifacts/MiniRadio-0.1.0-universal.zip
shasum -a 256 artifacts/MiniRadio-0.1.0-universal.zip > artifacts/SHA256SUMS
