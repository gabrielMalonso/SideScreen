#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
VERSION=$(cat "$ROOT_DIR/VERSION" | tr -d '[:space:]')
APP_DIR="$ROOT_DIR/SideScreen.app"
PORT="${SIDESCREEN_PORT:-54321}"
ADB_AVAILABLE=0

echo "======================================="
echo "  Side Screen - Dev Test (v$VERSION)"
echo "======================================="
echo ""

# 1. Build macOS
echo "[1/5] Building macOS..."
cd "$ROOT_DIR/MacHost"
swift build -c release 2>&1 | tail -3
echo "  OK"

# 2. Create .app bundle (keeps permissions across rebuilds)
echo "[2/5] Creating .app bundle..."
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"
cp .build/out/Products/Release/SideScreen "$APP_DIR/Contents/MacOS/"
if [ -f ".build/out/Products/Release/SideScreenVirtualHIDHelper" ]; then
    cp .build/out/Products/Release/SideScreenVirtualHIDHelper "$APP_DIR/Contents/MacOS/"
fi

if [ -f "Resources/AppIcon.icns" ]; then
    cp Resources/AppIcon.icns "$APP_DIR/Contents/Resources/"
fi

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
    <key>CFBundleVersion</key>
    <string>$VERSION</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
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

codesign --force --deep --sign - --entitlements "$ROOT_DIR/MacHost/SideScreen.entitlements" "$APP_DIR" 2>/dev/null
echo "  OK"

# 3. Build Android
echo "[3/5] Building Android..."
cd "$ROOT_DIR/AndroidClient"
. "$SCRIPT_DIR/android-env.sh"
./gradlew assembleDebug -q
APK="$ROOT_DIR/AndroidClient/app/build/outputs/apk/debug/app-debug.apk"
echo "  OK"

# 4. Install APK on device
echo "[4/5] Installing APK..."
if . "$SCRIPT_DIR/adb-env.sh" >/tmp/sidescreen-dev-test-adb.out 2>&1; then
    ADB_AVAILABLE=1
fi

if [ "$ADB_AVAILABLE" -eq 1 ] && sidescreen_select_adb_device >/tmp/sidescreen-dev-test-device.out 2>&1; then
    adb install -r "$APK" 2>&1 | tail -1
else
    echo "  No device connected, skipping install"
fi

# 5. Run macOS app
echo "[5/5] Starting macOS app..."
pkill -f "SideScreen.app" 2>/dev/null || true
sleep 0.5

if [ "$ADB_AVAILABLE" -eq 1 ] && [ -n "${ANDROID_SERIAL:-}" ]; then
    adb reverse "tcp:$PORT" "tcp:$PORT" 2>/dev/null || true
fi
open "$APP_DIR"

echo ""
echo "======================================="
echo "  Ready to test!"
echo "  App: $APP_DIR"
echo "  Open Side Screen on your tablet"
echo "======================================="
echo ""
read -p "Test result? [y=OK / n=failed]: " RESULT

pkill -f "SideScreen.app" 2>/dev/null || true

if [ "$RESULT" = "y" ]; then
    echo ""
    echo "Test passed. Ready to push."
else
    echo ""
    echo "Test failed. Fix and re-run."
    exit 1
fi
