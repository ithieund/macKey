#!/bin/bash
#
# Build the app and screenshot every window plus every control-panel pane, without needing
# the Accessibility grant.
#
#   ./scripts/preview-ui.sh                    # Vietnamese screenshots in docs/images
#   ./scripts/preview-ui.sh --lang en          # English strings
#   ./scripts/preview-ui.sh --out /tmp/shots   # choose a different output folder
#
# Settings screenshots are named after their actual panes: settings-typing, settings-system,
# settings-compatibility, and settings-advanced.
#
# A Debug build launched with MACKEY_UI_ONLY draws its windows and installs no event tap,
# so it can run alongside the copy you actually type with and never asks for permission.
# See UIPreviewHarness.swift for why the screenshots go through screencapture rather than
# being rendered in-process.

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$HERE")"
OUT="$PROJECT_DIR/../../../docs/images"
LANG_CODE="vi"
LANG_ARGS=()
EXTRA_ARGS=()
SUFFIX=""

while [ $# -gt 0 ]; do
    case "$1" in
        --lang)
            [ $# -ge 2 ] || { echo "--lang requires a language code" >&2; exit 2; }
            LANG_CODE="$2"
            shift 2
            ;;
        --out) OUT="$2"; shift 2 ;;
        --) shift; EXTRA_ARGS=("$@"); break ;;
        *) echo "unknown option: $1" >&2; exit 2 ;;
    esac
done

LANG_ARGS=(-AppleLanguages "($LANG_CODE)")
SUFFIX="-$LANG_CODE"

if [ -z "${DEVELOPER_DIR:-}" ] && [ -d /Applications/Xcode.app ]; then
    export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi

BUILD_DIR="${MACKEY_DERIVED_DATA:-/tmp/mackey-preview-dd}"
BUILD_LOG="$(mktemp)"
echo "==> Building Debug"
if ! xcodebuild -project "$PROJECT_DIR/MacKey.xcodeproj" -scheme MacKey -configuration Debug \
    -derivedDataPath "$BUILD_DIR" CODE_SIGNING_ALLOWED=NO build >"$BUILD_LOG" 2>&1; then
    cat "$BUILD_LOG" >&2
    rm -f "$BUILD_LOG"
    exit 1
fi
grep -E '^\*\* (BUILD|ARCHIVE)' "$BUILD_LOG" || true
rm -f "$BUILD_LOG"

APP="$BUILD_DIR/Build/Products/Debug/macKey.app"
[ -d "$APP" ] || { echo "build produced no app" >&2; exit 1; }

mkdir -p "$OUT"
LOG="$(mktemp)"
APP_PID=""
cleanup() {
    if [ -n "$APP_PID" ]; then kill "$APP_PID" 2>/dev/null || true; fi
    rm -f "$LOG"
}
trap cleanup EXIT

capture_tab() {
    local tab="$1"
    local capture_all_windows="$2"

    : > "$LOG"
    echo "==> Launching UI-only ($tab pane)"
    # macOS ships bash 3.2, where an empty array expansion under `set -u` is an error.
    # Launch the executable directly so the preview environment flags are available before
    # AppKit starts; run this from a logged-in macOS desktop session for window capture.
    MACKEY_UI_ONLY=1 MACKEY_UI_HOLD=25 "$APP/Contents/MacOS/macKey" \
        ${EXTRA_ARGS[@]+"${EXTRA_ARGS[@]}"} -SettingsSelectedTab "$tab" \
        ${LANG_ARGS[@]+"${LANG_ARGS[@]}"} > "$LOG" 2>&1 &
    APP_PID=$!

    for _ in $(seq 1 50); do
        grep -q MACKEY_WINDOWS_READY "$LOG" && break
        sleep 0.2
    done

    if ! grep -q MACKEY_WINDOWS_READY "$LOG"; then
        echo "windows never reported themselves for the $tab pane:" >&2
        cat "$LOG" >&2
        return 1
    fi

    while read -r _ kind window_id; do
        if [ "$kind" = "settings" ]; then
            local output="$OUT/settings-$tab$SUFFIX.png"
            screencapture -o -x -l"$window_id" "$output"
            echo "    $output"
        elif [ "$capture_all_windows" = "yes" ]; then
            local output="$OUT/$kind$SUFFIX.png"
            screencapture -o -x -l"$window_id" "$output"
            echo "    $output"
        fi
    done < <(grep '^MACKEY_WINDOW ' "$LOG")

    kill "$APP_PID" 2>/dev/null || true
    wait "$APP_PID" 2>/dev/null || true
    APP_PID=""
}

SETTINGS_TABS=(typing system compatibility advanced)
CAPTURE_ALL_WINDOWS="yes"
for tab in "${SETTINGS_TABS[@]}"; do
    capture_tab "$tab" "$CAPTURE_ALL_WINDOWS"
    CAPTURE_ALL_WINDOWS="no"
done

for tab in "${SETTINGS_TABS[@]}"; do
    screenshot="$OUT/settings-$tab$SUFFIX.png"
    [ -s "$screenshot" ] || { echo "missing settings screenshot: $screenshot" >&2; exit 1; }
done

open "$OUT"
echo "==> Done"
