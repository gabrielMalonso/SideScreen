#!/bin/bash
set -e

# Navigate to project root (parent of scripts directory)
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$ROOT_DIR"
PORT="${SIDESCREEN_PORT:-54321}"
VERSION=$(cat "$ROOT_DIR/VERSION" | tr -d '[:space:]')
INSTALL_MAC=1
INSTALL_ANDROID=1
REQUIRE_ANDROID=0

usage() {
    echo "Usage: ./scripts/install.sh [--mac-only] [--android-only] [--skip-android] [--require-android]"
    echo ""
    echo "Default: build/install the Mac app, then install Android only when one authorized ADB device is connected."
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --mac-only|--skip-android)
            INSTALL_ANDROID=0
            shift
            ;;
        --android-only)
            INSTALL_MAC=0
            REQUIRE_ANDROID=1
            shift
            ;;
        --require-android)
            REQUIRE_ANDROID=1
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown argument: $1"
            usage
            exit 1
            ;;
    esac
done

echo "🚀 Installing Side Screen..."
echo ""

if [ "$INSTALL_MAC" -eq 1 ]; then
    # Build macOS app
    echo "📦 Building macOS app..."
    cd MacHost
    swift build -c release
    cd "$ROOT_DIR"
    echo "  ✓ macOS app built"

    # Create macOS .app bundle
    echo "📦 Creating macOS .app bundle..."
    APP_NAME="SideScreen.app"
    APP_DIR="$ROOT_DIR/$APP_NAME"
    CONTENTS_DIR="$APP_DIR/Contents"
    rm -rf "$APP_DIR"
    mkdir -p "$CONTENTS_DIR/MacOS"
    mkdir -p "$CONTENTS_DIR/Resources"

    # Copy executable
    RELEASE_DIR="MacHost/.build/out/Products/Release"
    cp "$RELEASE_DIR/SideScreen" "$CONTENTS_DIR/MacOS/SideScreen"
    if [ -f "$RELEASE_DIR/SideScreenVirtualHIDHelper" ]; then
        cp "$RELEASE_DIR/SideScreenVirtualHIDHelper" "$CONTENTS_DIR/MacOS/SideScreenVirtualHIDHelper"
    fi
    if [ -f "MacHost/Resources/AppIcon.icns" ]; then
        cp "MacHost/Resources/AppIcon.icns" "$CONTENTS_DIR/Resources/AppIcon.icns"
    fi

    # Create Info.plist
    cat > "$CONTENTS_DIR/Info.plist" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>SideScreen</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleName</key>
    <string>Side Screen</string>
    <key>CFBundleDisplayName</key>
    <string>Side Screen</string>
    <key>CFBundleIdentifier</key>
    <string>com.sidescreen.app</string>
    <key>CFBundleVersion</key>
    <string>$VERSION</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSSupportsAutomaticGraphicsSwitching</key>
    <true/>
    <key>LSUIElement</key>
    <false/>
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
PLIST

    codesign --force --deep --sign - --entitlements "$ROOT_DIR/MacHost/SideScreen.entitlements" "$APP_DIR"
    echo "  ✓ macOS .app bundle created: $APP_NAME"
    echo ""
fi

if [ "$INSTALL_ANDROID" -eq 1 ]; then
    echo "📱 Checking Android device..."
    ADB_READY=0
    if . "$SCRIPT_DIR/adb-env.sh" >/tmp/sidescreen-install-adb.out 2>&1 &&
       sidescreen_select_adb_device >/tmp/sidescreen-install-device.out 2>&1; then
        ADB_READY=1
        echo "  ✓ Android device connected ($ANDROID_SERIAL)"
    else
        echo "  ⚠️  Android install skipped: no single authorized ADB device"
        cat /tmp/sidescreen-install-adb.out /tmp/sidescreen-install-device.out 2>/dev/null | sed 's/^/     /' || true
        echo "     Connect one Android device by USB, enable USB debugging, accept the prompt, then run:"
        echo "       ./scripts/install_android.sh"
        if [ "$REQUIRE_ANDROID" -eq 1 ]; then
            exit 1
        fi
    fi

    if [ "$ADB_READY" -eq 1 ]; then
        # Build Android app
        echo ""
        echo "📦 Building Android app..."
        . "$SCRIPT_DIR/android-env.sh"
        cd AndroidClient
        ./gradlew assembleDebug
        cd "$ROOT_DIR"
        echo "  ✓ Android app built"
        echo ""

        # Install Android app
        echo "📱 Installing Android app..."
        adb install -r AndroidClient/app/build/outputs/apk/debug/app-debug.apk
        echo "  ✓ Android app installed"
        echo ""

        # Setup ADB reverse (with retry)
        echo "🔧 Setting up USB port forwarding..."
        adb reverse --remove "tcp:$PORT" 2>/dev/null || true
        sleep 0.5
        adb reverse "tcp:$PORT" "tcp:$PORT"

        # Verify ADB reverse is active
        echo "🔍 Verifying port forwarding..."
        if adb reverse --list | grep -q "tcp:$PORT"; then
            echo "  ✓ Port $PORT forwarded successfully"
        else
            echo "  ⚠️  Port forwarding setup but verification failed"
            echo "  Run './scripts/setup-usb.sh' if connection issues occur"
        fi
        echo ""
    fi
fi

echo "✅ Installation complete!"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "To start streaming:"
if [ "$INSTALL_MAC" -eq 1 ]; then
    echo "  1. Start Mac app: open SideScreen.app"
    echo "     (or run: MacHost/.build/out/Products/Release/SideScreen)"
else
    echo "  1. Start the Mac app on the Mac"
fi
echo "  2. Open 'Side Screen' app on Android"
echo "  3. Tap Connect or pair via Wireless"
echo ""
echo "💡 Troubleshooting:"
echo "  • Android not installed yet: ./scripts/install_android.sh"
echo "  • Connection fails: ./scripts/setup-usb.sh"
echo "  • Check server: lsof -i :$PORT"
echo "  • Check forwarding: adb reverse --list"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
