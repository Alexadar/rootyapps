#!/usr/bin/env bash
#
# capture_mac_reel.sh [scenario] — Mac App Store preview reel for Tarot.
#
# Same filming scenario as the iPhone and iPad reels, so all three previews show the same draw,
# the same cards and the same reading, and a change to the take is a change to one YAML file.
#
# Recording is ScreenCaptureKit via `recordwindow --pid`, never `ffmpeg -f avfoundation`:
#   • avfoundation can only grab a whole display, so the terminal, the dock and any notification
#     land in the store preview;
#   • SCK's desktopIndependentWindow filter composites ONLY our window, even when occluded;
#   • addressing by PID rather than by window title or app name means a second copy of Tarot,
#     started by another session, cannot be recorded by mistake.
# The app therefore never needs to be frontmost, and this run does not steal the screen.
#
# Needs Screen Recording permission for the terminal, once.
set -uo pipefail

ROOT=/Users/oleksandr/Projects/rootyapps
APP_DIR="$ROOT/tarot"
SCENARIO="${1:-will-i-be-rich}"
LOC=en
RECORDER="$ROOT/marketing/reels/recordwindow"
DERIVED="$APP_DIR/.build/dd-mac"
APPBUNDLE="$DERIVED/Build/Products/Debug/Tarot.app"
CANVAS_W=1920; CANVAS_H=1080

RAW_DIR="$APP_DIR/marketing/raw/$LOC/mac/video/$SCENARIO"
ASO_DIR="$APP_DIR/marketing/aso/$LOC/mac/video/$SCENARIO"
mkdir -p "$RAW_DIR" "$ASO_DIR"
RAW_MOV="$RAW_DIR/capture.mov"

YAML="$APP_DIR/Tarot/Debug/Scenarios/$SCENARIO.scenario.yaml"
[ -f "$YAML" ] || { echo "❌ no scenario at $YAML" >&2; exit 1; }
if grep -qi "PLACEHOLDER\|Placeholder for the" "$YAML"; then
  echo "❌ $SCENARIO still holds placeholder passages — capture the real text first" >&2; exit 1
fi

[ -x "$RECORDER" ] || { echo "building recordwindow…"; swiftc -O "$ROOT/marketing/reels/RecordWindow.swift" -o "$RECORDER"; }

echo "▶ building the Mac app"
( cd "$APP_DIR" && xcodegen generate >/dev/null && \
  xcodebuild -project tarot.xcodeproj -scheme tarot -destination 'platform=macOS' \
    -derivedDataPath "$DERIVED" build >/dev/null 2>&1 ) || { echo "❌ build failed" >&2; exit 1; }
EXEC="$APPBUNDLE/Contents/MacOS/$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$APPBUNDLE/Contents/Info.plist")"
[ -x "$EXEC" ] || { echo "❌ no executable at $EXEC" >&2; exit 1; }

# The take is ~41.6 s of content; record generously and trim, because the tail is the one thing a
# re-shoot cannot recover cheaply.
DURATION="${DURATION:-52}"

rm -f "$RAW_MOV"
echo "▶ recording ${DURATION}s"
# `open -n -g`: a new instance, in the BACKGROUND. Launching the executable directly makes the
# app activate and take the screen for the whole ~50 s recording, which is both rude and
# unnecessary — SCK records the window's own composited content, so it never needs to be
# frontmost (marketing/reels/README.md, "Run (macOS)"). The pid comes back as the process that
# appeared, by set difference, so another session's copy of Tarot cannot be recorded instead.
# `|| true` is load-bearing under `set -e -o pipefail`: pgrep exits 1 when nothing
# matches, which is the NORMAL case (no copy running), and pipefail then propagates
# that through the pipeline and kills the script before it ever launches anything.
BEFORE="$(pgrep -f "MacOS/Tarot" 2>/dev/null | sort -u || true)"
open -n -g -a "$APPBUNDLE" --args -TAROT_SCENARIO "$SCENARIO" -AppleLanguages "(en)"
PID=""
for _ in $(seq 1 80); do
  AFTER="$(pgrep -f "MacOS/Tarot" 2>/dev/null | sort -u || true)"
  PID="$(comm -13 <(printf '%s\n' "$BEFORE") <(printf '%s\n' "$AFTER") | head -1 || true)"
  [ -n "$PID" ] && break
  sleep 0.25
