#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
. "$SCRIPT_DIR/apple-remote-lib.sh"

DRY_RUN=0
while [ "$#" -gt 0 ]; do
    case "$1" in
        --dry-run) DRY_RUN=1 ;;
        -h|--help)
            echo "Usage: $0 [--dry-run]"
            exit 0
            ;;
        *)
            echo "Unknown argument: $1" >&2
            exit 2
            ;;
    esac
    shift
done

apple_remote_print_config
echo

if [ "$DRY_RUN" -eq 1 ]; then
    if ! apple_remote_ssh "test -d '$APPLE_REMOTE_PATH'"; then
        echo "Remote path does not exist yet: $APPLE_REMOTE_PATH" >&2
        echo "Run scripts/apple-remote-sync.sh once to create it." >&2
        exit 1
    fi
else
    apple_remote_ssh "mkdir -p '$APPLE_REMOTE_PATH'"
fi

RSYNC_ARGS=(
    -az
    --delete
    --delete-excluded
    --info=stats2,progress2
    --exclude='.git/'
    --exclude='.apple-remote.env'
    --exclude='**/.DS_Store'
    --exclude='**/node_modules/'
    --exclude='**/.gradle/'
    --exclude='**/.build/'
    --exclude='**/.swiftpm/'
    --exclude='**/DerivedData/'
    --exclude='**/build/'
    --exclude='**/dist/'
    --exclude='**/*.xcworkspace/'
    --exclude='**/*.xcodeproj/xcuserdata/'
    --exclude='**/*.xcuserdata/'
    --exclude='**/.idea/'
    --exclude='**/.vscode/'
    --exclude='**/.Codex/'
    --exclude='**/.claude/'
    --exclude='**/.t3code/'
    --exclude='**/.playwright-mcp/'
    --exclude='**/*.apk'
    --exclude='**/*.aab'
    --exclude='**/*.dmg'
    --exclude='**/*.dSYM/'
    --exclude='docs/'
    --exclude='tmp/'
    --exclude='temp/'
)

if [ "$DRY_RUN" -eq 1 ]; then
    RSYNC_ARGS+=(--dry-run --itemize-changes)
fi

rsync "${RSYNC_ARGS[@]}" "$APPLE_REMOTE_ROOT_DIR/" "$APPLE_REMOTE_HOST:$APPLE_REMOTE_PATH/"

if [ "$DRY_RUN" -eq 1 ]; then
    echo
    echo "Dry run complete. Nothing changed on the Mac."
else
    echo
    echo "Synced Ubuntu workspace to Mac mirror."
fi
