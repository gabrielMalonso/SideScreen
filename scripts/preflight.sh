#!/bin/bash
set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
PORT="${SIDESCREEN_PORT:-54321}"
if ! [[ "$PORT" =~ ^[0-9]+$ ]] || [ "$PORT" -lt 1 ] || [ "$PORT" -gt 65534 ]; then
    echo "SIDESCREEN_PORT must be 1..65534 because remote input uses port + 1." >&2
    exit 1
fi
INPUT_PORT=$((PORT + 1))
FULL=0
DISTRIBUTION=0

usage() {
    cat <<EOF
Usage: ./scripts/preflight.sh [--full] [--dev|--release|--distribution]

Default dev mode allows local-only release warnings.
Release/distribution mode turns signing, notarization, and Gatekeeper
problems into blockers.
EOF
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --full)
            FULL=1
            ;;
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
            echo "Unknown argument: $1" >&2
            usage >&2
            exit 64
            ;;
    esac
    shift
done

VERIFY_MODE_ARG="--dev"
if [ "$DISTRIBUTION" -eq 1 ]; then
    VERIFY_MODE_ARG="--release"
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

distribution_issue() {
    if [ "$DISTRIBUTION" -eq 1 ]; then
        fail "Distribution blocker: $1"
    else
        warn "$1"
    fi
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
if [ "$DISTRIBUTION" -eq 1 ]; then
    echo "Profile: distribution"
else
    echo "Profile: dev"
fi

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

if [ "$FULL" -eq 1 ]; then
    section "Full Automated Tests"
    run_check "Mac swift test" bash -lc "cd '$ROOT_DIR/MacHost' && swift test"
    if [ "$DISTRIBUTION" -eq 1 ]; then
        run_check "Android unit tests and signed release build" bash -lc "cd '$ROOT_DIR/AndroidClient' && JAVA_HOME='${JAVA_HOME:-}' ANDROID_HOME='${ANDROID_HOME:-}' SIDESCREEN_REQUIRE_RELEASE_SIGNING=1 ./gradlew testDebugUnitTest assembleRelease bundleRelease"
    else
        run_check "Android unit tests and local release build" bash -lc "cd '$ROOT_DIR/AndroidClient' && JAVA_HOME='${JAVA_HOME:-}' ANDROID_HOME='${ANDROID_HOME:-}' ./gradlew testDebugUnitTest assembleRelease bundleRelease"
    fi
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
    distribution_issue "SideScreen.app missing; run ./scripts/build_mac.sh --release for distribution"
fi

if [ -f "$ROOT_DIR/SideScreen-$(cat "$ROOT_DIR/VERSION" | tr -d '[:space:]')-mac-arm64.dmg" ]; then
    pass "Mac DMG exists"
else
    distribution_issue "Mac DMG missing; run ./scripts/build_mac.sh --release for distribution"
fi

if [ -f "$ROOT_DIR/AndroidClient/app/build/outputs/apk/debug/app-debug.apk" ]; then
    pass "Android debug APK exists"
else
    warn "Android debug APK missing; run ./scripts/build_android.sh"
fi

if [ -f "$ROOT_DIR/AndroidClient/app/build/outputs/apk/release/app-release.apk" ]; then
    pass "Android release APK exists"
else
    distribution_issue "Android release APK missing; run ./scripts/build_android.sh --release for distribution"
fi

if [ -f "$ROOT_DIR/AndroidClient/app/build/outputs/bundle/release/app-release.aab" ]; then
    pass "Android release AAB exists"
else
    distribution_issue "Android release AAB missing; run ./scripts/build_android.sh --release for distribution"
fi

if "$SCRIPT_DIR/generate-checksums.sh" --stdout >/tmp/sidescreen-preflight.out 2>&1; then
    pass "Release checksums generated"
else
    if [ "$DISTRIBUTION" -eq 1 ]; then
        fail "Release checksums generated"
    else
        warn "Release checksums not generated; release artifacts are incomplete"
    fi
    print_matching_output "Missing artifact|❌|ERROR|WARNING" 40
fi

if "$SCRIPT_DIR/verify-android-signing.sh" "$VERIFY_MODE_ARG" >/tmp/sidescreen-preflight.out 2>&1; then
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

if "$SCRIPT_DIR/verify-mac-distribution.sh" "$VERIFY_MODE_ARG" >/tmp/sidescreen-preflight.out 2>&1; then
    pass "Mac Gatekeeper distribution readiness"
else
    STATUS=$?
    if [ "$STATUS" -eq 2 ]; then
        warn "Mac app/DMG not ready for Gatekeeper distribution"
        print_matching_output "rejected|source=|WARNING|OK:|Signature=|Authority=|stapler" 50
    else
        fail "Mac Gatekeeper distribution readiness"
        print_matching_output "ERROR|WARNING|rejected|source=|Signature=|Authority=|stapler" 50
    fi
fi

if [ -n "${SIDESCREEN_RELEASE_STORE_FILE:-}" ] &&
   [ -n "${SIDESCREEN_RELEASE_STORE_PASSWORD:-}" ] &&
   [ -n "${SIDESCREEN_RELEASE_KEY_ALIAS:-}" ] &&
   [ -n "${SIDESCREEN_RELEASE_KEY_PASSWORD:-}" ]; then
    if [ -f "$SIDESCREEN_RELEASE_STORE_FILE" ]; then
        pass "Android release signing env configured"
    else
        distribution_issue "Android release keystore file does not exist at SIDESCREEN_RELEASE_STORE_FILE"
    fi
else
    distribution_issue "Android release signing env missing; release APK/AAB will be debug-signed unless SIDESCREEN_REQUIRE_RELEASE_SIGNING=1"
fi

if [ -n "${SIDESCREEN_CODESIGN_IDENTITY:-}" ] && [ "${SIDESCREEN_CODESIGN_IDENTITY:-}" != "-" ]; then
    case "$SIDESCREEN_CODESIGN_IDENTITY" in
        Developer\ ID\ Application:*)
            pass "Mac Developer ID signing identity configured"
            ;;
        Apple\ Development:*)
            distribution_issue "Mac signing identity is Apple Development. Good for stable local TCC, not distribution."
            ;;
        *)
            distribution_issue "Mac signing identity is not Developer ID Application"
            ;;
    esac
elif security find-identity -v -p codesigning 2>/dev/null | grep -q '"Developer ID Application:'; then
    pass "Mac Developer ID signing identity available for auto-signing"
elif security find-identity -v -p codesigning 2>/dev/null | grep -q '"Apple Development:'; then
    distribution_issue "Only Apple Development signing identity found. Stable enough for local TCC, not distribution."
else
    distribution_issue "Mac Developer ID signing identity missing; Mac app/DMG will be ad-hoc signed and not notarized"
fi

if [ -n "${APPLE_ID:-}" ] &&
   [ -n "${APPLE_TEAM_ID:-}" ] &&
   [ -n "${APPLE_APP_SPECIFIC_PASSWORD:-}" ]; then
    pass "Mac notarization env configured"
else
    distribution_issue "Mac notarization env missing; set APPLE_ID, APPLE_TEAM_ID, and APPLE_APP_SPECIFIC_PASSWORD for distribution"
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
