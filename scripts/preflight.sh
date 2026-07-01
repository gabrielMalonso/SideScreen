#!/bin/bash
set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
PORT="${SIDESCREEN_PORT:-54321}"
INPUT_PORT=$((PORT + 1))
if [ "$INPUT_PORT" -gt 65535 ]; then
    INPUT_PORT=65535
fi
FULL=0

if [ "${1:-}" = "--full" ]; then
    FULL=1
fi

PASS=0
WARN=0
FAIL=0

section() {
    echo ""
    echo "## $1"
}

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

run_check() {
    local label="$1"
    shift
    if "$@" >/tmp/sidescreen-preflight.out 2>&1; then
        pass "$label"
    else
        fail "$label"
        sed 's/^/   /' /tmp/sidescreen-preflight.out | tail -40
    fi
}

print_matching_output() {
    local pattern="$1"
    local fallback_lines="${2:-30}"

    if grep -E "$pattern" /tmp/sidescreen-preflight.out >/tmp/sidescreen-preflight-filtered.out; then
        tail -20 /tmp/sidescreen-preflight-filtered.out | awk '{print "   " $0}'
    else
        tail -"$fallback_lines" /tmp/sidescreen-preflight.out | awk '{print "   " $0}'
    fi
}

echo "# Side Screen Preflight"
echo ""
echo "Date: $(date '+%Y-%m-%d %H:%M:%S %Z')"
echo "Root: $ROOT_DIR"
echo "Port: $PORT"

section "Repository"
run_check "Shell scripts parse" bash -lc "cd '$ROOT_DIR' && for f in scripts/*.sh; do bash -n \"\$f\" || exit 1; done"
run_check "Diff has no whitespace errors" bash -lc "cd '$ROOT_DIR' && git diff --check"

if git -C "$ROOT_DIR" status --short | grep -q .; then
    warn "Worktree has uncommitted changes"
    git -C "$ROOT_DIR" status --short | sed 's/^/   /'
else
    pass "Worktree clean"
fi

section "Toolchain"
if . "$SCRIPT_DIR/android-env.sh" >/tmp/sidescreen-preflight.out 2>&1; then
    pass "Android toolchain env"
    echo "   JAVA_HOME=$JAVA_HOME"
    echo "   ANDROID_HOME=$ANDROID_HOME"
else
    fail "Android toolchain env"
    sed 's/^/   /' /tmp/sidescreen-preflight.out | tail -20
fi

if command -v swift >/dev/null 2>&1; then
    pass "Swift available ($(swift --version 2>&1 | head -1))"
else
    fail "Swift unavailable"
fi

section "Artifacts"
run_check "Input QA harness" "$SCRIPT_DIR/validate-input-qa.sh"

if [ -d "$ROOT_DIR/SideScreen.app" ]; then
    run_check "SideScreen.app code signature" codesign --verify --deep --strict --verbose=2 "$ROOT_DIR/SideScreen.app"
    run_check "SideScreen.app privacy plist keys" bash -lc "\
        /usr/libexec/PlistBuddy -c 'Print :NSScreenCaptureUsageDescription' '$ROOT_DIR/SideScreen.app/Contents/Info.plist' >/dev/null && \
        /usr/libexec/PlistBuddy -c 'Print :NSLocalNetworkUsageDescription' '$ROOT_DIR/SideScreen.app/Contents/Info.plist' >/dev/null && \
        /usr/libexec/PlistBuddy -c 'Print :NSBonjourServices:0' '$ROOT_DIR/SideScreen.app/Contents/Info.plist' >/dev/null"
    if [ -x "$ROOT_DIR/SideScreen.app/Contents/MacOS/SideScreenVirtualHIDHelper" ]; then
        pass "Virtual HID helper bundled"
    else
        warn "Virtual HID helper missing from app bundle; remote input will fall back to CGEvent"
    fi
else
    warn "SideScreen.app missing; run ./scripts/build_mac.sh"
fi

if [ -f "$ROOT_DIR/SideScreen-$(cat "$ROOT_DIR/VERSION" | tr -d '[:space:]')-mac-arm64.dmg" ]; then
    pass "Mac DMG exists"
else
    warn "Mac DMG missing; run ./scripts/build_mac.sh"
fi

if [ -f "$ROOT_DIR/AndroidClient/app/build/outputs/apk/debug/app-debug.apk" ]; then
    pass "Android debug APK exists"
else
    warn "Android debug APK missing; run ./scripts/build_android.sh"
fi

if [ -f "$ROOT_DIR/AndroidClient/app/build/outputs/apk/release/app-release.apk" ]; then
    pass "Android release APK exists"
else
    warn "Android release APK missing; run assembleRelease"
fi

