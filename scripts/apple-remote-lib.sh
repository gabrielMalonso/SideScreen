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
APPLE_REMOTE_PATH_PREFIX="${APPLE_REMOTE_PATH_PREFIX:-/opt/homebrew/bin:/usr/local/bin}"
APPLE_REMOTE_CONNECT_TIMEOUT="${APPLE_REMOTE_CONNECT_TIMEOUT:-10}"

MACOS_PACKAGE_DIR="${MACOS_PACKAGE_DIR:-MacHost}"
MACOS_CONFIGURATION="${MACOS_CONFIGURATION:-debug}"
MACOS_RUN_TESTS="${MACOS_RUN_TESTS:-1}"
MACOS_RUN_SWIFTLINT="${MACOS_RUN_SWIFTLINT:-1}"

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
  path prefix: $APPLE_REMOTE_PATH_PREFIX
  package dir: $MACOS_PACKAGE_DIR
EOF
}

