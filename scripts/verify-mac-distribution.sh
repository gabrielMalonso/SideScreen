#!/bin/bash
set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
VERSION="$(tr -d '[:space:]' < "$ROOT_DIR/VERSION")"
APP="$ROOT_DIR/SideScreen.app"
DMG="$ROOT_DIR/SideScreen-$VERSION-mac-arm64.dmg"
WARN=0

if [ ! -d "$APP" ]; then
    echo "ERROR: SideScreen.app missing: $APP"
    exit 1
fi

if [ ! -f "$DMG" ]; then
    echo "ERROR: Mac DMG missing: $DMG"
    exit 1
fi

echo "## App code signature"
if codesign --verify --deep --strict --verbose=2 "$APP"; then
    echo "OK: app code signature verifies"
else
    echo "ERROR: app code signature does not verify"
    exit 1
fi

echo ""
echo "## App Gatekeeper assessment"
if spctl -a -vv "$APP" >/tmp/sidescreen-spctl-app.out 2>&1; then
    cat /tmp/sidescreen-spctl-app.out
    echo "OK: Gatekeeper accepts SideScreen.app"
else
    cat /tmp/sidescreen-spctl-app.out
    echo "WARNING: Gatekeeper rejects SideScreen.app. Use Developer ID signing and notarization for distribution."
    WARN=1
fi

echo ""
echo "## DMG Gatekeeper assessment"
if spctl -a -vv -t open "$DMG" >/tmp/sidescreen-spctl-dmg.out 2>&1; then
    cat /tmp/sidescreen-spctl-dmg.out
    echo "OK: Gatekeeper accepts DMG"
else
    cat /tmp/sidescreen-spctl-dmg.out
    echo "WARNING: Gatekeeper rejects DMG. Sign, notarize, and staple the DMG before distribution."
    WARN=1
fi

if [ "$WARN" -eq 1 ]; then
    exit 2
fi

exit 0
