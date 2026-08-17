#!/bin/zsh
# Film the scripted demo. One take, no framing, no focus stolen.
#
# It calls `marketing/reels/recordwindow` IN PLACE — nothing is forked out of the shared toolchain
# (CLAUDE.md), and this file only knows the things that are specific to this app: its process name,
# its demo env vars, and how long the scenario runs.
#
# Requires Screen Recording permission for the terminal this runs from, or ScreenCaptureKit silently
# records black. The emptiness check at the end is the practical test for that.
#
#   ./pig/marketing/reels/capture_mac_demo.sh [seconds]
set -e

ROOT=${0:a:h:h:h:h}                      # …/rootyapps
APP_DIR=$ROOT/pig
SECS=${1:-45}                            # Scenario.duration is 42.5 s; a little tail is free
REC=$ROOT/marketing/reels/recordwindow

# 960×540 is not arbitrary: RecordWindow captures at scale 2, so the file lands at exactly
# 1920×1080 — the macOS store-preview size — with no rescale and no resampling.
SIZE=960x540

[ -x "$REC" ] || ( cd $ROOT/marketing/reels && swiftc -O RecordWindow.swift -o recordwindow )

APP=$(xcodebuild -project $APP_DIR/pig.xcodeproj -scheme pig -destination 'platform=macOS' \
      -configuration Release -showBuildSettings 2>/dev/null \
      | awk -F' = ' '/ BUILT_PRODUCTS_DIR/{print $2}' | head -1)/Pig.app
[ -d "$APP" ] || { echo "❌ no Release build at $APP — build it first"; exit 1 }

RAW=$APP_DIR/marketing/raw/mac/video
OUT=$APP_DIR/marketing/aso/mac/video
mkdir -p $RAW $OUT

# A single-instance SwiftUI app ignores new env unless the old process is really gone.
pkill -9 -f "MacOS/Pig" 2>/dev/null || true
while pgrep -f "MacOS/Pig" >/dev/null; do sleep 0.3; done

# `-g` is the whole point: a capture run is several relaunches and none of them may take the
# foreground off whatever the user is doing.
open -n -g "$APP" --env PIG_DEMO=1 --env PIG_DEMO_SIZE=$SIZE
sleep 3.0                                # let the window settle and the scenario start

PID=$(pgrep -f "MacOS/Pig" | head -1)
[ -n "$PID" ] || { echo "❌ the app did not start"; exit 1 }

echo "▶︎ recording ${SECS}s from pid $PID"
"$REC" --pid "$PID" "$SECS" "$RAW/capture.mov"
pkill -9 -f "MacOS/Pig" 2>/dev/null || true

[ -s "$RAW/capture.mov" ] || { echo "❌ EMPTY capture (Screen Recording permission?)"; exit 1 }

# Conform to the delivery mp4. Same filter and encode shape as marketing/reels/mac_store_rec.sh.
ffmpeg -y -loglevel error -i "$RAW/capture.mov" \
  -vf "fps=30,format=yuv420p" \
  -c:v libx264 -profile:v high -crf 20 -preset medium -pix_fmt yuv420p -an \
  "$OUT/pig_demo_1920x1080.mp4"

echo "✅ $OUT/pig_demo_1920x1080.mp4"
ffprobe -v error -show_entries stream=width,height,r_frame_rate,duration \
        -of default=noprint_wrappers=1 "$OUT/pig_demo_1920x1080.mp4"
