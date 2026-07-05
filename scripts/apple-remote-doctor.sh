#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
. "$SCRIPT_DIR/apple-remote-lib.sh"

STATUS=0

check() {
    local label="$1"
    shift

    printf "%-32s" "$label"
    if "$@" >/tmp/apple-remote-doctor.out 2>&1; then
        echo "OK"
    else
        echo "FAIL"
        sed 's/^/  /' /tmp/apple-remote-doctor.out
        STATUS=1
    fi
}

check_optional() {
    local label="$1"
    shift

    printf "%-32s" "$label"
    if "$@" >/tmp/apple-remote-doctor.out 2>&1; then
        echo "OK"
    else
        echo "missing"
        sed 's/^/  /' /tmp/apple-remote-doctor.out
    fi
}

check_if_configured() {
    local value="$1"
    local label="$2"
    shift 2

    if [ -n "$value" ]; then
        check "$label" "$@"
    fi
}

apple_remote_print_config
echo

printf "%-32s" "known_hosts"
APPLE_REMOTE_RESOLVED_HOST="$(ssh -G "$APPLE_REMOTE_HOST" 2>/dev/null | awk '/^hostname / {print $2; exit}')"
APPLE_REMOTE_RESOLVED_HOST="${APPLE_REMOTE_RESOLVED_HOST:-$APPLE_REMOTE_HOST}"
if ssh-keygen -F "$APPLE_REMOTE_HOST" >/tmp/apple-remote-doctor.out 2>&1 || \
    ssh-keygen -F "$APPLE_REMOTE_RESOLVED_HOST" >/tmp/apple-remote-doctor.out 2>&1; then
    echo "OK"
else
    echo "missing"
    echo "  Run scripts/apple-remote-trust-host.sh if SSH asks to trust the Mac key."
fi

printf "%-32s" "ssh connects"
if apple_remote_ssh "true" >/tmp/apple-remote-doctor.out 2>&1; then
    echo "OK"
else
    echo "FAIL"
    sed 's/^/  /' /tmp/apple-remote-doctor.out
    echo
    echo "SSH is blocked, so the Apple runner cannot be checked yet."
    exit 1
fi

check "remote mirror path exists" apple_remote_ssh "test -d '$APPLE_REMOTE_PATH'"
check "remote mirror writable" apple_remote_ssh "test -w '$APPLE_REMOTE_PATH'"
check_if_configured "$APPLE_REMOTE_DERIVED_DATA" "derived data writable" \
    apple_remote_ssh "mkdir -p '$APPLE_REMOTE_DERIVED_DATA' && test -w '$APPLE_REMOTE_DERIVED_DATA'"
check "macOS version/arch" apple_remote_ssh "sw_vers && uname -m"
check "remote PATH" apple_remote_ssh "export PATH='$APPLE_REMOTE_PATH_PREFIX':\"\$PATH\" && printf '%s\n' \"\$PATH\""
check "xcodebuild" apple_remote_ssh "export PATH='$APPLE_REMOTE_PATH_PREFIX':\"\$PATH\" && xcodebuild -version"
check "xcode-select" apple_remote_ssh "xcode-select -p"
check "swift" apple_remote_ssh "export PATH='$APPLE_REMOTE_PATH_PREFIX':\"\$PATH\" && swift --version"
check "xcrun" apple_remote_ssh "export PATH='$APPLE_REMOTE_PATH_PREFIX':\"\$PATH\" && command -v xcrun"
check "rsync on Mac" apple_remote_ssh "command -v rsync"
check_optional "swiftlint" apple_remote_ssh "export PATH='$APPLE_REMOTE_PATH_PREFIX':\"\$PATH\" && command -v swiftlint"
check_optional "xcodegen" apple_remote_ssh "export PATH='$APPLE_REMOTE_PATH_PREFIX':\"\$PATH\" && command -v xcodegen"
check_if_configured "$MACOS_BUILD_PRODUCTS_DIR" "macOS products writable" \
    apple_remote_ssh "mkdir -p '$MACOS_BUILD_PRODUCTS_DIR' && test -w '$MACOS_BUILD_PRODUCTS_DIR'"

if [ -n "$IOS_PROJECT" ] && [ -n "$IOS_SCHEME" ]; then
    check "iOS simulator exists" apple_remote_ssh \
        "export PATH='$APPLE_REMOTE_PATH_PREFIX':\"\$PATH\" && xcrun simctl list devices available | grep -F '$IOS_SIMULATOR_NAME'"
fi

echo
if [ "$STATUS" -eq 0 ]; then
    echo "Doctor passed. The remote Apple runner is reachable."
else
    echo "Doctor found a real setup problem. Fix that before blaming the app."
fi

exit "$STATUS"
