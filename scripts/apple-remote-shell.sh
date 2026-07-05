#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
. "$SCRIPT_DIR/apple-remote-lib.sh"

SYNC=0
while [ "$#" -gt 0 ]; do
    case "$1" in
        --sync) SYNC=1 ;;
        -h|--help)
            echo "Usage: $0 [--sync]"
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

apple_remote_print_config
echo
ssh -t -o ConnectTimeout="$APPLE_REMOTE_CONNECT_TIMEOUT" "$APPLE_REMOTE_HOST" \
    "cd '$APPLE_REMOTE_PATH' && export PATH='$APPLE_REMOTE_PATH_PREFIX':\"\$PATH\" && exec \$SHELL -l"
