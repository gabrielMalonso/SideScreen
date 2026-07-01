#!/bin/bash
set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
APK_PATH="$ROOT_DIR/AndroidClient/app/build/outputs/apk/debug/app-debug.apk"
PORT="${SIDESCREEN_PORT:-54321}"
INPUT_PORT=$((PORT + 1))
if [ "$INPUT_PORT" -gt 65535 ]; then
    INPUT_PORT=65535
fi
DURATION=15
INSTALL=1
REVERSE=1
TAILNET_HOST=""
EXPECT_STREAM=0
TAP_CONNECT=0

usage() {
    echo "Usage: ./scripts/android-device-smoke.sh [--no-install] [--no-reverse] [--duration seconds] [--tailnet-host host] [--expect-stream] [--tap-connect]"
    echo ""
    echo "Use --expect-stream for manual long runs: start the Mac app, launch this script,"
    echo "tap Connect/Reconnect on Android, and the script fails if no stream connection is logged."
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --no-install)
            INSTALL=0
            shift
            ;;
        --no-reverse)
            REVERSE=0
            shift
            ;;
        --duration)
            DURATION="${2:-}"
            shift 2
            ;;
        --tailnet-host)
            TAILNET_HOST="${2:-}"
            shift 2
            ;;
        --expect-stream)
            EXPECT_STREAM=1
            shift
            ;;
        --tap-connect)
            TAP_CONNECT=1
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown argument: $1"
            usage
            exit 1
            ;;
    esac
done

. "$SCRIPT_DIR/adb-env.sh"

PASS=0
WARN=0
FAIL=0

pass() {
    PASS=$((PASS + 1))
    echo "✅ $1"
}

warn() {
    WARN=$((WARN + 1))
    echo "⚠️  $1"
}

fail() {
    FAIL=$((FAIL + 1))
    echo "❌ $1"
}

if ! sidescreen_select_adb_device >/tmp/sidescreen-device-select.out 2>&1; then
    if grep -q "Multiple Android devices" /tmp/sidescreen-device-select.out; then
        fail "Multiple Android devices connected; set ANDROID_SERIAL"
        sed 's/^/   /' /tmp/sidescreen-device-select.out
        exit 1
    fi

    warn "No authorized Android device connected via ADB"
    sed 's/^/   /' /tmp/sidescreen-device-select.out
    echo ""
    echo "Connect the tablet by USB, enable USB debugging, accept the prompt, then rerun this script."
    exit 2
fi

DEVICE_SERIAL="$ANDROID_SERIAL"
ADB=(adb -s "$DEVICE_SERIAL")

echo "# Side Screen Android Device Smoke"
echo "Device: $DEVICE_SERIAL"
echo "Port: $PORT"
echo "Input port: $INPUT_PORT"
echo "Duration: ${DURATION}s"
echo "Expect stream: $EXPECT_STREAM"
echo "Tap connect: $TAP_CONNECT"
echo ""

if "${ADB[@]}" get-state >/tmp/sidescreen-device-smoke.out 2>&1; then
    pass "ADB device authorized"
else
    fail "ADB device unavailable"
    sed 's/^/   /' /tmp/sidescreen-device-smoke.out
    exit 1
fi

if [ ! -f "$APK_PATH" ]; then
    echo "APK missing; building debug APK first..."
    if "$SCRIPT_DIR/build_android.sh" >/tmp/sidescreen-device-smoke.out 2>&1; then
        pass "Android debug APK built"
    else
        fail "Android debug APK build failed"
        sed 's/^/   /' /tmp/sidescreen-device-smoke.out | tail -80
        exit 1
    fi
fi

if [ "$INSTALL" -eq 1 ]; then
    if "${ADB[@]}" install -r "$APK_PATH" >/tmp/sidescreen-device-smoke.out 2>&1; then
        pass "APK installed"
    else
        fail "APK install failed"
        sed 's/^/   /' /tmp/sidescreen-device-smoke.out | tail -80
        exit 1
    fi
else
    pass "APK install skipped by request"
fi

if [ "$REVERSE" -eq 1 ]; then
    "${ADB[@]}" reverse --remove "tcp:$PORT" >/dev/null 2>&1 || true
    "${ADB[@]}" reverse --remove "tcp:$INPUT_PORT" >/dev/null 2>&1 || true
    if "${ADB[@]}" reverse "tcp:$PORT" "tcp:$PORT" >/tmp/sidescreen-device-smoke.out 2>&1 &&
       "${ADB[@]}" reverse "tcp:$INPUT_PORT" "tcp:$INPUT_PORT" >>/tmp/sidescreen-device-smoke.out 2>&1 &&
       "${ADB[@]}" reverse --list | grep -q "tcp:$PORT tcp:$PORT" &&
       "${ADB[@]}" reverse --list | grep -q "tcp:$INPUT_PORT tcp:$INPUT_PORT"; then
        pass "ADB reverse active on $PORT and $INPUT_PORT"
    else
        fail "ADB reverse setup failed"
        sed 's/^/   /' /tmp/sidescreen-device-smoke.out | tail -40
    fi
else
    "${ADB[@]}" reverse --remove "tcp:$PORT" >/dev/null 2>&1 || true
    "${ADB[@]}" reverse --remove "tcp:$INPUT_PORT" >/dev/null 2>&1 || true
    pass "ADB reverse disabled for network/Tailnet test"
fi

