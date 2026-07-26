#!/usr/bin/env bash
#
# capture_ios.sh — App Store preview reel for eartharound (Space Weather).
#
# Unlike the shared marketing/reels/make_reel.sh (xcodegen + a ReelTour XCUITest), this app
# drives its own tour from inside the process: launching with EARTHAROUND_DEMO=1 makes
# DemoDriver walk the six beats and emit REEL_T0 / REEL_SCENE / REEL_END epoch markers. So
# there's no test target to build — just launch, record, and align.
#
#   1. build + install on the 6.9" sim, clean the marketing status bar
#   2. launch with EARTHAROUND_DEMO=1 and record with `simctl io recordVideo`
#   3. align captions to the tour's markers (align_scenes.py)
#   4. ffmpeg conform -> full.mp4 + preview_886x1920.mp4
#   5. frame_reel.py  -> framed_full.mp4 + framed_preview_886x1920.mp4
#
# The bed is muxed separately (see score_ios.sh) so audio can be re-picked without re-capturing.
set -euo pipefail

ROOT="/Users/oleksandr/Projects/rootyapps"
APP_DIR="$ROOT/eartharound.swift"
PROJECT="$APP_DIR/eartharound.swift.xcodeproj"
SCHEME="eartharound.swift"
APP_BUNDLE="${APP_BUNDLE:-oleksandr.aisixteen.eartharound}"
SIM_NAME="${SIM_NAME:-Calc-iPhone17ProMax}"
SCENES="${SCENES:-$APP_DIR/marketing/reels/scenes.json}"
PYBIN="${PYBIN:-/Users/oleksandr/miniconda3/envs/fantastic/bin/python}"
FRAME_PY="$ROOT/marketing/reels/frame_reel.py"
ALIGN_PY="$ROOT/marketing/reels/align_scenes.py"

RAW_DIR="$APP_DIR/marketing/raw/ios/video"
ASO_DIR="$APP_DIR/marketing/aso/ios/video"
DERIVED="$APP_DIR/.build/reel-dd"
RAW_MOV="$RAW_DIR/capture.mov"

CANVAS_W=$("$PYBIN" -c "import json,sys;print(json.load(open(sys.argv[1]))['canvas'][0])" "$SCENES")
CANVAS_H=$("$PYBIN" -c "import json,sys;print(json.load(open(sys.argv[1]))['canvas'][1])" "$SCENES")
CONTENT_LEN=$("$PYBIN" -c "import json,sys;print(json.load(open(sys.argv[1]))['content_len'])" "$SCENES")
PREVIEW_MAXLEN=$("$PYBIN" -c "import json,sys;print(json.load(open(sys.argv[1]))['preview_maxlen'])" "$SCENES")
OUTRO_DUR=$("$PYBIN" -c "import json,sys;print(json.load(open(sys.argv[1]))['outro_dur'])" "$SCENES")

FULL="$ASO_DIR/full.mp4"
PREVIEW="$ASO_DIR/preview_${CANVAS_W}x${CANVAS_H}.mp4"
CONFORM="scale=${CANVAS_W}:${CANVAS_H}:force_original_aspect_ratio=decrease,pad=${CANVAS_W}:${CANVAS_H}:(ow-iw)/2:(oh-ih)/2:color=black,fps=30,format=yuv420p"
ENC=(-c:v libx264 -profile:v high -crf 20 -preset medium -movflags +faststart -an)
REC_LATENCY="${REC_LATENCY:-0.5}"
HEAD_TRIM="${HEAD_TRIM:-2.5}"

mkdir -p "$RAW_DIR" "$ASO_DIR" "$DERIVED"

UDID=$(xcrun simctl list devices | grep "$SIM_NAME (" | grep -oE "[0-9A-Fa-f-]{36}" | head -1)
[ -n "$UDID" ] || { echo "❌ simulator '$SIM_NAME' not found"; exit 1; }
echo "▶ simulator $SIM_NAME = $UDID"
xcrun simctl boot "$UDID" 2>/dev/null || true
xcrun simctl bootstatus "$UDID" -b