if [ -f "$ROOT_DIR/AndroidClient/app/build/outputs/bundle/release/app-release.aab" ]; then
    pass "Android release AAB exists"
else
    warn "Android release AAB missing; run bundleRelease"
fi

run_check "Release checksums generated" "$SCRIPT_DIR/generate-checksums.sh" --stdout

if "$SCRIPT_DIR/verify-android-signing.sh" >/tmp/sidescreen-preflight.out 2>&1; then
    pass "Android release artifact signatures"
else
    STATUS=$?
    if [ "$STATUS" -eq 2 ]; then
        warn "Android release artifacts are debug-signed"
        print_matching_output "Signer #1 certificate DN|Signed by|CN=Android Debug|WARNING|OK:"
    else
        fail "Android release artifact signatures"
        print_matching_output "ERROR|WARNING|Signer #1 certificate DN|Signed by" 40
    fi
fi

if "$SCRIPT_DIR/verify-mac-distribution.sh" >/tmp/sidescreen-preflight.out 2>&1; then
    pass "Mac Gatekeeper distribution readiness"
else
    STATUS=$?
    if [ "$STATUS" -eq 2 ]; then
        warn "Mac app/DMG rejected by Gatekeeper"
        print_matching_output "rejected|source=|WARNING|OK:"
    else
        fail "Mac Gatekeeper distribution readiness"
        print_matching_output "ERROR|WARNING|rejected|source=" 50
    fi
fi

if [ -n "${SIDESCREEN_RELEASE_STORE_FILE:-}" ] &&
   [ -n "${SIDESCREEN_RELEASE_STORE_PASSWORD:-}" ] &&
   [ -n "${SIDESCREEN_RELEASE_KEY_ALIAS:-}" ] &&
   [ -n "${SIDESCREEN_RELEASE_KEY_PASSWORD:-}" ]; then
    pass "Android release signing env configured"
else
    warn "Android release signing env missing; release APK/AAB will be debug-signed unless SIDESCREEN_REQUIRE_RELEASE_SIGNING=1"
fi

if [ -n "${SIDESCREEN_CODESIGN_IDENTITY:-}" ] && [ "${SIDESCREEN_CODESIGN_IDENTITY:-}" != "-" ]; then
    pass "Mac Developer ID signing identity configured"
elif security find-identity -v -p codesigning 2>/dev/null | grep -q '"Developer ID Application:'; then
    pass "Mac Developer ID signing identity available for auto-signing"
else
    warn "Mac Developer ID signing identity missing; Mac app/DMG will be ad-hoc signed and not notarized"
fi

section "Devices"
if command -v adb >/dev/null 2>&1; then
    adb devices -l > /tmp/sidescreen-preflight-adb.out 2>&1 || true
    if grep -q " device " /tmp/sidescreen-preflight-adb.out || grep -q $'\tdevice' /tmp/sidescreen-preflight-adb.out; then
        pass "ADB Android device connected"
        sed 's/^/   /' /tmp/sidescreen-preflight-adb.out
        if adb reverse --list 2>/dev/null | grep -q "tcp:$PORT tcp:$PORT" &&
           adb reverse --list 2>/dev/null | grep -q "tcp:$INPUT_PORT tcp:$INPUT_PORT"; then
            pass "ADB reverse active on $PORT and $INPUT_PORT"
        else
            warn "ADB reverse not active on $PORT and $INPUT_PORT; run ./scripts/setup-usb.sh"
        fi
    else
        warn "No ADB Android device connected"
        sed 's/^/   /' /tmp/sidescreen-preflight-adb.out
    fi
else
    warn "adb unavailable"
fi

if command -v tailscale >/dev/null 2>&1; then
    tailscale status > /tmp/sidescreen-preflight-tailscale.out 2>&1 || true
    if grep -i "android" /tmp/sidescreen-preflight-tailscale.out | grep -vi "offline" >/dev/null; then
        pass "Tailnet Android online"
        grep -i "android" /tmp/sidescreen-preflight-tailscale.out | sed 's/^/   /'
    else
        warn "No Tailnet Android online"
        grep -i "android" /tmp/sidescreen-preflight-tailscale.out | sed 's/^/   /' || true
    fi
else
    warn "tailscale unavailable"
fi

if [ "$FULL" -eq 1 ]; then
    section "Full Automated Tests"
    run_check "Mac swift test" bash -lc "cd '$ROOT_DIR/MacHost' && swift test"
    run_check "Android unit tests and release build" bash -lc "cd '$ROOT_DIR/AndroidClient' && JAVA_HOME='$JAVA_HOME' ANDROID_HOME='$ANDROID_HOME' ./gradlew testDebugUnitTest assembleRelease bundleRelease"
fi

section "Summary"
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
