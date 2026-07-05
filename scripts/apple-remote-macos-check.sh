#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
. "$SCRIPT_DIR/apple-remote-lib.sh"

SYNC=1
FRESH_SYNC=0
RESOLVE_PACKAGES=0

while [ "$#" -gt 0 ]; do
    case "$1" in
        --no-sync) SYNC=0 ;;
        --fresh-sync) FRESH_SYNC=1 ;;
        --resolve-packages) RESOLVE_PACKAGES=1 ;;
        -h|--help)
            cat <<EOF
Usage: $0 [--no-sync] [--fresh-sync] [--resolve-packages]

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
    if [ "$FRESH_SYNC" -eq 1 ]; then
        "$SCRIPT_DIR/apple-remote-sync.sh" --fresh
    else
        "$SCRIPT_DIR/apple-remote-sync.sh"
    fi
fi

REMOTE_SCRIPT=$(cat <<EOF
set -euo pipefail
export PATH='$APPLE_REMOTE_PATH_PREFIX':"\$PATH"
cd '$APPLE_REMOTE_PATH/$MACOS_PACKAGE_DIR'

echo "[1/4] Swift version"
swift --version

if [ -n '$MACOS_PROJECT' ] && [ -n '$MACOS_SCHEME' ]; then
    echo "[2/4] Xcode project"
    XCODE_COMMON_ARGS=(
        -project '$MACOS_PROJECT'
        -scheme '$MACOS_SCHEME'
        -configuration '$MACOS_CONFIGURATION'
        -destination '$MACOS_DESTINATION'
    )

    if [ -n '$MACOS_DERIVED_DATA' ]; then
        mkdir -p '$MACOS_DERIVED_DATA'
        XCODE_COMMON_ARGS+=(-derivedDataPath '$MACOS_DERIVED_DATA')
    fi

    xcodebuild "\${XCODE_COMMON_ARGS[@]}" \\
        CODE_SIGNING_ALLOWED='$MACOS_CODE_SIGNING_ALLOWED' \\
        CODE_SIGNING_REQUIRED='$MACOS_CODE_SIGNING_REQUIRED' \\
        build

    if [ "$MACOS_RUN_TESTS" = "1" ]; then
        echo "[3/4] Xcode tests"
        mkdir -p '$MACOS_BUILD_PRODUCTS_DIR'
        xcodebuild "\${XCODE_COMMON_ARGS[@]}" \\
            CODE_SIGNING_ALLOWED='$MACOS_CODE_SIGNING_ALLOWED' \\
            CODE_SIGNING_REQUIRED='$MACOS_CODE_SIGNING_REQUIRED' \\
            SYMROOT='$MACOS_BUILD_PRODUCTS_DIR' \\
            OBJROOT='$MACOS_BUILD_PRODUCTS_DIR/Intermediates.noindex' \\
            -parallel-testing-enabled '$MACOS_PARALLEL_TESTING_ENABLED' \\
            test
    else
        echo "[3/4] Tests disabled by MACOS_RUN_TESTS=0"
    fi
else
    if [ "$RESOLVE_PACKAGES" -eq 1 ]; then
        echo "[2/4] Resolving Swift packages"
        swift package resolve
    else
        echo "[2/4] Skipping package resolve"
    fi

    echo "[3/4] Building Swift package ($MACOS_CONFIGURATION)"
    swift build -c '$MACOS_CONFIGURATION'

    if [ "$MACOS_RUN_TESTS" = "1" ]; then
        echo "[4/4] Running Swift package tests"
        swift test
    else
        echo "[4/4] Tests disabled by MACOS_RUN_TESTS=0"
    fi
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