if [ -n "$TAILNET_HOST" ]; then
    if "${ADB[@]}" shell ping -c 1 -W 3 "$TAILNET_HOST" >/tmp/sidescreen-device-smoke.out 2>&1; then
        pass "Device can ping Tailnet host $TAILNET_HOST"
    else
        warn "Device could not ping Tailnet host $TAILNET_HOST"
        sed 's/^/   /' /tmp/sidescreen-device-smoke.out | tail -20
    fi
fi

"${ADB[@]}" logcat -c >/dev/null 2>&1 || true
"${ADB[@]}" shell run-as com.sidescreen.app rm -f files/diag.log >/dev/null 2>&1 || true
if "${ADB[@]}" shell am start -n com.sidescreen.app/.MainActivity >/tmp/sidescreen-device-smoke.out 2>&1; then
    pass "MainActivity launched"
else
    fail "MainActivity launch failed"
    sed 's/^/   /' /tmp/sidescreen-device-smoke.out | tail -40
fi

tap_connect_button() {
    local dump_file="/tmp/sidescreen-ui-$DEVICE_SERIAL.xml"
    sleep 1
    if ! "${ADB[@]}" shell uiautomator dump /sdcard/sidescreen-ui.xml >/tmp/sidescreen-device-smoke.out 2>&1; then
        return 1
    fi
    if ! "${ADB[@]}" exec-out cat /sdcard/sidescreen-ui.xml > "$dump_file" 2>/tmp/sidescreen-device-smoke.out; then
        return 1
    fi

    local bounds
    bounds="$(
        tr '><' '\n\n' < "$dump_file" |
            grep -Ei 'text="(connect|reconnect)"|content-desc="(connect|reconnect)"|resource-id="com\.sidescreen\.app:id/(connectButton|wirelessReconnectButton)"' |
            grep -Eiv 'text="disconnect"|content-desc="disconnect"|resource-id="com\.sidescreen\.app:id/(disconnectButton|wirelessDisconnectButton)"' |
            sed -n 's/.*bounds="\[\([0-9][0-9]*\),\([0-9][0-9]*\)\]\[\([0-9][0-9]*\),\([0-9][0-9]*\)\]".*/\1 \2 \3 \4/p' |
            head -1
    )"
    if [ -z "$bounds" ]; then
        return 1
    fi

    set -- $bounds
    local x=$(((($1 + $3)) / 2))
    local y=$(((($2 + $4)) / 2))
    "${ADB[@]}" shell input tap "$x" "$y" >/tmp/sidescreen-device-smoke.out 2>&1
}

if [ "$TAP_CONNECT" -eq 1 ]; then
    if tap_connect_button; then
        pass "Connect/Reconnect tapped"
    else
        fail "Could not find Connect/Reconnect button to tap"
        sed 's/^/   /' /tmp/sidescreen-device-smoke.out | tail -40
    fi
fi

sleep "$DURATION"

PID="$("${ADB[@]}" shell pidof com.sidescreen.app 2>/dev/null | tr -d '\r' || true)"
if [ -n "$PID" ]; then
    pass "App process alive (pid $PID)"
else
    fail "App process not running after launch"
fi

echo ""
echo "## Recent Side Screen logcat"
"${ADB[@]}" logcat -d -t 200 -s MA SC IC QR WT VD DiagLog VideoDecoder InputClient StreamClient QRScanner 2>/dev/null > /tmp/sidescreen-device-logcat.out
cat /tmp/sidescreen-device-logcat.out |
    sed 's/^/   /' |
    tail -80

echo ""
echo "## App diagnostic log"
if "${ADB[@]}" shell run-as com.sidescreen.app cat files/diag.log >/tmp/sidescreen-device-diag-full.out 2>&1; then
    tail -80 /tmp/sidescreen-device-diag-full.out | sed 's/^/   /'
    pass "App diagnostic log readable"
else
    warn "App diagnostic log unavailable yet"
    sed 's/^/   /' /tmp/sidescreen-device-diag-full.out | tail -20
fi

if [ "$EXPECT_STREAM" -eq 1 ]; then
    STREAM_EVIDENCE_FILE="/tmp/sidescreen-device-stream-evidence.out"
    cat /tmp/sidescreen-device-diag-full.out /tmp/sidescreen-device-logcat.out > "$STREAM_EVIDENCE_FILE" 2>/dev/null || true
    if grep -E "Stream connected|Connected to .*:$PORT|Wireless connected to .*:$PORT|First video frame|First output frame|Frames received: [1-9][0-9]*|Decode stats: input=[1-9][0-9]*" \
        "$STREAM_EVIDENCE_FILE" >/dev/null 2>&1; then
        pass "Stream connection and frame flow observed"
    else
        fail "No stream connection/frame flow observed; tap Connect/Reconnect during the run and keep the Mac app running"
    fi
fi

echo ""
echo "## Device battery and thermal snapshot"
"${ADB[@]}" shell dumpsys battery 2>/dev/null | sed 's/^/   /' | sed -n '1,24p'
"${ADB[@]}" shell dumpsys thermalservice 2>/dev/null | sed 's/^/   /' | sed -n '1,30p'

echo ""
echo "## Summary"
echo "Passed: $PASS"
echo "Warnings: $WARN"
echo "Failed: $FAIL"

if [ "$FAIL" -gt 0 ]; then
    exit 1
fi

if [ "$WARN" -gt 0 ]; then
    exit 2
fi

exit 0
