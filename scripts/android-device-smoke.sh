#!/bin/bash
set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
DEFAULT_APK_PATH="$ROOT_DIR/AndroidClient/app/build/outputs/apk/debug/app-debug.apk"
APK_PATH="${SIDESCREEN_APK:-$DEFAULT_APK_PATH}"
APK_SOURCE="default debug APK"
APK_SELECTED_EXPLICITLY=0
if [ -n "${SIDESCREEN_APK:-}" ]; then
    APK_SOURCE="SIDESCREEN_APK"
    APK_SELECTED_EXPLICITLY=1
fi
PORT="${SIDESCREEN_PORT:-54321}"
if ! [[ "$PORT" =~ ^[0-9]+$ ]] || [ "$PORT" -lt 1 ] || [ "$PORT" -gt 65534 ]; then
    echo "SIDESCREEN_PORT must be 1..65534 because remote input uses port + 1." >&2
    exit 1
fi
INPUT_PORT=$((PORT + 1))
DURATION=15
INSTALL=1
REVERSE=1
TAILNET_HOST=""
EXPECT_STREAM=0
TAP_CONNECT=0
FORCE_USB_MODE=0
FORCE_WIRELESS_MODE=0
STREAM_RECENT_WINDOW_MS="${SIDESCREEN_STREAM_RECENT_WINDOW_MS:-20000}"

usage() {
    echo "Usage: ./scripts/android-device-smoke.sh [--apk path] [--no-install] [--no-reverse] [--duration seconds] [--tailnet-host host] [--expect-stream] [--tap-connect] [--force-usb-mode] [--force-wireless-mode]"
    echo ""
    echo "Use --apk or SIDESCREEN_APK to install a specific APK, for example a signed release APK."
    echo "Use --expect-stream for manual long runs: start the Mac app, launch this script,"
    echo "tap Connect/Reconnect on Android, and the script fails if no stream connection is logged."
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --apk)
            if [ $# -lt 2 ] || [ -z "${2:-}" ]; then
                echo "--apk requires a path" >&2
                exit 1
            fi
            APK_PATH="$2"
            APK_SOURCE="--apk"
            APK_SELECTED_EXPLICITLY=1
            shift 2
            ;;
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
        --force-usb-mode)
            FORCE_USB_MODE=1
            shift
            ;;
        --force-wireless-mode)
            FORCE_WIRELESS_MODE=1
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

if [ "$APK_SELECTED_EXPLICITLY" -eq 1 ] && [ ! -f "$APK_PATH" ]; then
    echo "Selected APK does not exist: $APK_PATH" >&2
    exit 1
fi

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

device_now_ms() {
    local value
    value="$("${ADB[@]}" shell date +%s%3N 2>/dev/null | tr -d '\r' | head -1)"
    if [[ "$value" =~ ^[0-9]+$ ]]; then
        echo "$value"
        return
    fi
    value="$("${ADB[@]}" shell date +%s 2>/dev/null | tr -d '\r' | head -1)"
    if [[ "$value" =~ ^[0-9]+$ ]]; then
        echo $((value * 1000))
    fi
}

last_diag_timestamp() {
    local pattern="$1"
    local file="$2"
    grep -E "$pattern" "$file" 2>/dev/null |
        tail -1 |
        sed -n 's/^\[\([0-9][0-9]*\)\].*/\1/p'
}

