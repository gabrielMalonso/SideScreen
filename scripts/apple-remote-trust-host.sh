#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
. "$SCRIPT_DIR/apple-remote-lib.sh"

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
    echo "Usage: $0"
    echo
    echo "Registers the current Mac SSH host key in ~/.ssh/known_hosts."
    exit 0
fi

SSH_HOST="$APPLE_REMOTE_HOST"
SSH_PORT="22"

if command -v ssh >/dev/null 2>&1; then
    SSH_HOST="$(ssh -G "$APPLE_REMOTE_HOST" 2>/dev/null | awk '/^hostname / {print $2; exit}')"
    SSH_PORT="$(ssh -G "$APPLE_REMOTE_HOST" 2>/dev/null | awk '/^port / {print $2; exit}')"
    SSH_HOST="${SSH_HOST:-$APPLE_REMOTE_HOST}"
    SSH_PORT="${SSH_PORT:-22}"
fi

mkdir -p "$HOME/.ssh"
chmod 700 "$HOME/.ssh"
touch "$HOME/.ssh/known_hosts"
chmod 600 "$HOME/.ssh/known_hosts"

if ssh-keygen -F "$APPLE_REMOTE_HOST" >/dev/null 2>&1 || ssh-keygen -F "$SSH_HOST" >/dev/null 2>&1; then
    echo "Host key already registered for $APPLE_REMOTE_HOST."
    exit 0
fi

echo "Scanning SSH host key for $APPLE_REMOTE_HOST ($SSH_HOST:$SSH_PORT)..."
ssh-keyscan -T "$APPLE_REMOTE_CONNECT_TIMEOUT" -p "$SSH_PORT" -H "$SSH_HOST" >> "$HOME/.ssh/known_hosts"
echo "Host key registered in ~/.ssh/known_hosts."
