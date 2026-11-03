#!/usr/bin/env bash
set -euo pipefail

# Pure Android SDK build; no Gradle, Maven downloads or third-party runtime dependencies.
ROOT=$(cd "$(dirname "$0")/.." && pwd)
SDK=${ANDROID_SDK_ROOT:-${ANDROID_HOME:-"$HOME/Library/Android/sdk"}}
BUILD_TOOLS_VERSION=${ANDROID_BUILD_TOOLS_VERSION:-36.0.0}
ANDROID_PLATFORM=${ANDROID_PLATFORM:-android-35}
TOOLS="$SDK/build-tools/$BUILD_TOOLS_VERSION"
PLATFORM="$SDK/platforms/$ANDROID_PLATFORM/android.jar"
OUT="$ROOT/artifacts/android"
JAVA_BIN=${JAVA_HOME:+"$JAVA_HOME/bin/"}
for tool in aapt2 d8 zipalign apksigner; do
    if [ ! -x "$TOOLS/$tool" ]; then echo "Missing Android build tool: $tool ($BUILD_TOOLS_VERSION)" >&2; exit 1; fi
done
if [ ! -f "$PLATFORM" ]; then echo "Install SDK platform $ANDROID_PLATFORM first." >&2; exit 1; fi
rm -rf "$OUT/obj"
mkdir -p "$OUT/obj/classes" "$OUT/obj/generated" "$OUT/obj/dex"
mkdir -m 700 "$OUT/obj/private-assets"
if [ -n "${MINI_RADIO_SYNC_CONFIG:-}" ]; then
    # Only an explicitly supplied private file can provision a local installation.
    # Public builds have no credentials or personal library data.
    python3 - "$MINI_RADIO_SYNC_CONFIG" "$ROOT" "$OUT/obj/private-assets" <<'PY'
import json, os, sys
from pathlib import Path
from urllib.parse import urlsplit
import re
source, root, destination = map(Path, sys.argv[1:])
try:
    source.resolve().relative_to(root.resolve())
except ValueError:
    pass
else:
    raise SystemExit('Sync provisioning must be kept outside the repository.')
try:
    value = json.loads(source.read_text())
    url = urlsplit(value['server'])
    valid = (url.scheme == 'https' and url.hostname and not url.username and not url.password
             and not url.query and not url.fragment and re.fullmatch(r'MR1_[A-Za-z0-9_-]{43}', value['key']))
    if not valid: raise ValueError()
except Exception:
    raise SystemExit('Invalid private sync provisioning file.')
destination.mkdir(mode=0o700, exist_ok=True)
target = destination / 'sync-provisioning.json'
target.write_text(json.dumps({'server': value['server'], 'key': value['key']}))
os.chmod(target, 0o600)
PY
fi
"$TOOLS/aapt2" compile --dir "$ROOT/android/res" -o "$OUT/obj/resources.zip"
"$TOOLS/aapt2" link -o "$OUT/obj/unsigned.apk" -I "$PLATFORM" \
    --manifest "$ROOT/android/AndroidManifest.xml" --java "$OUT/obj/generated" -A "$OUT/obj/private-assets" "$OUT/obj/resources.zip"
find "$ROOT/android/src" "$OUT/obj/generated" -name '*.java' > "$OUT/obj/sources.txt"
"${JAVA_BIN}javac" --release 8 -encoding UTF-8 -classpath "$PLATFORM" -d "$OUT/obj/classes" @"$OUT/obj/sources.txt"
"${JAVA_BIN}jar" cf "$OUT/obj/classes.jar" -C "$OUT/obj/classes" .
"$TOOLS/d8" --lib "$PLATFORM" --min-api 26 --output "$OUT/obj/dex" "$OUT/obj/classes.jar"
(cd "$OUT/obj/dex" && zip -q "$OUT/obj/unsigned.apk" classes*.dex)
"$TOOLS/zipalign" -f -p 4 "$OUT/obj/unsigned.apk" "$OUT/obj/aligned.apk"

# A persistent local development identity permits updates without deleting user data.
# Production signing can provide an existing keystore via the environment.
KEYSTORE=${MINI_RADIO_KEYSTORE:-"$HOME/.android/mini-radio-development.keystore"}
KEY_ALIAS=${MINI_RADIO_KEY_ALIAS:-mini-radio}
export MINI_RADIO_STORE_PASSWORD=${MINI_RADIO_STORE_PASSWORD:-android}
export MINI_RADIO_KEY_PASSWORD=${MINI_RADIO_KEY_PASSWORD:-$MINI_RADIO_STORE_PASSWORD}
if [ ! -f "$KEYSTORE" ]; then
    if [ -n "${MINI_RADIO_KEYSTORE:-}" ]; then echo "Configured signing keystore does not exist." >&2; exit 1; fi
    mkdir -p "$(dirname "$KEYSTORE")"
    "${JAVA_BIN}keytool" -genkeypair -keystore "$KEYSTORE" -alias "$KEY_ALIAS" -keyalg RSA -keysize 2048 \
        -validity 10000 -storepass:env MINI_RADIO_STORE_PASSWORD -keypass:env MINI_RADIO_KEY_PASSWORD \
        -dname "CN=Mini Radio Development" >/dev/null 2>&1
    chmod 600 "$KEYSTORE"
fi
APK="$OUT/MiniRadio-Android-0.4.0.apk"
"$TOOLS/apksigner" sign --ks "$KEYSTORE" --ks-key-alias "$KEY_ALIAS" \
    --ks-pass env:MINI_RADIO_STORE_PASSWORD --key-pass env:MINI_RADIO_KEY_PASSWORD --out "$APK" "$OUT/obj/aligned.apk"
"$TOOLS/apksigner" verify "$APK"
echo "Built artifacts/android/MiniRadio-Android-0.4.0.apk"
if [ -n "${MINI_RADIO_SYNC_CONFIG:-}" ]; then
    chmod 600 "$APK"
    echo "Private sync provisioning included. Keep this installation APK private."
fi

if [ "${1:-}" = install ]; then
    ADB="$SDK/platform-tools/adb"
    if [ -n "${ANDROID_SERIAL:-}" ]; then
        "$ADB" -s "$ANDROID_SERIAL" install -r "$APK"
        "$ADB" -s "$ANDROID_SERIAL" shell am start -n com.miniradio.car/.MainActivity
    else
        "$ADB" -d install -r "$APK"
        "$ADB" -d shell am start -n com.miniradio.car/.MainActivity
    fi
fi
