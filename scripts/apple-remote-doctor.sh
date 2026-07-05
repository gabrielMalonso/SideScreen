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

apple_remote_print_config
echo

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
check "xcodebuild" apple_remote_ssh "export PATH='$APPLE_REMOTE_PATH_PREFIX':\"\$PATH\" && xcodebuild -version"
check "swift" apple_remote_ssh "export PATH='$APPLE_REMOTE_PATH_PREFIX':\"\$PATH\" && swift --version"
check "rsync on Mac" apple_remote_ssh "command -v rsync"
check_optional "swiftlint" apple_remote_ssh "export PATH='$APPLE_REMOTE_PATH_PREFIX':\"\$PATH\" && command -v swiftlint"
check_optional "xcrun" apple_remote_ssh "export PATH='$APPLE_REMOTE_PATH_PREFIX':\"\$PATH\" && command -v xcrun"

echo
if [ "$STATUS" -eq 0 ]; then
    echo "Doctor passed. The remote Apple runner is reachable."
else
    echo "Doctor found a real setup problem. Fix that before blaming the app."
fi

exit "$STATUS"
