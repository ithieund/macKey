#!/bin/bash
#
# Build the app and screenshot all four windows, without needing the Accessibility grant.
#
#   ./scripts/preview-ui.sh                     # Vietnamese, current appearance
#   ./scripts/preview-ui.sh --lang en           # English strings
#   ./scripts/preview-ui.sh --out /tmp/shots    # somewhere other than /tmp/ohmykey-ui
#   ./scripts/preview-ui.sh -- -SettingsSelectedTab system   # extra launch args (defaults)
#
# A Debug build launched with OMK_UI_ONLY draws its windows and installs no event tap,
# so it can run alongside the copy you actually type with and never asks for permission.
# See UIPreviewHarness.swift for why the screenshots go through screencapture rather than
# being rendered in-process.

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$HERE")"
OUT="/tmp/ohmykey-ui"
LANG_ARGS=()
EXTRA_ARGS=()
SUFFIX=""

while [ $# -gt 0 ]; do
    case "$1" in
        --lang) LANG_ARGS=(-AppleLanguages "($2)"); SUFFIX="-$2"; shift 2 ;;
        --out) OUT="$2"; shift 2 ;;
        --) shift; EXTRA_ARGS=("$@"); break ;;
        *) echo "unknown option: $1" >&2; exit 2 ;;
    esac
done

if [ -z "${DEVELOPER_DIR:-}" ] && [ -d /Applications/Xcode.app ]; then
    export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi

BUILD_DIR="${OMK_DERIVED_DATA:-/tmp/omk-preview-dd}"
echo "==> Building Debug"
xcodebuild -project "$PROJECT_DIR/OhMyKey.xcodeproj" -scheme OhMyKey -configuration Debug \
    -derivedDataPath "$BUILD_DIR" CODE_SIGNING_ALLOWED=NO build \
    | grep -E '^(\*\*|.*error:)' || true

APP="$BUILD_DIR/Build/Products/Debug/OhMyKey.app"
[ -d "$APP" ] || { echo "build produced no app" >&2; exit 1; }

mkdir -p "$OUT"
LOG="$(mktemp)"
trap 'rm -f "$LOG"' EXIT

echo "==> Launching UI-only"
# ${arr[@]+...}: macOS ships bash 3.2, where "${empty[@]}" under `set -u` is an
# unbound-variable error - which would kill the background subshell and fire its
# inherited EXIT trap, deleting the log this script is about to read.
OMK_UI_ONLY=1 OMK_UI_HOLD=25 "$APP/Contents/MacOS/OhMyKey" ${EXTRA_ARGS[@]+"${EXTRA_ARGS[@]}"} \
    ${LANG_ARGS[@]+"${LANG_ARGS[@]}"} > "$LOG" 2>&1 &
APP_PID=$!
trap 'kill "$APP_PID" 2>/dev/null || true; rm -f "$LOG"' EXIT

for _ in $(seq 1 50); do
    grep -q OMK_WINDOWS_READY "$LOG" && break
    sleep 0.2
done

if ! grep -q OMK_WINDOWS_READY "$LOG"; then
    echo "windows never reported themselves:" >&2
    cat "$LOG" >&2
    exit 1
fi

while read -r _ kind window_id; do
    screencapture -o -x -l"$window_id" "$OUT/$kind$SUFFIX.png"
    echo "    $OUT/$kind$SUFFIX.png"
done < <(grep '^OMK_WINDOW ' "$LOG")

kill "$APP_PID" 2>/dev/null || true
echo "==> Done"