echo "▶ build"
xcodebuild build -project "$PROJECT" -scheme "$SCHEME" \
  -destination "id=$UDID" -derivedDataPath "$DERIVED" -quiet

BUILT_APP=$(find "$DERIVED/Build/Products" -maxdepth 2 -name "*.app" -path "*iphonesimulator*" | head -1)
[ -n "$BUILT_APP" ] || { echo "❌ no built .app"; exit 1; }
xcrun simctl install "$UDID" "$BUILT_APP" >/dev/null
xcrun simctl terminate "$UDID" "$APP_BUNDLE" 2>/dev/null || true

# Marketing status bar: 9:41, full bars, no carrier.
xcrun simctl status_bar "$UDID" override \
  --time "9:41" --operatorName " " --batteryState charged --batteryLevel 100 \
  --cellularBars 4 --wifiBars 3 --dataNetwork wifi 2>/dev/null || true
xcrun simctl launch "$UDID" com.apple.springboard >/dev/null 2>&1 || true
sleep 1

SYSLOG="$DERIVED/reel-syslog.log"
rm -f "$RAW_MOV" "$SYSLOG"
xcrun simctl spawn "$UDID" log stream --style compact \
  --predicate 'eventMessage CONTAINS "REEL_"' > "$SYSLOG" 2>/dev/null &
LOG_PID=$!

echo "▶ recording"
RSTART=$(date +%s.%N)
xcrun simctl io "$UDID" recordVideo --codec h264 --force "$RAW_MOV" &
REC_PID=$!
sleep 1

echo "▶ tour (DemoDriver, ~${CONTENT_LEN}s)"
# MODE=extended belt-and-braces: the tour pins it too, but the beats scroll to Wind/Flare/Hpo
# panels that only exist in Extended, so a Simple carry-over would record a broken reel.
SIMCTL_CHILD_EARTHAROUND_DEMO=1 SIMCTL_CHILD_EARTHAROUND_MODE=extended \
  xcrun simctl launch "$UDID" "$APP_BUNDLE" >/dev/null
# Wait for the tour to actually finish (REEL_END), not for a guessed duration: under GPU
# load the sim's encoder lags wall-clock, and `recordVideo` drops its trailing buffer on
# SIGINT — so a tight sleep truncates the last beat. Poll the marker, then let the encoder
# drain before stopping.
for _ in $(seq 1 "$(echo "($CONTENT_LEN + 25) / 1" | bc)"); do
  grep -q "REEL_END" "$SYSLOG" 2>/dev/null && break
  sleep 1
done
grep -q "REEL_END" "$SYSLOG" 2>/dev/null || echo "⚠ tour never reached REEL_END"
sleep "${DRAIN:-6}"                         # let recordVideo flush the tail

kill -INT "$REC_PID" 2>/dev/null || true
wait "$REC_PID" 2>/dev/null || true
kill "$LOG_PID" 2>/dev/null || true
xcrun simctl status_bar "$UDID" clear 2>/dev/null || true
[ -s "$RAW_MOV" ] || { echo "❌ no capture produced"; exit 1; }

# ── Align to the tour's markers ─────────────────────────────────────────────
T0=$(grep -oE 'REEL_T0 [0-9.]+'  "$SYSLOG" | tail -1 | awk '{print $2}')
TEND=$(grep -oE 'REEL_END [0-9.]+' "$SYSLOG" | tail -1 | awk '{print $2}')
SCENES_RUNTIME="$SCENES"
if [ -n "${T0:-}" ] && [ -n "${TEND:-}" ]; then
  HEAD_TRIM=$(echo "$T0 - $RSTART - $REC_LATENCY" | bc -l)
  CONTENT_LEN=$(echo "$TEND - $T0" | bc -l)
  echo "▶ marker-aligned: head ${HEAD_TRIM}s, content ${CONTENT_LEN}s"
  if "$PYBIN" "$ALIGN_PY" "$SCENES" "$SYSLOG" "$DERIVED/scenes.runtime.json"; then
    SCENES_RUNTIME="$DERIVED/scenes.runtime.json"
  fi
