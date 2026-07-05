#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
. "$SCRIPT_DIR/apple-remote-lib.sh"

SYNC=1
RESOLVE_PACKAGES=0

while [ "$#" -gt 0 ]; do
    case "$1" in
        --no-sync) SYNC=0 ;;
        --resolve-packages) RESOLVE_PACKAGES=1 ;;
        -h|--help)
            cat <<EOF
Usage: $0 [--no-sync] [--resolve-packages]

Runs macOS Swift checks on the remote Mac mirror.
EOF
            exit 0
            ;;
        *)
            echo "Unknown argument: $1" >&2
            exit 2
            ;;
    esac
    shift
done

if [ "$SYNC" -eq 1 ]; then
    "$SCRIPT_DIR/apple-remote-sync.sh"
fi

REMOTE_SCRIPT=$(cat <<EOF
set -euo pipefail
export PATH='$APPLE_REMOTE_PATH_PREFIX':"\$PATH"
cd '$APPLE_REMOTE_PATH/$MACOS_PACKAGE_DIR'

echo "[1/4] Swift version"
swift --version

if [ "$RESOLVE_PACKAGES" -eq 1 ]; then
    echo "[2/4] Resolving Swift packages"
    swift package resolve
else
    echo "[2/4] Skipping package resolve"
fi

echo "[3/4] Building SideScreen ($MACOS_CONFIGURATION)"
swift build -c '$MACOS_CONFIGURATION'

if [ "$MACOS_RUN_TESTS" = "1" ]; then
    echo "[4/4] Running tests"
    swift test
else
    echo "[4/4] Tests disabled by MACOS_RUN_TESTS=0"
fi

if [ "$MACOS_RUN_SWIFTLINT" = "1" ]; then
    if command -v swiftlint >/dev/null 2>&1; then
        echo "[lint] Running swiftlint"
        swiftlint lint --config .swiftlint.yml --strict
    else
        echo "[lint] swiftlint not found; skipping"
    fi
fi
EOF
)

apple_remote_run "$REMOTE_SCRIPT"

echo
echo "Remote macOS check passed."

