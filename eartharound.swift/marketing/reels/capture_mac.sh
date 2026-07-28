#!/usr/bin/env bash
#
# capture_mac.sh — Mac App Store preview reel for Earth Around.
#
#   ./reels/capture_mac.sh          # English → aso/en/mac/video/
#   ./reels/capture_mac.sh de
#
# Same tour as the iPhone reel (DemoDriver walks six beats and emits REEL_T0 / REEL_SCENE /
# REEL_END), composed onto the 1920x1080 canvas the Mac slot requires.
#
# Two things differ from the simulator flow, both in our favour:
#   • We launch the binary ourselves, so the REEL_ markers arrive on the process's own stdout —
#     no `log stream` predicate scraping, and no chance of reading another process's markers.
#   • Recording is by PID through ScreenCaptureKit (recordwindow --pid), so the reel contains
#     that window's own composited content. `screencapture`/avfoundation record a display, which
#     on a working Mac means notifications, other apps, or a second copy of this app launched by
#     another agent all end up in the footage.
set -euo pipefail

ROOT="/Users/oleksandr/Projects/rootyapps"
APP_DIR="$ROOT/eartharound.swift"
PROJECT="$APP_DIR/eartharound.swift.xcodeproj"
PYBIN="${PYBIN:-/Users/oleksandr/miniconda3/envs/fantastic/bin/python}"
FRAME_PY="$ROOT/marketing/reels/frame_reel.py"
ALIGN_PY="$ROOT/marketing/reels/align_scenes.py"
RECORDER="$ROOT/marketing/reels/recordwindow"

LOC="${1:-en}"
_SCENES="$APP_DIR/marketing/reels/scenes_mac.json"
[ "$LOC" = en ] || _SCENES="$APP_DIR/marketing/reels/scenes_mac_$LOC.json"
SCENES="${SCENES:-$_SCENES}"

RAW_DIR="$APP_DIR/marketing/raw/$LOC/mac/video"
ASO_DIR="$APP_DIR/marketing/aso/$LOC/mac/video"
DERIVED="$APP_DIR/.build/mac-reel-dd"
RAW_MOV="$RAW_DIR/capture.mov"
mkdir -p "$RAW_DIR" "$ASO_DIR" "$DERIVED"

CANVAS_W=$("$PYBIN" -c "import json,sys;print(json.load(open(sys.argv[1]))['canvas'][0])" "$SCENES")
CANVAS_H=$("$PYBIN" -c "import json,sys;print(json.load(open(sys.argv[1]))['canvas'][1])" "$SCENES")
CONTENT_LEN=$("$PYBIN" -c "import json,sys;print(json.load(open(sys.argv[1]))['content_len'])" "$SCENES")

[ -x "$RECORDER" ] || { echo "building recordwindow…"; swiftc -O "$ROOT/marketing/reels/RecordWindow.swift" -o "$RECORDER"; }

echo "▶ build (macOS)"
xcodebuild build -project "$PROJECT" -scheme eartharound.swift \
  -destination 'platform=macOS' -configuration Debug -derivedDataPath "$DERIVED" \
  -allowProvisioningUpdates -quiet
APP=$(find "$DERIVED/Build/Products" -maxdepth 2 -name "*.app" | head -1)
[ -n "$APP" ] || { echo "❌ no built .app"; exit 1; }
EXEC="$APP/Contents/MacOS/$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$APP/Contents/Info.plist")"

MARKERS="$DERIVED/reel-markers-$LOC.log"; rm -f "$MARKERS" "$RAW_MOV"

echo "▶ launching tour ($LOC)"
EARTHAROUND_DEMO=1 EARTHAROUND_MODE=extended \
  "$EXEC" -AppleLanguages "($LOC)" -AppleLocale "$LOC" > "$MARKERS" 2>&1 &
PID=$!
trap 'kill "$PID" 2>/dev/null || true' EXIT

# Wait for the window to exist before recording, rather than sleeping a guessed amount.
for _ in $(seq 1 60); do
  "$RECORDER" --pid "$PID" 0.01 /dev/null >/dev/null 2>&1 && break
  grep -q "REEL_T0" "$MARKERS" 2>/dev/null && break
  sleep 0.5
done

REC_LEN=$(echo "$CONTENT_LEN + 12" | bc -l)     # tour + settle + drain
echo "▶ recording ${REC_LEN}s of window (pid $PID)"
RSTART=$(date +%s.%N)
"$RECORDER" --pid "$PID" "$REC_LEN" "$RAW_MOV"

kill "$PID" 2>/dev/null || true
[ -s "$RAW_MOV" ] || { echo "❌ no capture produced"; exit 1; }

# ── Align captions to the tour's own markers ────────────────────────────────
SCENES_RUNTIME="$SCENES"
if grep -q "REEL_T0" "$MARKERS" && grep -q "REEL_END" "$MARKERS"; then
  if "$PYBIN" "$ALIGN_PY" "$SCENES" "$MARKERS" "$DERIVED/scenes_mac_$LOC.runtime.json"; then
    SCENES_RUNTIME="$DERIVED/scenes_mac_$LOC.runtime.json"
    echo "▶ marker-aligned"
  fi
else
  echo "⚠ no REEL markers — using the scene file's nominal timing"
fi

T0=$(grep -oE 'REEL_T0 [0-9.]+' "$MARKERS" | tail -1 | awk '{print $2}')
HEAD_TRIM=0
[ -n "${T0:-}" ] && HEAD_TRIM=$(printf "%.3f" "$(echo "if ($T0 - $RSTART > 0) $T0 - $RSTART else 0" | bc -l)")

FULL="$ASO_DIR/full.mp4"
ffmpeg -y -v error -ss "$HEAD_TRIM" -i "$RAW_MOV" -an \
  -vf "fps=30" -c:v libx264 -pix_fmt yuv420p -crf 18 "$FULL"

echo "▶ framing onto ${CANVAS_W}x${CANVAS_H}"
"$PYBIN" "$FRAME_PY" --scenes "$SCENES_RUNTIME" --video "$FULL" \
  --app-dir "$APP_DIR" --out-dir "$ASO_DIR"

echo
echo "✅ mac reel ($LOC) in $ASO_DIR"
echo "   score it:  V=$ASO_DIR/framed_preview_${CANVAS_W}x${CANVAS_H}.mp4 reels/score_ios.sh $LOC"