else
  echo "⚠ no REEL markers — falling back to head ${HEAD_TRIM}s / content ${CONTENT_LEN}s"
fi

# ── Fit the wall-clock timeline to the footage that actually exists ─────────
#
# Under animation load the simulator's H.264 encoder can't keep up and drops frames, so the
# recording holds LESS video time than the wall-clock time the tour took (~25s of video for
# ~34s of tour+drain is normal here). The REEL markers are wall-clock, so using them raw
# runs past the end of the file and silently cuts the last beat.
#
# The drop is uniform, so rescale: squeeze the marker timeline onto the captured duration.
# The tour then plays back slightly fast (a speed-fit preview does this anyway), and every
# caption still lands on its own footage.
RAW_LEN=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$RAW_MOV")
AVAIL=$(echo "$RAW_LEN - $HEAD_TRIM - 0.1" | bc -l)
if [ "$(echo "$AVAIL < 5" | bc -l)" -eq 1 ]; then
  echo "❌ capture unusable: only ${AVAIL}s after the head trim"; exit 1
fi
if [ "$(echo "$AVAIL < $CONTENT_LEN" | bc -l)" -eq 1 ]; then
  TIME_SCALE=$(echo "$AVAIL / $CONTENT_LEN" | bc -l)
  echo "▶ encoder dropped frames: ${CONTENT_LEN}s of tour -> ${AVAIL}s of video (x$(printf '%.3f' "$TIME_SCALE")); rescaling captions"
  "$PYBIN" - "$SCENES_RUNTIME" "$TIME_SCALE" "$DERIVED/scenes.fitted.json" <<'PY'
import json, sys
cfg, k, out = json.load(open(sys.argv[1])), float(sys.argv[2]), sys.argv[3]
for s in cfg["scenes"]:
    s["start"], s["end"] = round(s["start"] * k, 3), round(s["end"] * k, 3)
cfg["content_len"] = round(cfg["content_len"] * k, 3)
json.dump(cfg, open(out, "w"), indent=2)
PY
  SCENES_RUNTIME="$DERIVED/scenes.fitted.json"
  CONTENT_LEN=$AVAIL
fi

echo "▶ conform"
ffmpeg -y -loglevel error -i "$RAW_MOV" -ss "$HEAD_TRIM" -t "$CONTENT_LEN" -vf "$CONFORM" "${ENC[@]}" "$FULL"
TARGET_MAIN=$(echo "$PREVIEW_MAXLEN - $OUTRO_DUR" | bc -l)
SPEED=$(echo "if ($CONTENT_LEN > $TARGET_MAIN) $CONTENT_LEN / $TARGET_MAIN else 1" | bc -l)
ffmpeg -y -loglevel error -i "$FULL" -vf "setpts=PTS/$SPEED,fps=30,format=yuv420p" "${ENC[@]}" "$PREVIEW"

echo "▶ framing (captions + outro)"
"$PYBIN" "$FRAME_PY" --scenes "$SCENES_RUNTIME" --video "$FULL" --app-dir "$APP_DIR" --out-dir "$ASO_DIR"

dur() { ffprobe -v error -show_entries format=duration -of csv=p=0 "$1"; }
echo
echo "✅ capture done"
echo "   full:            $FULL  $(dur "$FULL")s"
echo "   framed_full:     $ASO_DIR/framed_full.mp4  $(dur "$ASO_DIR/framed_full.mp4")s"
echo "   framed_preview:  $ASO_DIR/framed_preview_${CANVAS_W}x${CANVAS_H}.mp4  $(dur "$ASO_DIR/framed_preview_${CANVAS_W}x${CANVAS_H}.mp4")s"
echo "   → score it:      marketing/reels/score_ios.sh"
