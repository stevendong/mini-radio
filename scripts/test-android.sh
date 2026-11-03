#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
SDK=${ANDROID_SDK_ROOT:-${ANDROID_HOME:-"$HOME/Library/Android/sdk"}}
TOOLS="$SDK/build-tools/${ANDROID_BUILD_TOOLS_VERSION:-36.0.0}"
PLATFORM="$SDK/platforms/${ANDROID_PLATFORM:-android-35}/android.jar"
JAVA_BIN=${JAVA_HOME:+"$JAVA_HOME/bin/"}
bash "$ROOT/scripts/build-android.sh"
OUT="$ROOT/artifacts/android"
mkdir -p "$OUT/obj/test-classes" "$OUT/obj/test-dex"
"${JAVA_BIN}javac" --release 8 -encoding UTF-8 -classpath "$PLATFORM:$OUT/obj/classes.jar" \
    -d "$OUT/obj/test-classes" "$ROOT/android/test/com/miniradio/car/RadioInstrumentation.java"
"${JAVA_BIN}jar" cf "$OUT/obj/tests.jar" -C "$OUT/obj/test-classes" .
"$TOOLS/d8" --lib "$PLATFORM" --classpath "$OUT/obj/classes.jar" --min-api 26 --output "$OUT/obj/test-dex" "$OUT/obj/tests.jar"
"$TOOLS/aapt2" link -o "$OUT/obj/tests-unsigned.apk" -I "$PLATFORM" --manifest "$ROOT/android/test/AndroidManifest.xml"
(cd "$OUT/obj/test-dex" && zip -q "$OUT/obj/tests-unsigned.apk" classes.dex)
"$TOOLS/zipalign" -f -p 4 "$OUT/obj/tests-unsigned.apk" "$OUT/obj/tests-aligned.apk"
export MINI_RADIO_STORE_PASSWORD=${MINI_RADIO_STORE_PASSWORD:-android}
export MINI_RADIO_KEY_PASSWORD=${MINI_RADIO_KEY_PASSWORD:-$MINI_RADIO_STORE_PASSWORD}
"$TOOLS/apksigner" sign --ks "${MINI_RADIO_KEYSTORE:-$HOME/.android/mini-radio-development.keystore}" \
    --ks-key-alias "${MINI_RADIO_KEY_ALIAS:-mini-radio}" --ks-pass env:MINI_RADIO_STORE_PASSWORD \
    --key-pass env:MINI_RADIO_KEY_PASSWORD --out "$OUT/MiniRadio-Tests.apk" "$OUT/obj/tests-aligned.apk"
ADB=("$SDK/platform-tools/adb")
if [ -n "${ANDROID_SERIAL:-}" ]; then ADB+=(-s "$ANDROID_SERIAL"); else ADB+=(-d); fi
"${ADB[@]}" install -r "$OUT/MiniRadio-Android-0.4.0.apk"
"${ADB[@]}" install -r "$OUT/MiniRadio-Tests.apk"
"${ADB[@]}" shell am instrument -w com.miniradio.car.tests/com.miniradio.car.RadioInstrumentation | tee "$OUT/test-result.txt"
if ! grep -q 'PASS:' "$OUT/test-result.txt"; then exit 1; fi
"${ADB[@]}" shell am start -n com.miniradio.car/.MainActivity
