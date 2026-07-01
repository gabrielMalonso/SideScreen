#!/bin/bash
set -e

# Get absolute path to root directory
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# Read version
VERSION=$(cat "$ROOT_DIR/VERSION" | tr -d '[:space:]')
SIGN_IDENTITY="${SIDESCREEN_CODESIGN_IDENTITY:-auto}"
NOTARIZE="${SIDESCREEN_NOTARIZE:-0}"
echo "Building version $VERSION..."

resolve_sign_identity() {
    if [ "$SIGN_IDENTITY" != "auto" ]; then
        echo "$SIGN_IDENTITY"
        return
    fi

    local identity
    identity="$(security find-identity -v -p codesigning 2>/dev/null |
        sed -n 's/.*"\(Developer ID Application:[^"]*\)".*/\1/p' |
        head -1)"
    if [ -z "$identity" ]; then
        identity="$(security find-identity -v -p codesigning 2>/dev/null |
            sed -n 's/.*"\(Apple Development:[^"]*\)".*/\1/p' |
            head -1)"
    fi

    if [ -n "$identity" ]; then
        echo "$identity"
    else
        echo "-"
    fi
}

SIGN_IDENTITY="$(resolve_sign_identity)"
if [ "$SIGN_IDENTITY" = "-" ]; then
    echo "Code signing identity: ad-hoc (set SIDESCREEN_CODESIGN_IDENTITY for stable macOS permissions)"
else
    echo "Code signing identity: $SIGN_IDENTITY"
fi

cd "$ROOT_DIR/MacHost"

# Kill running instance
echo "Stopping running Side Screen..."
pkill -x SideScreen 2>/dev/null || true
sleep 0.5

# Clean old build
echo "Cleaning old build..."
rm -rf .build

# Build fresh. Modern SwiftPM/Xcode writes the release product under
# .build/out/Products/Release for this package.
echo "Building macOS Host (arm64)..."
swift build -c release

RELEASE_DIR=".build/out/Products/Release"
APP_BINARY="$RELEASE_DIR/SideScreen"
HELPER_BINARY="$RELEASE_DIR/SideScreenVirtualHIDHelper"

if [ ! -f "$APP_BINARY" ]; then
    echo "❌ Expected app binary not found: $APP_BINARY"
    exit 1
fi

# Create .app bundle
APP_NAME="SideScreen"
APP_DIR="$ROOT_DIR/$APP_NAME.app"

echo "Creating app bundle..."
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

# Copy binaries
cp "$APP_BINARY" "$APP_DIR/Contents/MacOS/"
if [ -f "$HELPER_BINARY" ]; then
    cp "$HELPER_BINARY" "$APP_DIR/Contents/MacOS/"
fi

# Copy app icon if exists
if [ -f "$ROOT_DIR/MacHost/Resources/AppIcon.icns" ]; then
    cp "$ROOT_DIR/MacHost/Resources/AppIcon.icns" "$APP_DIR/Contents/Resources/"
    echo "  ✓ App icon copied"
fi

# Create Info.plist
cat > "$APP_DIR/Contents/Info.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>SideScreen</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>com.sidescreen.app</string>
    <key>CFBundleName</key>
    <string>Side Screen</string>
    <key>CFBundleDisplayName</key>
    <string>Side Screen</string>
    <key>CFBundleVersion</key>
    <string>$VERSION</string><!-- VERSION -->
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string><!-- VERSION -->
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <false/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSSupportsAutomaticGraphicsSwitching</key>
    <true/>
    <key>NSScreenCaptureUsageDescription</key>
    <string>Side Screen needs screen recording access to capture your virtual display and stream it to your Android device.</string>
    <key>NSLocalNetworkUsageDescription</key>
    <string>Side Screen needs Local Network access so your Android tablet can connect to the Mac over WiFi for wireless mode. Without this, only USB-tethered connections work.</string>
    <key>NSBonjourServices</key>
    <array>
        <string>_sidescreen._tcp</string>
    </array>
</dict>
</plist>
EOF

if [ "$SIGN_IDENTITY" = "-" ]; then
    echo "Code signing (ad-hoc)..."
    codesign --force --deep --sign - --entitlements "$ROOT_DIR/MacHost/SideScreen.entitlements" "$APP_DIR"
    echo "  ✓ App signed ad-hoc"
else
    echo "Code signing (Developer ID: $SIGN_IDENTITY)..."
    codesign --force --deep --timestamp --options runtime --sign "$SIGN_IDENTITY" --entitlements "$ROOT_DIR/MacHost/SideScreen.entitlements" "$APP_DIR"
    echo "  ✓ App signed with Developer ID"
fi

echo ""
echo "Build successful!"
echo ""
echo "App: $ROOT_DIR/$APP_NAME.app"
echo "To run: open $APP_NAME.app"

# Create DMG with Applications symlink
echo ""
echo "Creating DMG..."
DMG_DIR=$(mktemp -d)
cp -R "$APP_DIR" "$DMG_DIR/"
ln -s /Applications "$DMG_DIR/Applications"
DMG_PATH="$ROOT_DIR/SideScreen-${VERSION}-mac-arm64.dmg"
hdiutil create -volname "Side Screen" -srcfolder "$DMG_DIR" -ov -format UDZO "$DMG_PATH"
rm -rf "$DMG_DIR"

if [ "$SIGN_IDENTITY" != "-" ]; then
    echo "Signing DMG..."
    codesign --force --timestamp --sign "$SIGN_IDENTITY" "$DMG_PATH"
fi

if [ "$NOTARIZE" = "1" ]; then
    if [ "$SIGN_IDENTITY" = "-" ]; then
        echo "❌ SIDESCREEN_NOTARIZE=1 requires SIDESCREEN_CODESIGN_IDENTITY"
        exit 1
    fi
    if [ -z "${APPLE_ID:-}" ] || [ -z "${APPLE_TEAM_ID:-}" ] || [ -z "${APPLE_APP_SPECIFIC_PASSWORD:-}" ]; then
        echo "❌ Notarization requires APPLE_ID, APPLE_TEAM_ID, and APPLE_APP_SPECIFIC_PASSWORD"
        exit 1
    fi

    echo "Submitting DMG for notarization..."
    xcrun notarytool submit "$DMG_PATH" \
        --apple-id "$APPLE_ID" \
        --team-id "$APPLE_TEAM_ID" \
        --password "$APPLE_APP_SPECIFIC_PASSWORD" \
        --wait
    xcrun stapler staple "$DMG_PATH"
    echo "  ✓ DMG notarized and stapled"
elif [ "$SIGN_IDENTITY" = "-" ]; then
    echo "Not notarized: set SIDESCREEN_CODESIGN_IDENTITY and SIDESCREEN_NOTARIZE=1 for distributable builds."
fi

echo "DMG: $DMG_PATH"
