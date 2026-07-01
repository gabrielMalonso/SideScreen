#!/bin/bash
set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
APK="$ROOT_DIR/AndroidClient/app/build/outputs/apk/release/app-release.apk"
AAB="$ROOT_DIR/AndroidClient/app/build/outputs/bundle/release/app-release.aab"

. "$SCRIPT_DIR/android-env.sh" >/tmp/sidescreen-android-signing-env.out 2>&1 || {
    cat /tmp/sidescreen-android-signing-env.out
    exit 1
}

APKSIGNER="$(find "$ANDROID_HOME/build-tools" -maxdepth 2 -type f -name apksigner 2>/dev/null | sort | tail -1)"

if [ -z "$APKSIGNER" ] || [ ! -x "$APKSIGNER" ]; then
    echo "ERROR: apksigner not found under ANDROID_HOME/build-tools"
    exit 1
fi

if [ ! -f "$APK" ]; then
    echo "ERROR: Release APK missing: $APK"
    exit 1
fi

if [ ! -f "$AAB" ]; then
    echo "ERROR: Release AAB missing: $AAB"
    exit 1
fi

DEBUG_SIGNED=0

echo "## APK signature"
if "$APKSIGNER" verify --verbose --print-certs "$APK" >/tmp/sidescreen-apk-signing.out 2>&1; then
    grep -E "Verifies|Number of signers|Signer #1 certificate DN|Signer #1 certificate SHA-256 digest" /tmp/sidescreen-apk-signing.out
else
    cat /tmp/sidescreen-apk-signing.out
    exit 1
fi

if grep -q "CN=Android Debug" /tmp/sidescreen-apk-signing.out; then
    DEBUG_SIGNED=1
fi

echo ""
echo "## AAB signature"
if jarsigner -verify -certs -verbose "$AAB" >/tmp/sidescreen-aab-signing.out 2>&1; then
    grep -E "jar verified|Signed by|CN=Android Debug" /tmp/sidescreen-aab-signing.out | awk '!seen[$0]++' | head -8
else
    cat /tmp/sidescreen-aab-signing.out
    exit 1
fi

if grep -q "CN=Android Debug" /tmp/sidescreen-aab-signing.out; then
    DEBUG_SIGNED=1
fi

if [ "$DEBUG_SIGNED" -eq 1 ]; then
    echo ""
    echo "WARNING: Android release artifacts are signed with the debug certificate."
    echo "   Set SIDESCREEN_RELEASE_* and rebuild before publication."
    exit 2
fi

echo ""
echo "OK: Android release artifacts are signed and do not use the debug certificate."
