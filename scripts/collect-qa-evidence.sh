#!/bin/bash
set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
VERSION="$(tr -d '[:space:]' < "$ROOT_DIR/VERSION")"
STAMP="$(date '+%Y%m%d-%H%M%S')-$$"
OUT_DIR="$ROOT_DIR/qa-evidence/$STAMP"
PORT="${SIDESCREEN_PORT:-54321}"
DURATION=15
RUN_SMOKE=0
EXPECT_STREAM=0
TAILNET_HOST=""
NO_REVERSE=0
SMOKE_STATUS=0

usage() {
    echo "Usage: ./scripts/collect-qa-evidence.sh [--smoke] [--expect-stream] [--no-reverse] [--duration seconds] [--tailnet-host host]"
    echo ""
    echo "Examples:"
    echo "  ./scripts/collect-qa-evidence.sh"
    echo "  ./scripts/collect-qa-evidence.sh --smoke --duration 1800 --expect-stream"
    echo "  ./scripts/collect-qa-evidence.sh --smoke --duration 1800 --expect-stream --tailnet-host mac.example.ts.net"
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --smoke)
            RUN_SMOKE=1
            shift
            ;;
        --expect-stream)
            RUN_SMOKE=1
            EXPECT_STREAM=1
            shift
            ;;
        --duration)
            DURATION="${2:-}"
            shift 2
            ;;
        --tailnet-host)
            RUN_SMOKE=1
            TAILNET_HOST="${2:-}"
            shift 2
            ;;
        --no-reverse)
            RUN_SMOKE=1
            NO_REVERSE=1
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

mkdir -p "$OUT_DIR"

capture() {
    local label="$1"
    local file="$2"
    shift 2

    {
        echo "# $label"
        echo "Command: $*"
        echo "Started: $(date '+%Y-%m-%d %H:%M:%S %Z')"
        echo ""
    } > "$OUT_DIR/$file"

    "$@" >> "$OUT_DIR/$file" 2>&1
    local status=$?

    {
        echo ""
        echo "Exit status: $status"
        echo "Finished: $(date '+%Y-%m-%d %H:%M:%S %Z')"
    } >> "$OUT_DIR/$file"

    return "$status"
}

capture_shell() {
    local label="$1"
    local file="$2"
    local command="$3"
    capture "$label" "$file" bash -lc "$command"
}

{
    echo "Side Screen QA Evidence"
    echo "Version: $VERSION"
    echo "Date: $(date '+%Y-%m-%d %H:%M:%S %Z')"
    echo "Root: $ROOT_DIR"
    echo "Port: $PORT"
    echo "Smoke: $RUN_SMOKE"
    echo "Expect stream: $EXPECT_STREAM"
    echo "Duration: $DURATION"
    echo "Tailnet host: ${TAILNET_HOST:-none}"
    echo "No reverse: $NO_REVERSE"
} > "$OUT_DIR/manifest.txt"

capture "Git status" "git-status.txt" git -C "$ROOT_DIR" status --short
capture "Git diff stat" "git-diff-stat.txt" git -C "$ROOT_DIR" diff --stat
capture "Preflight full" "preflight.txt" "$SCRIPT_DIR/preflight.sh" --full

if command -v adb >/dev/null 2>&1; then
    capture "ADB devices" "adb-devices.txt" adb devices -l
else
    echo "adb unavailable" > "$OUT_DIR/adb-devices.txt"
fi

if command -v tailscale >/dev/null 2>&1; then
    capture "Tailscale status" "tailscale-status.txt" tailscale status
    capture "Side Screen Tailnet diagnostics" "tailnet-diagnostics.txt" "$SCRIPT_DIR/tailnet-diagnostics.sh"
else
    echo "tailscale unavailable" > "$OUT_DIR/tailscale-status.txt"
fi

capture_shell "Artifacts" "artifacts.txt" "cd '$ROOT_DIR' && ls -lh SideScreen.app SideScreen-'$VERSION'-mac-arm64.dmg AndroidClient/app/build/outputs/apk/debug/app-debug.apk AndroidClient/app/build/outputs/apk/release/app-release.apk AndroidClient/app/build/outputs/bundle/release/app-release.aab 2>&1"
capture "Release checksums" "checksums.txt" "$SCRIPT_DIR/generate-checksums.sh" --stdout
capture "Android release signing" "android-release-signing.txt" "$SCRIPT_DIR/verify-android-signing.sh"
capture_shell "Input QA harness" "input-qa-harness.txt" "cd '$ROOT_DIR' && ls -lh qa/input-text-harness.html scripts/open-input-qa.sh && shasum -a 256 qa/input-text-harness.html scripts/open-input-qa.sh"
capture "Input QA validation" "input-qa-validation.txt" "$SCRIPT_DIR/validate-input-qa.sh"

if [ -d "$ROOT_DIR/SideScreen.app" ]; then
    capture "Mac app codesign" "mac-codesign.txt" codesign --verify --deep --strict --verbose=2 "$ROOT_DIR/SideScreen.app"
    capture "Mac app Gatekeeper assessment" "mac-spctl-app.txt" spctl -a -vv "$ROOT_DIR/SideScreen.app"
    capture "Mac distribution readiness" "mac-distribution.txt" "$SCRIPT_DIR/verify-mac-distribution.sh"
fi

DMG="$ROOT_DIR/SideScreen-$VERSION-mac-arm64.dmg"
if [ -f "$DMG" ]; then
    capture "Mac DMG Gatekeeper assessment" "mac-spctl-dmg.txt" spctl -a -vv -t open "$DMG"
fi

if [ "$RUN_SMOKE" -eq 1 ]; then
    smoke_args=(--duration "$DURATION")
    if [ "$EXPECT_STREAM" -eq 1 ]; then
        smoke_args+=(--expect-stream)
    fi
    if [ -n "$TAILNET_HOST" ]; then
        smoke_args+=(--tailnet-host "$TAILNET_HOST")
    fi
    if [ "$NO_REVERSE" -eq 1 ]; then
        smoke_args+=(--no-reverse)
    fi
    capture "Android device smoke" "android-device-smoke.txt" "$SCRIPT_DIR/android-device-smoke.sh" "${smoke_args[@]}"
    SMOKE_STATUS=$?
fi

{
    echo ""
    echo "Android smoke exit status: $SMOKE_STATUS"
    echo "Evidence folder: $OUT_DIR"
} >> "$OUT_DIR/manifest.txt"

echo "Evidence written to: $OUT_DIR"
echo "Start with: $OUT_DIR/manifest.txt"

if [ "$RUN_SMOKE" -eq 1 ] && [ "$SMOKE_STATUS" -ne 0 ]; then
    exit "$SMOKE_STATUS"
fi

exit 0
