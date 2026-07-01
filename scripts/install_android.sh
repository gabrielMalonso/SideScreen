#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
APK_PATH="$ROOT_DIR/AndroidClient/app/build/outputs/apk/debug/app-debug.apk"
PORT="${SIDESCREEN_PORT:-54321}"
if ! [[ "$PORT" =~ ^[0-9]+$ ]] || [ "$PORT" -lt 1 ] || [ "$PORT" -gt 65534 ]; then
    echo "SIDESCREEN_PORT must be 1..65534 because remote input uses port + 1." >&2
    exit 1
fi
INPUT_PORT=$((PORT + 1))

. "$SCRIPT_DIR/adb-env.sh"

echo "📱 Installing Android app..."

# Check if APK exists
if [ ! -f "$APK_PATH" ]; then
    echo "❌ APK not found. Building first..."
    "$SCRIPT_DIR/build_android.sh"
fi

# Check ADB connection
if ! sidescreen_select_adb_device; then
    echo "   Please connect one Android device by USB, enable USB debugging, and accept the prompt."
    exit 1
fi

# Install APK
adb install -r "$APK_PATH"

echo ""
echo "✅ App installed successfully!"
echo ""
echo "📲 Setting up USB port forwarding..."
adb reverse --remove "tcp:$PORT" 2>/dev/null || true
adb reverse --remove "tcp:$INPUT_PORT" 2>/dev/null || true
adb reverse "tcp:$PORT" "tcp:$PORT"
adb reverse "tcp:$INPUT_PORT" "tcp:$INPUT_PORT"

echo "✅ Ports $PORT and $INPUT_PORT forwarded"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Ready! Open 'Remote Mac' on your Android device"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
