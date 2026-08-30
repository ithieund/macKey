#!/bin/bash
#
# Build OhMyKey and install it into /Applications so you can actually run it.
#
#   ./scripts/build-and-install.sh            # Release (what you want to use)
#   ./scripts/build-and-install.sh Debug      # Debug
#
# Why a script rather than just "open it in Xcode and hit Run": running the app
# needs the Accessibility permission, which macOS ties to the app's code signature
# AND its location. Xcode's Run builds into a DerivedData path that changes, so the
# permission has to be re-granted constantly. Building to a fixed /Applications path
# keeps it stable between builds - though see the note at the end, an ad-hoc
# signature still changes on every rebuild.

set -euo pipefail

CONFIG="${1:-Release}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$HERE")"
BUILD_DIR="$(mktemp -d)"
APP="/Applications/OhMyKey.app"

# xcodebuild needs the full Xcode, not the Command Line Tools. Respect an existing
# DEVELOPER_DIR, otherwise point at Xcode ourselves so this works even when
# `xcode-select -p` still says CommandLineTools.
if [ -z "${DEVELOPER_DIR:-}" ] && [ -d /Applications/Xcode.app ]; then
    export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi

trap 'rm -rf "$BUILD_DIR"' EXIT

echo "==> Building $CONFIG"
xcodebuild \
    -project "$PROJECT_DIR/OhMyKey.xcodeproj" \
    -scheme OhMyKey \
    -configuration "$CONFIG" \
    -derivedDataPath "$BUILD_DIR" \
    CODE_SIGN_IDENTITY=- \
    CODE_SIGNING_REQUIRED=NO \
    build \
    | grep -E '^(\*\*|.*(error|warning):)' || true

BUILT="$BUILD_DIR/Build/Products/$CONFIG/OhMyKey.app"
if [ ! -d "$BUILT" ]; then
    echo "Build failed: $BUILT was not produced" >&2
    exit 1
fi

# The running copy holds its bundle open; replacing it underneath is what leaves you
# with a half-updated app that still shows the old icon.
if pgrep -f "$APP/Contents/MacOS/OhMyKey" > /dev/null; then
    echo "==> Quitting the running copy"
    osascript -e 'tell application "OhMyKey" to quit' 2>/dev/null || true
    sleep 1
    pkill -f "$APP/Contents/MacOS/OhMyKey" 2>/dev/null || true
fi

echo "==> Installing to $APP"
rm -rf "$APP"
cp -R "$BUILT" "$APP"
# Locally built, so not quarantined - but harmless to be sure Gatekeeper stays quiet.
xattr -dr com.apple.quarantine "$APP" 2>/dev/null || true

echo "==> Done: $(defaults read "$APP/Contents/Info.plist" CFBundleShortVersionString) ($CONFIG)"
echo
echo "Run it with:  open -a OhMyKey"
echo
echo "If it quits immediately it needs Accessibility permission again. An ad-hoc"
echo "signature is derived from the binary, so every rebuild produces a new identity"
echo "and macOS stops recognising the old grant. To re-grant cleanly:"
echo "    tccutil reset Accessibility com.hungdoansy.ohmykey"
echo "    open -a OhMyKey        # click 'Cấp quyền', then enable OhMyKey in the list"
echo "Signing with a real Developer ID certificate instead would make the grant stick."