local_port_listening() {
    local port="$1"
    if command -v lsof >/dev/null 2>&1; then
        lsof -nP -iTCP:"$port" -sTCP:LISTEN >/dev/null 2>&1
    elif command -v ss >/dev/null 2>&1; then
        ss -ltn | awk -v port=":$port" '$4 ~ port "$" { found=1 } END { exit !found }'
    elif command -v netstat >/dev/null 2>&1; then
        netstat -an -p tcp 2>/dev/null | awk -v port=".$port" '$4 ~ port "$" && $6 == "LISTEN" { found=1 } END { exit !found }'
    else
        return 1
    fi
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
echo "APK: $APK_PATH"
echo "APK source: $APK_SOURCE"
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
    if [ "$APK_SELECTED_EXPLICITLY" -eq 1 ]; then
        fail "Selected APK does not exist: $APK_PATH"
        exit 1
    fi

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
        pass "APK installed from $APK_PATH"
    else
        fail "APK install failed"
        sed 's/^/   /' /tmp/sidescreen-device-smoke.out | tail -80
        exit 1
    fi
else
    pass "APK install skipped by request; selected APK: $APK_PATH"
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

if [ "$EXPECT_STREAM" -eq 1 ] && [ "$REVERSE" -eq 1 ]; then
    if local_port_listening "$PORT"; then
        pass "Mac video server is listening on 127.0.0.1:$PORT"
    else
        warn "Mac video server is not listening on 127.0.0.1:$PORT yet; start the Mac app/server before expecting USB stream"
    fi
    if local_port_listening "$INPUT_PORT"; then
        pass "Mac input server is listening on 127.0.0.1:$INPUT_PORT"
    else
        warn "Mac input server is not listening on 127.0.0.1:$INPUT_PORT yet; click Start or run ./scripts/run.sh --start --usb"
    fi
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

dump_ui() {
    local dump_file="/tmp/sidescreen-ui-$DEVICE_SERIAL.xml"
    sleep 1
    if ! "${ADB[@]}" shell uiautomator dump /sdcard/sidescreen-ui.xml >/tmp/sidescreen-device-smoke.out 2>&1; then
        return 1
    fi
    if ! "${ADB[@]}" exec-out cat /sdcard/sidescreen-ui.xml > "$dump_file" 2>/tmp/sidescreen-device-smoke.out; then
        return 1
    fi
    echo "$dump_file"
}

tap_bounds_from_dump() {
    local dump_file="$1"
    local include_pattern="$2"
    local exclude_pattern="${3:-__SIDESCREEN_NO_EXCLUDE_MATCH__}"
    local bounds
    bounds="$(
        tr '><' '\n\n' < "$dump_file" |
            grep -Ei "$include_pattern" |
            grep -Eiv "$exclude_pattern" |
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

tap_usb_mode_button() {
    local dump_file
    dump_file="$(dump_ui)" || return 1
    tap_bounds_from_dump "$dump_file" 'resource-id="com\.sidescreen\.app:id/modeUSB"'
}

tap_wireless_mode_button() {
    local dump_file
    dump_file="$(dump_ui)" || return 1
    tap_bounds_from_dump "$dump_file" 'resource-id="com\.sidescreen\.app:id/modeWireless"'
}

tap_connect_button() {
    local dump_file
    dump_file="$(dump_ui)" || return 1
    tap_bounds_from_dump \
        "$dump_file" \
        'text="(connect|reconnect)"|content-desc="(connect|reconnect)"|resource-id="com\.sidescreen\.app:id/(connectButton|wirelessReconnectButton)"' \
        'text="disconnect"|content-desc="disconnect"|resource-id="com\.sidescreen\.app:id/(disconnectButton|wirelessDisconnectButton)"'
}

if [ "$FORCE_USB_MODE" -eq 1 ] || { [ "$EXPECT_STREAM" -eq 1 ] && [ "$REVERSE" -eq 1 ]; }; then
    if tap_usb_mode_button; then
        pass "USB mode selected"
    else
        fail "Could not find USB mode toggle to tap"
        sed 's/^/   /' /tmp/sidescreen-device-smoke.out | tail -40
    fi
fi

if [ "$FORCE_WIRELESS_MODE" -eq 1 ] || { [ "$EXPECT_STREAM" -eq 1 ] && [ "$REVERSE" -eq 0 ]; }; then
    if tap_wireless_mode_button; then
        pass "Wireless mode selected"
    else
        fail "Could not find Wireless mode toggle to tap"
        sed 's/^/   /' /tmp/sidescreen-device-smoke.out | tail -40
    fi
fi

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
    if [ "$REVERSE" -eq 1 ] && grep -E "Stream (connected|disconnected) - mode=WIRELESS|onConnectionStatus\\(false\\).*mode=WIRELESS|mode=TAILNET|mode=MANUAL|connectWireless|Wireless connected" "$STREAM_EVIDENCE_FILE" >/dev/null 2>&1; then
        fail "Android app is using wireless/Tailnet state during a USB smoke; switch to USB and rerun"
    fi
    if [ "$REVERSE" -eq 0 ] && grep -E "Stream connected - mode=USB|Connected to 127\\.0\\.0\\.1:$PORT|Input channel connected to 127\\.0\\.0\\.1:$INPUT_PORT" "$STREAM_EVIDENCE_FILE" >/dev/null 2>&1; then
        fail "Android app is using USB/loopback state during a network/Tailnet smoke; switch to Wireless and rerun"
    fi
    if grep -E "Stream connected|Connected to .*:$PORT|Wireless connected to .*:$PORT|First video frame|First output frame|Frames received: [1-9][0-9]*|Decode stats: input=[1-9][0-9]*" \
        "$STREAM_EVIDENCE_FILE" >/dev/null 2>&1; then
        pass "Stream connection and frame flow observed"
    else
        fail "No stream connection/frame flow observed; tap Connect/Reconnect during the run and keep the Mac app running"
    fi

    LAST_FRAME_TS="$(last_diag_timestamp "First video frame|First output frame|Frames received: [1-9][0-9]*|Decode stats: input=[1-9][0-9]*|Output #[1-9][0-9]*" /tmp/sidescreen-device-diag-full.out)"
    LAST_CONNECT_TS="$(last_diag_timestamp "Stream connected|Wireless connected|Connected to .*:$PORT" /tmp/sidescreen-device-diag-full.out)"
    LAST_DISCONNECT_TS="$(last_diag_timestamp "Stream disconnected|surfaceDestroyed|Session wake lock released" /tmp/sidescreen-device-diag-full.out)"
    NOW_MS="$(device_now_ms)"

    if [ -n "$LAST_DISCONNECT_TS" ] && [ -n "$LAST_CONNECT_TS" ] && [ "$LAST_DISCONNECT_TS" -gt "$LAST_CONNECT_TS" ]; then
        fail "Stream disconnected after the most recent connection during the run"
    fi
    if [ -n "$LAST_FRAME_TS" ] && [ -n "$NOW_MS" ]; then
        FRAME_AGE_MS=$((NOW_MS - LAST_FRAME_TS))
        if [ "$FRAME_AGE_MS" -le "$STREAM_RECENT_WINDOW_MS" ]; then
            pass "Recent frame flow observed near end of run (${FRAME_AGE_MS}ms old)"
        else
            fail "No recent frame flow near end of run; last frame was ${FRAME_AGE_MS}ms old"
        fi
    else
        fail "Could not verify recent frame flow near end of run"
    fi

    if grep -E "Input channel connected to .*:$INPUT_PORT" "$STREAM_EVIDENCE_FILE" >/dev/null 2>&1; then
        pass "Input channel observed on $INPUT_PORT"
    else
        fail "No input channel connection observed on $INPUT_PORT"
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
