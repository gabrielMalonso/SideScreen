#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
DISTRIBUTION=0

usage() {
    cat <<EOF
Usage: ./scripts/build_android.sh [--dev|--release|--distribution]

Default dev mode builds debug plus local release artifacts. Without
SIDESCREEN_RELEASE_* env vars, those release artifacts use the debug key.

Release/distribution mode requires:
  SIDESCREEN_RELEASE_STORE_FILE
  SIDESCREEN_RELEASE_STORE_PASSWORD
  SIDESCREEN_RELEASE_KEY_ALIAS
  SIDESCREEN_RELEASE_KEY_PASSWORD
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

missing_release_env() {
    local missing=0

    for name in \
        SIDESCREEN_RELEASE_STORE_FILE \
        SIDESCREEN_RELEASE_STORE_PASSWORD \
        SIDESCREEN_RELEASE_KEY_ALIAS \
        SIDESCREEN_RELEASE_KEY_PASSWORD
    do
        if [ -z "${!name:-}" ]; then
            echo "  missing $name"
            missing=1
        fi
    done

    if [ -n "${SIDESCREEN_RELEASE_STORE_FILE:-}" ] && [ ! -f "$SIDESCREEN_RELEASE_STORE_FILE" ]; then
        echo "  missing keystore file at SIDESCREEN_RELEASE_STORE_FILE"
        missing=1
    fi

    return "$missing"
}

echo "🔨 Building Android Client..."
cd "$ROOT_DIR/AndroidClient"

. "$SCRIPT_DIR/android-env.sh"

if [ "$DISTRIBUTION" -eq 1 ]; then
    echo "Release signing: required"
    if ! missing_release_env; then
        echo "❌ Android distribution build needs release signing env vars."
        echo "   Keep the keystore outside the repo. Do not commit it."
        exit 1
    fi

    export SIDESCREEN_REQUIRE_RELEASE_SIGNING=1
    ./gradlew testDebugUnitTest assembleRelease bundleRelease
    "$SCRIPT_DIR/verify-android-signing.sh" --release
else
    if missing_release_env >/tmp/sidescreen-android-signing-missing.out; then
        echo "Release signing: configured"
    else
        echo "Release signing: not configured; release APK/AAB will be debug-signed for local dev only."
        sed 's/^/   /' /tmp/sidescreen-android-signing-missing.out
    fi

    ./gradlew testDebugUnitTest assembleDebug assembleRelease bundleRelease
    set +e
    "$SCRIPT_DIR/verify-android-signing.sh"
    VERIFY_STATUS=$?
    set -e
    if [ "$VERIFY_STATUS" -ne 0 ] && [ "$VERIFY_STATUS" -ne 2 ]; then
        exit "$VERIFY_STATUS"
    fi
fi

echo ""
echo "✅ Build successful!"
echo ""
echo "📦 Debug APK:   $ROOT_DIR/AndroidClient/app/build/outputs/apk/debug/app-debug.apk"
echo "📦 Release APK: $ROOT_DIR/AndroidClient/app/build/outputs/apk/release/app-release.apk"
echo "📦 Release AAB: $ROOT_DIR/AndroidClient/app/build/outputs/bundle/release/app-release.aab"
echo ""
echo "To install on device:"
echo "  adb install -r $ROOT_DIR/AndroidClient/app/build/outputs/apk/debug/app-debug.apk"
echo ""
echo "Or run: ./scripts/install_android.sh"
