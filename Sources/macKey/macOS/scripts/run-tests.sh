#!/bin/bash
#
# Run the unit tests.
#
#   ./scripts/run-tests.sh
#
# The project has no XCTest target, and adding one means hand-editing a pbxproj that has
# no Xcode to validate it. These two units need neither AppKit nor a running app, so they
# are compiled straight from source and run as ordinary executables.

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MACOS_DIR="$(dirname "$HERE")"
ENGINE_DIR="$(dirname "$MACOS_DIR")/engine"
BUILD_DIR="$(mktemp -d)"
trap 'rm -rf "$BUILD_DIR"' EXIT

if [ -z "${DEVELOPER_DIR:-}" ] && [ -d /Applications/Xcode.app ]; then
    export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi

status=0

echo "==> Hotkey"
xcrun swiftc -O -swift-version 5 \
    "$MACOS_DIR/MacKey/UI/Hotkey.swift" \
    "$MACOS_DIR/tests/HotkeyTests.swift" \
    -o "$BUILD_DIR/hotkey-tests"
"$BUILD_DIR/hotkey-tests" || status=1

echo
echo "==> Macro store"
xcrun clang++ -std=gnu++14 -stdlib=libc++ -I "$ENGINE_DIR" \
    "$ENGINE_DIR/Macro.cpp" "$ENGINE_DIR/Vietnamese.cpp" "$ENGINE_DIR/Engine.cpp" \
    "$MACOS_DIR/tests/EngineSettings.cpp" "$MACOS_DIR/tests/MacroStoreTests.cpp" \
    -o "$BUILD_DIR/macro-tests"
"$BUILD_DIR/macro-tests" || status=1

echo
if [ "$status" -eq 0 ]; then
    echo "All tests passed"
else
    echo "Tests failed"
fi
exit "$status"
