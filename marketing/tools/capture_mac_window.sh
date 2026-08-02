#!/usr/bin/env bash
#
# capture_mac_window.sh — screenshot ONE macOS app window, safely, with other apps running.
#
#   ./capture_mac_window.sh "/path/to/My App.app" out.png [KEY=VAL ...]
#
# The problem this solves: `screencapture` grabs a screen region, so it photographs whatever is
# in front — a notification, another app, or a second copy of this same app that another agent
# launched a second earlier. There is no way to ask it for "my window".
#
# The sequence that makes it deterministic:
#   1. Launch the executable INSIDE the bundle directly, not `open`. `open` hands off to
#      LaunchServices, which may activate an EXISTING instance and return you nothing useful;
#      running the binary gives us $! — the exact pid, and allows several copies at once.
#   2. Poll until THAT pid owns an on-screen window (a fixed sleep either flakes on a slow
#      launch or wastes seconds on a fast one).
#   3. Capture by pid via ScreenCaptureKit, which composites that window alone even if occluded.
#   4. Kill that pid only — never `killall AppName`, which would take out a sibling agent's copy.
#
# Extra KEY=VAL arguments are exported into the app's environment, for demo/state flags.
# Set LAUNCH_ARGS to pass argv through to the app — notably -AppleLanguages "(de)" -AppleLocale de,
# which NSUserDefaults reads as a defaults override, so one binary can be shot in any language.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
BIN="$HERE/capturewindow"
[ -x "$BIN" ] || { echo "building capturewindow…" >&2; swiftc -O "$HERE/CaptureWindow.swift" -o "$BIN"; }

APP="${1:?usage: capture_mac_window.sh <App.app> <out.png> [KEY=VAL ...]}"
OUT="${2:?missing output path}"
shift 2

EXEC_NAME="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$APP/Contents/Info.plist")"
EXEC="$APP/Contents/MacOS/$EXEC_NAME"
[ -x "$EXEC" ] || { echo "no executable at $EXEC" >&2; exit 1; }

# Export any KEY=VAL pairs for this launch only.
for kv in "$@"; do export "${kv?}"; done

# shellcheck disable=SC2086 — LAUNCH_ARGS is deliberately word-split into argv.
"$EXEC" ${LAUNCH_ARGS:-} >/dev/null 2>&1 &
PID=$!
# Kill our own instance on any exit path, so a failed capture never leaves a stray app running.
trap 'kill "$PID" 2>/dev/null || true' EXIT

for _ in $(seq 1 60); do
  if "$BIN" --list 2>/dev/null | grep -q "\"pid\":$PID,"; then break; fi
  sleep 0.5
done

sleep "${SETTLE:-3}"          # let first paint and any live fetch land
"$BIN" --pid "$PID" --out "$OUT" --largest
echo "✅ $OUT"
