#!/bin/bash
set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
APK="$ROOT_DIR/AndroidClient/app/build/outputs/apk/release/app-release.apk"
AAB="$ROOT_DIR/AndroidClient/app/build/outputs/bundle/release/app-release.aab"
DISTRIBUTION=0

usage() {
    cat <<EOF
Usage: ./scripts/verify-android-signing.sh [--dev|--release|--distribution]

Default dev mode exits 2 when release artifacts are debug-signed.
Release/distribution mode exits 1 for the same condition.
EOF
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --dev)
            DISTRIBUTION=0
            ;;
        --release|--distribution)
            DISTRIBUTION=1
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "ERROR: Unknown argument: $1" >&2
            usage >&2
            exit 64
            ;;
    esac
    shift
done

issue_debug_signed() {
    echo ""
    if [ "$DISTRIBUTION" -eq 1 ]; then
        echo "ERROR: Android release artifacts are signed with the debug certificate."
        echo "   Set SIDESCREEN_RELEASE_STORE_FILE, SIDESCREEN_RELEASE_STORE_PASSWORD,"
        echo "   SIDESCREEN_RELEASE_KEY_ALIAS, and SIDESCREEN_RELEASE_KEY_PASSWORD,"
        echo "   then rebuild with SIDESCREEN_REQUIRE_RELEASE_SIGNING=1."
        exit 1
    fi

    echo "WARNING: Android release artifacts are signed with the debug certificate."
    echo "   Fine for local dev. Not fine for publication."
    echo "   Set SIDESCREEN_RELEASE_* and rebuild before distribution."
    exit 2
}

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
    issue_debug_signed
fi

echo ""
echo "OK: Android release artifacts are signed and do not use the debug certificate."
