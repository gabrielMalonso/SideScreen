#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PORT="${SIDESCREEN_PORT:-54321}"
INPUT_PORT=$((PORT + 1))
if [ "$INPUT_PORT" -gt 65535 ]; then
    INPUT_PORT=65535
fi

. "$SCRIPT_DIR/adb-env.sh"

echo "🔧 Setting up USB port forwarding..."

# Check ADB connection
if ! sidescreen_select_adb_device; then
    echo ""
    echo "Troubleshooting:"
    echo "  1. Connect device via USB cable"
    echo "  2. Enable Developer Options on device"
    echo "  3. Enable USB Debugging in Developer Options"
    echo "  4. Accept the USB debugging prompt on device"
    echo "  5. Run this script again"
    exit 1
fi

echo "  ✓ Device connected ($ANDROID_SERIAL)"

# Remove existing reverse for Side Screen only. Other adb forwards may belong to debuggers.
echo "  Clearing existing Side Screen port forward..."
adb reverse --remove "tcp:$PORT" 2>/dev/null || true
adb reverse --remove "tcp:$INPUT_PORT" 2>/dev/null || true
sleep 0.5

# Setup new reverse
echo "  Setting up port $PORT..."
adb reverse "tcp:$PORT" "tcp:$PORT"
echo "  Setting up input port $INPUT_PORT..."
adb reverse "tcp:$INPUT_PORT" "tcp:$INPUT_PORT"

# Verify
if adb reverse --list | grep -q "tcp:$PORT tcp:$PORT" &&
   adb reverse --list | grep -q "tcp:$INPUT_PORT tcp:$INPUT_PORT"; then
    echo ""
    echo "✅ USB port forwarding active!"
    echo ""
    adb reverse --list
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "Ready to connect. Make sure Mac app is running."
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
else
    echo "❌ Port forwarding failed"
    exit 1
fi