done
[ -n "$PID" ] || { echo "❌ the app never appeared as a new process" >&2; exit 1; }
trap 'kill "$PID" 2>/dev/null || true' EXIT
sleep 1.5
kill -0 "$PID" 2>/dev/null || { echo "❌ the app exited immediately" >&2; exit 1; }
"$RECORDER" --pid "$PID" "$DURATION" "$RAW_MOV" >/dev/null 2>&1
kill "$PID" 2>/dev/null || true
[ -s "$RAW_MOV" ] || { echo "❌ no capture produced" >&2; exit 1; }

# START from the picture, exactly as the simulator reel does and for the same reason: the app
# holds a launch curtain over the frames where RealityKit is still uploading textures, and the
# three phases separate cleanly by luminance — white window (~232), curtain (~25), table (~60).
# Take the third consecutive in-band sample so the cut begins after the dissolve, not inside it.
echo "▶ locating the loaded frame"
SCAN=$(ffmpeg -loglevel info -i "$RAW_MOV" -vf "fps=4,scale=16:16,signalstats,metadata=print" \
  -f null - 2>&1 | grep -oE "pts_time:[0-9.]+|YAVG=[0-9.]+" | paste - -)
HEAD_TRIM=$(printf '%s\n' "$SCAN" | awk -F'[:=\t]' '
  $4 >= 50 && $4 <= 120 { run++; if (run == 3) { print $2; exit } }
  $4 < 50 || $4 > 120   { run = 0 }')
[ -n "$HEAD_TRIM" ] || { echo "❌ could not find the loaded app in the capture" >&2; exit 1; }

# LENGTH comes from the scenario, not from a marker read back over a drifting clock: on the Mac
# the take is a single uninterrupted run, and its content length is a property of the YAML.
CONTENT_LEN=$(awk '
  /^timing:/      { t = 1 }
  /^writing:/     { t = 0 }
  t && /typeInterval:/ { ti = $2 }
  t && /pauseAfter:/   { pa = $2 }
  t && /settle:/       { se = $2 }
  t && /perCard:/      { pc = $2 }
  t && /hold:/         { ho = $2 }
  END { printf "%.2f", 15 * ti + pa + se + 3 * pc + 1.1 + ho }' "$YAML")
echo "▶ content ${CONTENT_LEN}s from HEAD ${HEAD_TRIM}s"

CONFORM="scale=${CANVAS_W}:${CANVAS_H}:force_original_aspect_ratio=decrease,pad=${CANVAS_W}:${CANVAS_H}:(ow-iw)/2:(oh-ih)/2:color=black,fps=30,format=yuv420p"
FULL="$ASO_DIR/full.mp4"
ffmpeg -y -loglevel error -i "$RAW_MOV" -ss "$HEAD_TRIM" -t "$CONTENT_LEN" -vf "$CONFORM" \
  -c:v libx264 -profile:v high -crf 20 -preset medium -movflags +faststart -an "$FULL"

GOT=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$FULL")
if [ "$(echo "$CONTENT_LEN - $GOT > 0.4" | bc -l)" = "1" ]; then
  echo "❌ cut is ${GOT}s but the content is ${CONTENT_LEN}s — raise DURATION and re-shoot" >&2
  exit 1
fi
OPEN_Y=$(ffmpeg -loglevel info -i "$FULL" -t 0.1 -vf "scale=16:16,signalstats,metadata=print" \
  -f null - 2>&1 | grep -oE "YAVG=[0-9.]+" | head -1 | cut -d= -f2)
if [ -n "$OPEN_Y" ] && [ "$(echo "$OPEN_Y > 100" | bc -l)" = "1" ]; then
  echo "❌ the cut opens on a bright frame (YAVG $OPEN_Y) — that is the launch window" >&2
  exit 1
fi

echo "▶ opening frame YAVG $OPEN_Y (the app, not the launch window)"
echo "✅ raw  $RAW_MOV"
echo "✅ full $FULL  (${GOT}s)"
