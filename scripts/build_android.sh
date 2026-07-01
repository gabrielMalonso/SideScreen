#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "🔨 Building Android Client..."
cd "$ROOT_DIR/AndroidClient"

. "$SCRIPT_DIR/android-env.sh"

./gradlew testDebugUnitTest assembleDebug assembleRelease bundleRelease

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
