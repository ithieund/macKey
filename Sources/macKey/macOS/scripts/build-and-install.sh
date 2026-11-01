#!/bin/bash
#
# Build macKey and install it into /Applications so you can actually run it.
#
#   ./scripts/build-and-install.sh            # Release (what you want to use)
#   ./scripts/build-and-install.sh Debug      # Debug
#
# Why a script rather than just "open it in Xcode and hit Run": running the app
# needs the Accessibility permission, which macOS ties to the app's code signature
# AND its location. Xcode's Run builds into a DerivedData path that changes, so the
# permission has to be re-granted constantly. Building to a fixed /Applications path
# keeps it stable between builds, provided the app is signed with the same identity.
# Run create-local-signing-identity.sh once when developing without an Apple
# Developer certificate.

set -euo pipefail

CONFIG="${1:-Release}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$HERE")"
BUILD_DIR="$(mktemp -d)"
BUILD_LOG="$BUILD_DIR/build.log"
APP="/Applications/macKey.app"
LOCAL_IDENTITY="macKey Local Development"

# A developer may override this with an Apple Development or Developer ID identity.
# The local identity is intentionally stable, unlike an ad-hoc signature whose hash
# changes with every build and therefore loses its Accessibility permission.
SIGNING_IDENTITY="${MACKEY_CODE_SIGN_IDENTITY:-$LOCAL_IDENTITY}"

# xcodebuild needs the full Xcode, not the Command Line Tools. Respect an existing
# DEVELOPER_DIR, otherwise point at Xcode ourselves so this works even when
# `xcode-select -p` still says CommandLineTools.
if [ -z "${DEVELOPER_DIR:-}" ] && [ -d /Applications/Xcode.app ]; then
    export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi

trap 'rm -rf "$BUILD_DIR"' EXIT

echo "==> Building $CONFIG"
if ! xcodebuild \
    -project "$PROJECT_DIR/MacKey.xcodeproj" \
    -scheme MacKey \
    -configuration "$CONFIG" \
    -derivedDataPath "$BUILD_DIR" \
    CODE_SIGN_STYLE=Manual \
    CODE_SIGN_IDENTITY="$SIGNING_IDENTITY" \
    CODE_SIGNING_REQUIRED=YES \
    build >"$BUILD_LOG" 2>&1; then
    grep -E '^(\*\*|.*(error|warning):)' "$BUILD_LOG" || true
    tail -n 60 "$BUILD_LOG" >&2
    exit 1
fi
grep -E '^(\*\*|.*(error|warning):)' "$BUILD_LOG" || true

BUILT="$BUILD_DIR/Build/Products/$CONFIG/macKey.app"
if [ ! -d "$BUILT" ]; then
    echo "Build failed: $BUILT was not produced" >&2
    exit 1
fi

# The running copy holds its bundle open; replacing it underneath is what leaves you
# with a half-updated app that still shows the old icon.
if pgrep -f "$APP/Contents/MacOS/macKey" > /dev/null; then
    echo "==> Quitting the running copy"
    osascript -e 'tell application "macKey" to quit' 2>/dev/null || true
    sleep 1
    pkill -f "$APP/Contents/MacOS/macKey" 2>/dev/null || true
fi

echo "==> Installing to $APP"
rm -rf "$APP"
cp -R "$BUILT" "$APP"
# Locally built, so not quarantined - but harmless to be sure Gatekeeper stays quiet.
xattr -dr com.apple.quarantine "$APP" 2>/dev/null || true

echo "==> Launching macKey"
open -a "$APP"

echo "==> Done: $(defaults read "$APP/Contents/Info.plist" CFBundleShortVersionString) ($CONFIG)"
echo
echo "The same signing identity is used on every build, so Accessibility only needs"
echo "to be granted once. If you have not set up a signing identity yet, run:"
echo "    ./scripts/create-local-signing-identity.sh"
echo "then build again and grant Accessibility once to the newly signed macKey.app."
