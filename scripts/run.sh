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
APP_ARGS=()

usage() {
    echo "Usage: ./scripts/run.sh [--start] [--usb|--wireless|--lan|--tailnet|--manual-endpoint] [--tailnet-host host]"
}

require_value() {
    local option="$1"
    local value="${2:-}"
    if [ -z "$value" ]; then
        echo "$option requires a value" >&2
        usage >&2
        exit 1
    fi
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --start|--usb|--wireless|--lan|--tailnet|--manual-endpoint)
            APP_ARGS+=("$1")
            shift
            ;;
        --tailnet-host)
            require_value "$1" "${2:-}"
            APP_ARGS+=("$1" "${2:-}")
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown argument: $1" >&2
            usage >&2
            exit 1
            ;;
    esac
done

echo "🚀 Starting Side Screen..."

# Kill any existing instance
pkill -x SideScreen 2>/dev/null || true
sleep 0.3

# Check if app bundle exists
if [ -d "$ROOT_DIR/SideScreen.app" ]; then
    echo "  Opening SideScreen.app..."
    if [ "${#APP_ARGS[@]}" -gt 0 ]; then
        open "$ROOT_DIR/SideScreen.app" --args "${APP_ARGS[@]}"
    else
        open "$ROOT_DIR/SideScreen.app"
    fi
elif [ -f "$ROOT_DIR/MacHost/.build/out/Products/Release/SideScreen" ]; then
    echo "  Running release binary..."
    "$ROOT_DIR/MacHost/.build/out/Products/Release/SideScreen" "${APP_ARGS[@]}" &
elif [ -f "$ROOT_DIR/MacHost/.build/debug/SideScreen" ]; then
    echo "  Running debug binary..."
    "$ROOT_DIR/MacHost/.build/debug/SideScreen" "${APP_ARGS[@]}" &
else
    echo "❌ No build found. Building now..."
    "$SCRIPT_DIR/build_mac.sh"
    echo ""
    echo "  Opening SideScreen.app..."
    if [ "${#APP_ARGS[@]}" -gt 0 ]; then
        open "$ROOT_DIR/SideScreen.app" --args "${APP_ARGS[@]}"
    else
        open "$ROOT_DIR/SideScreen.app"
    fi
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
