#!/bin/bash

adb_env_fail() {
    echo "❌ adb not found. Install it with: brew install android-platform-tools"
    echo "   Or install Android SDK Platform Tools and set ANDROID_HOME."
    return 1 2>/dev/null || exit 1
}

if [ -n "${ANDROID_HOME:-}" ] && [ -d "$ANDROID_HOME/platform-tools" ]; then
    export PATH="$ANDROID_HOME/platform-tools:$PATH"
elif [ -d "$HOME/Library/Android/sdk/platform-tools" ]; then
    export ANDROID_HOME="${ANDROID_HOME:-$HOME/Library/Android/sdk}"
    export PATH="$HOME/Library/Android/sdk/platform-tools:$PATH"
fi

if ! command -v adb >/dev/null 2>&1; then
    adb_env_fail
fi

sidescreen_select_adb_device() {
    if [ -n "${ANDROID_SERIAL:-}" ]; then
        if adb -s "$ANDROID_SERIAL" get-state 2>/dev/null | grep -q "^device$"; then
            export ANDROID_SERIAL
            return 0
        fi

        echo "❌ Android device $ANDROID_SERIAL is not authorized or not connected"
        adb devices -l | sed 's/^/   /'
        return 1
    fi

    local devices
    local count
    devices="$(adb devices -l | awk 'NR > 1 && $2 == "device" {print $1}')"
    count="$(printf "%s\n" "$devices" | sed '/^$/d' | wc -l | tr -d ' ')"

    if [ "$count" -eq 0 ]; then
        echo "❌ No authorized Android device found via ADB"
        adb devices -l | sed 's/^/   /'
        return 1
    fi

    if [ "$count" -gt 1 ]; then
        echo "❌ Multiple Android devices connected; set ANDROID_SERIAL"
        adb devices -l | sed 's/^/   /'
        return 1
    fi

    ANDROID_SERIAL="$(printf "%s\n" "$devices" | sed '/^$/d' | head -1)"
    export ANDROID_SERIAL
}
