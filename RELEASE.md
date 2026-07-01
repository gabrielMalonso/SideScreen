# Release and Installation Guide

Side Screen has two build profiles. Dev builds are allowed to be convenient. Distribution builds are not.

| Check | Dev profile | Distribution profile |
| --- | --- | --- |
| Android release signing | May fall back to debug key | Must use `SIDESCREEN_RELEASE_*` |
| macOS signing | Developer ID, Apple Development, or ad-hoc | Must use Developer ID Application |
| macOS notarization | Warning if missing | Blocker if missing |
| Gatekeeper | Warning if rejected | Blocker if rejected |
| Secrets in Git | Never | Still never |

## Dev Checks

```bash
./scripts/preflight.sh --full
./scripts/build_mac.sh
./scripts/build_android.sh
```

Warnings here mean "fine for local testing, bad for shipping." Treat debug-signed Android release artifacts and unnotarized DMGs as local-only.

## Distribution Checks

Set signing and notarization values through environment variables or CI secrets. Do not commit keystores, `.jks`, `.p12`, `.pem`, passwords, or app-specific Apple passwords.

```bash
export SIDESCREEN_CODESIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)"
export SIDESCREEN_NOTARIZE=1
export APPLE_ID="you@example.com"
export APPLE_TEAM_ID="TEAMID"
export APPLE_APP_SPECIFIC_PASSWORD="xxxx-xxxx-xxxx-xxxx"

export SIDESCREEN_RELEASE_STORE_FILE="$HOME/secure/sidescreen-release.jks"
export SIDESCREEN_RELEASE_STORE_PASSWORD="..."
export SIDESCREEN_RELEASE_KEY_ALIAS="sidescreen"
export SIDESCREEN_RELEASE_KEY_PASSWORD="..."
```

Then run:

```bash
./scripts/build_mac.sh --release
./scripts/build_android.sh --release
./scripts/preflight.sh --full --release
./scripts/release.sh
```

`./scripts/release.sh` uses the distribution profile. If it fails on signing, notarization, Gatekeeper, or Android release signing, the release is blocked. That is the correct outcome.

## macOS Permissions

After installing a newly signed Mac app, open it once and grant the requested permissions:

| Permission | Why it exists |
| --- | --- |
| Screen Recording | Captures the virtual display for streaming |
| Local Network | Lets Android reach the Mac over LAN |
| Accessibility | Enables CGEvent touch, mouse, and keyboard fallback |
| Input Monitoring | May be required by macOS for reliable input paths |
| Virtual HID approval | Enables the privileged helper or Karabiner VirtualHID path |

TCC permissions are tied to the app identity. Changing from ad-hoc to Apple Development or Developer ID can require granting permissions once again. Rebuilding with the same stable identity should not keep resetting them.

## Android Install Notes

Use the APK for direct installation and the AAB for store-style publication. A debug-signed `app-release.apk` is useful for local smoke tests only. If the tablet already has a build signed by a different key, uninstall the old app before installing the real release.

For USB mode:

```bash
./scripts/setup-usb.sh
adb install -r AndroidClient/app/build/outputs/apk/release/app-release.apk
```

For Tailnet mode, keep Tailscale connected on both devices and pair again if the Mac token was reset.
