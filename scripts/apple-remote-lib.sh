#!/usr/bin/env bash
set -euo pipefail

APPLE_REMOTE_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APPLE_REMOTE_ROOT_DIR="$(cd "$APPLE_REMOTE_SCRIPT_DIR/.." && pwd)"
APPLE_REMOTE_ENV_FILE="$APPLE_REMOTE_ROOT_DIR/.apple-remote.env"

if [ -f "$APPLE_REMOTE_ENV_FILE" ]; then
    set -a
    # shellcheck disable=SC1090
    . "$APPLE_REMOTE_ENV_FILE"
    set +a
fi

APPLE_REMOTE_HOST="${APPLE_REMOTE_HOST:-mac-mini}"
APPLE_REMOTE_PATH="${APPLE_REMOTE_PATH:-/Users/gabrielalonso/dev/sidescreen-linux-mirror}"
APPLE_REMOTE_DERIVED_DATA="${APPLE_REMOTE_DERIVED_DATA:-}"
APPLE_REMOTE_PATH_PREFIX="${APPLE_REMOTE_PATH_PREFIX:-/opt/homebrew/bin:/usr/local/bin}"
APPLE_REMOTE_CONNECT_TIMEOUT="${APPLE_REMOTE_CONNECT_TIMEOUT:-10}"
APPLE_REMOTE_RSYNC_PROTOCOL="${APPLE_REMOTE_RSYNC_PROTOCOL:-29}"

MACOS_PACKAGE_DIR="${MACOS_PACKAGE_DIR:-MacHost}"
MACOS_CONFIGURATION="${MACOS_CONFIGURATION:-debug}"
MACOS_RUN_TESTS="${MACOS_RUN_TESTS:-1}"
MACOS_RUN_SWIFTLINT="${MACOS_RUN_SWIFTLINT:-1}"
MACOS_PROJECT="${MACOS_PROJECT:-}"
MACOS_SCHEME="${MACOS_SCHEME:-}"
MACOS_DESTINATION="${MACOS_DESTINATION:-platform=macOS,arch=arm64}"
MACOS_DERIVED_DATA="${MACOS_DERIVED_DATA:-${APPLE_REMOTE_DERIVED_DATA:+$APPLE_REMOTE_DERIVED_DATA/macos}}"
MACOS_BUILD_PRODUCTS_DIR="${MACOS_BUILD_PRODUCTS_DIR:-/tmp/sidescreen-xcode-products/macos}"
MACOS_PARALLEL_TESTING_ENABLED="${MACOS_PARALLEL_TESTING_ENABLED:-NO}"
MACOS_CODE_SIGNING_ALLOWED="${MACOS_CODE_SIGNING_ALLOWED:-NO}"
MACOS_CODE_SIGNING_REQUIRED="${MACOS_CODE_SIGNING_REQUIRED:-NO}"

IOS_SIMULATOR_NAME="${IOS_SIMULATOR_NAME:-iPhone 17}"
IOS_PROJECT="${IOS_PROJECT:-}"
IOS_SCHEME="${IOS_SCHEME:-}"
IOS_DERIVED_DATA="${IOS_DERIVED_DATA:-${APPLE_REMOTE_DERIVED_DATA:+$APPLE_REMOTE_DERIVED_DATA/ios}}"

apple_remote_usage_env() {
    cat <<EOF
Configure the remote Mac in .apple-remote.env:

  cp scripts/apple-remote.env.example .apple-remote.env
  \$EDITOR .apple-remote.env
EOF
}

apple_remote_ssh() {
    ssh -o ConnectTimeout="$APPLE_REMOTE_CONNECT_TIMEOUT" "$APPLE_REMOTE_HOST" "$@"
}

apple_remote_run() {
    local command="$1"
    apple_remote_ssh "cd '$APPLE_REMOTE_PATH' && export PATH='$APPLE_REMOTE_PATH_PREFIX':\"\$PATH\" && $command"
}

apple_remote_print_config() {
    cat <<EOF
Remote Apple config
  host: $APPLE_REMOTE_HOST
  path: $APPLE_REMOTE_PATH
  derived data: ${APPLE_REMOTE_DERIVED_DATA:-default}
  path prefix: $APPLE_REMOTE_PATH_PREFIX
  rsync protocol: ${APPLE_REMOTE_RSYNC_PROTOCOL:-auto}
  package dir: $MACOS_PACKAGE_DIR
  macOS project: ${MACOS_PROJECT:-SwiftPM}
  macOS scheme: ${MACOS_SCHEME:-SwiftPM}
  macOS destination: $MACOS_DESTINATION
  macOS derived data: ${MACOS_DERIVED_DATA:-default}
  macOS products: $MACOS_BUILD_PRODUCTS_DIR
EOF
}
