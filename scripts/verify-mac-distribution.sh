#!/bin/bash
set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
VERSION="$(tr -d '[:space:]' < "$ROOT_DIR/VERSION")"
APP="$ROOT_DIR/RemoteMac.app"
DMG="$ROOT_DIR/RemoteMac-$VERSION-mac-arm64.dmg"
WARN=0
FAIL=0
DISTRIBUTION=0

usage() {
    cat <<EOF
Usage: ./scripts/verify-mac-distribution.sh [--dev|--release|--distribution]

Default dev mode exits 2 for Gatekeeper/notarization warnings.
Release/distribution mode exits 1 for the same conditions.
EOF
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --dev)
            DISTRIBUTION=0
            ;;
        --release|--distribution)
            DISTRIBUTION=1
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "ERROR: Unknown argument: $1" >&2
            usage >&2
            exit 64
            ;;
    esac
    shift
done

issue() {
    if [ "$DISTRIBUTION" -eq 1 ]; then
        echo "ERROR: $1"
        FAIL=1
    else
        echo "WARNING: $1"
        WARN=1
    fi
}

if [ ! -d "$APP" ]; then
    echo "ERROR: RemoteMac.app missing: $APP"
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
echo "## App signing identity"
if codesign -dv --verbose=4 "$APP" >/tmp/sidescreen-codesign-app.out 2>&1; then
    grep -E "Authority=|TeamIdentifier=|Runtime Version|Signature=" /tmp/sidescreen-codesign-app.out || true
    if grep -q "Authority=Developer ID Application:" /tmp/sidescreen-codesign-app.out; then
        echo "OK: app is signed with Developer ID Application"
    elif grep -q "Authority=Apple Development:" /tmp/sidescreen-codesign-app.out; then
        issue "app is signed with Apple Development. That is stable enough for local TCC, but not for distribution."
    elif grep -q "Signature=adhoc" /tmp/sidescreen-codesign-app.out; then
        issue "app is ad-hoc signed. macOS TCC permissions can be noisy across rebuilds, and Gatekeeper distribution will fail."
    else
        issue "app is not signed with a Developer ID Application identity."
    fi
else
    cat /tmp/sidescreen-codesign-app.out
    echo "ERROR: unable to inspect app signing identity"
    exit 1
fi

echo ""
echo "## App Gatekeeper assessment"
if spctl -a -vv "$APP" >/tmp/sidescreen-spctl-app.out 2>&1; then
    cat /tmp/sidescreen-spctl-app.out
    echo "OK: Gatekeeper accepts RemoteMac.app"
else
    cat /tmp/sidescreen-spctl-app.out
    issue "Gatekeeper rejects RemoteMac.app. Use Developer ID signing and notarization for distribution."
fi

echo ""
echo "## DMG signing identity"
if codesign -dv --verbose=4 "$DMG" >/tmp/sidescreen-codesign-dmg.out 2>&1; then
    grep -E "Authority=|TeamIdentifier=|Signature=" /tmp/sidescreen-codesign-dmg.out || true
    if grep -q "Authority=Developer ID Application:" /tmp/sidescreen-codesign-dmg.out; then
        echo "OK: DMG is signed with Developer ID Application"
    elif grep -q "Signature=adhoc" /tmp/sidescreen-codesign-dmg.out; then
        issue "DMG is ad-hoc signed. Sign it with Developer ID before distribution."
    else
        issue "DMG is not signed with a Developer ID Application identity."
    fi
else
    cat /tmp/sidescreen-codesign-dmg.out
    issue "unable to inspect DMG signing identity."
fi

echo ""
echo "## DMG Gatekeeper assessment"
if spctl -a -vv -t open "$DMG" >/tmp/sidescreen-spctl-dmg.out 2>&1; then
    cat /tmp/sidescreen-spctl-dmg.out
    echo "OK: Gatekeeper accepts DMG"
else
    cat /tmp/sidescreen-spctl-dmg.out
    issue "Gatekeeper rejects DMG. Sign, notarize, and staple the DMG before distribution."
fi

echo ""
echo "## DMG notarization staple"
if command -v xcrun >/dev/null 2>&1; then
    if xcrun stapler validate "$DMG" >/tmp/sidescreen-stapler-dmg.out 2>&1; then
        cat /tmp/sidescreen-stapler-dmg.out
        echo "OK: DMG has a valid notarization staple"
    else
        cat /tmp/sidescreen-stapler-dmg.out
        issue "DMG is not notarized/stapled. Do not distribute it outside local dev."
    fi
else
    issue "xcrun unavailable; cannot validate notarization staple."
fi

if [ "$FAIL" -eq 1 ]; then
    exit 1
fi

if [ "$WARN" -eq 1 ]; then
    exit 2
fi

exit 0
