#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
PORT="${SIDESCREEN_PORT:-54321}"
if ! [[ "$PORT" =~ ^[0-9]+$ ]] || [ "$PORT" -lt 1 ] || [ "$PORT" -gt 65534 ]; then
    echo "SIDESCREEN_PORT must be 1..65534 because remote input uses port + 1." >&2
    exit 1
fi
INPUT_PORT=$((PORT + 1))

echo "🚀 Starting Side Screen..."

# Kill any existing instance
pkill -x SideScreen 2>/dev/null || true
sleep 0.3

# Check if app bundle exists
if [ -d "$ROOT_DIR/SideScreen.app" ]; then
    echo "  Opening SideScreen.app..."
    open "$ROOT_DIR/SideScreen.app"
elif [ -f "$ROOT_DIR/MacHost/.build/out/Products/Release/SideScreen" ]; then
    echo "  Running release binary..."
    "$ROOT_DIR/MacHost/.build/out/Products/Release/SideScreen" &
elif [ -f "$ROOT_DIR/MacHost/.build/debug/SideScreen" ]; then
    echo "  Running debug binary..."
    "$ROOT_DIR/MacHost/.build/debug/SideScreen" &
else
    echo "❌ No build found. Building now..."
    "$SCRIPT_DIR/build_mac.sh"
    echo ""
    echo "  Opening SideScreen.app..."
    open "$ROOT_DIR/SideScreen.app"
fi

echo ""
echo "✅ Mac app started!"
echo ""

# Setup USB if device connected
if . "$SCRIPT_DIR/adb-env.sh" >/tmp/sidescreen-run-adb.out 2>&1 && sidescreen_select_adb_device >/tmp/sidescreen-run-device.out 2>&1; then
    echo "📱 Android device detected, setting up USB..."
    adb reverse --remove "tcp:$PORT" 2>/dev/null || true
    adb reverse --remove "tcp:$INPUT_PORT" 2>/dev/null || true
    adb reverse "tcp:$PORT" "tcp:$PORT"
    adb reverse "tcp:$INPUT_PORT" "tcp:$INPUT_PORT"
    echo "  ✓ Port forwarding ready"
else
    echo "📱 No single authorized Android device detected; USB forwarding skipped"
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Open 'Side Screen' on Android and tap Connect"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
