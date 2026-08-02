#!/usr/bin/env bash
#
# make_reel.sh — capture an App Store app-preview reel from the iOS Simulator.
#
#   1. xcodegen + build-for-testing  (project.yml is the source of truth)
#   2. pre-launch the app, clean the status bar, start `simctl io recordVideo`
#   3. run the XCUITest "reel tour" that drives the app
#   4. stop recording  ->  raw .mov in marketing/raw/ios/video/
#   5. ffmpeg conform  ->  two cuts in marketing/aso/ios/video/:
#        full.mp4                — whole-app walkthrough, natural speed (internal acceptance)
#        preview_886x1920.mp4    — the SAME walkthrough speed-fit to <=28s, 886x1920 / H.264
#                                  / 30fps (App Store cut: shows every tab, under the 30s cap)
#
# Reference app = ephemeris.swift (already live -> tests whether a sim-captured reel passes
# App Store review). Replicate to other apps by overriding the APP_* / SIM / trim vars.
set -euo pipefail

# ── Config ──────────────────────────────────────────────────────────────────
ROOT="/Users/oleksandr/Projects/rootyapps"
APP_DIR="${APP_DIR:-$ROOT/ephemeris.swift}"
PROJECT="${PROJECT:-$APP_DIR/ephemeris.swift.xcodeproj}"
SCHEME="${SCHEME:-ephemerisReel}"
APP_BUNDLE="${APP_BUNDLE:-oleksandr.aisixteen.ephemeris}"
SIM_NAME="${SIM_NAME:-Calc-iPhone17ProMax}"     # 6.9" device
HEAD_TRIM="${HEAD_TRIM:-2.5}"                    # drop app activate/settle at the recording head
SCENES="${SCENES:-$APP_DIR/marketing/reels/scenes.json}"   # per-app timeline + captions + branding
FRAME_PY="${FRAME_PY:-$ROOT/marketing/reels/frame_reel.py}"
PYBIN="${PYBIN:-/Users/oleksandr/miniconda3/envs/fantastic/bin/python}"
# Content length, preview cap, and target canvas all come from the scene config.
CONTENT_LEN=$("$PYBIN" -c "import json,sys;print(json.load(open(sys.argv[1]))['content_len'])" "$SCENES")
PREVIEW_MAXLEN=$("$PYBIN" -c "import json,sys;print(json.load(open(sys.argv[1]))['preview_maxlen'])" "$SCENES")
CANVAS_W=$("$PYBIN" -c "import json,sys;print(json.load(open(sys.argv[1]))['canvas'][0])" "$SCENES")
CANVAS_H=$("$PYBIN" -c "import json,sys;print(json.load(open(sys.argv[1]))['canvas'][1])" "$SCENES")

PLATFORM="${PLATFORM:-ios}"                       # ios | ipad — selects the marketing subfolder
RAW_DIR="$APP_DIR/marketing/raw/$PLATFORM/video"
ASO_DIR="$APP_DIR/marketing/aso/$PLATFORM/video"
DERIVED="$APP_DIR/.build/reel-dd"
RAW_MOV="$RAW_DIR/capture.mov"
FULL="$ASO_DIR/full.mp4"
PREVIEW="$ASO_DIR/preview_${CANVAS_W}x${CANVAS_H}.mp4"

# App-preview resolution from the scene canvas (886x1920 iPhone 6.9", 1200x1600 iPad 13"),
# letterboxed, 30fps, H.264 high, yuv420p, faststart, no audio (muxed later).
CONFORM="scale=${CANVAS_W}:${CANVAS_H}:force_original_aspect_ratio=decrease,pad=${CANVAS_W}:${CANVAS_H}:(ow-iw)/2:(oh-ih)/2:color=black,fps=30,format=yuv420p"
ENC=(-c:v libx264 -profile:v high -crf 20 -preset medium -movflags +faststart -an)

mkdir -p "$RAW_DIR" "$ASO_DIR" "$DERIVED"

# ── Resolve & boot the simulator ────────────────────────────────────────────
UDID=$(xcrun simctl list devices | grep "$SIM_NAME (" | grep -oE "[0-9A-Fa-f-]{36}" | head -1)
[ -n "$UDID" ] || { echo "❌ simulator '$SIM_NAME' not found"; exit 1; }
echo "▶ simulator $SIM_NAME = $UDID"
xcrun simctl boot "$UDID" 2>/dev/null || true
xcrun simctl bootstatus "$UDID" -b

# ── Generate project + build for testing ────────────────────────────────────
echo "▶ xcodegen"
( cd "$APP_DIR" && xcodegen generate >/dev/null )

echo "▶ build-for-testing"
xcodebuild build-for-testing \
  -project "$PROJECT" -scheme "$SCHEME" \
  -destination "id=$UDID" -derivedDataPath "$DERIVED" \
  -quiet

# Clean marketing status bar (9:41, full battery/signal, blank carrier).
xcrun simctl status_bar "$UDID" override \
  --time "9:41" --operatorName " " --batteryState charged --batteryLevel 100 \
  --cellularBars 4 --wifiBars 3 --dataNetwork wifi 2>/dev/null || true

# Install the freshly built app + kill any stale instance, so the recording shows THIS build
# (build-for-testing compiles but doesn't install; a previously-installed build would otherwise
# be what pre-launch/activate shows).
BUILT_APP=$(find "$DERIVED/Build/Products" -maxdepth 2 -name "*.app" -path "*iphonesimulator*" ! -name "*-Runner.app" 2>/dev/null | head -1)
[ -n "$BUILT_APP" ] && xcrun simctl install "$UDID" "$BUILT_APP" >/dev/null 2>&1 || true
xcrun simctl terminate "$UDID" "$APP_BUNDLE" 2>/dev/null || true
# Return to the home screen so the launch has no "◄ PrevApp" breadcrumb in the status bar.
xcrun simctl launch "$UDID" com.apple.springboard >/dev/null 2>&1 || true
sleep 1

# Pre-launch the app so the recording opens straight on it (no prior app in frame).
# EPHEMERIS_DEMO=1 glides the Chart date; EPHEMERIS_TZ sets the shown time zone;
# EPHEMERIS_LAT/LON/PLACE set the observer so the houses + angles actually render (the
# Houses card is empty without a place). Keep the place consistent with REEL_TZ.
REEL_TZ="${REEL_TZ:-America/Los_Angeles}"
REEL_LAT="${REEL_LAT:-34.05}"
REEL_LON="${REEL_LON:--118.24}"
REEL_PLACE="${REEL_PLACE:-Los Angeles}"
echo "▶ pre-launch $APP_BUNDLE (tz $REEL_TZ, place $REEL_PLACE)"
SIMCTL_CHILD_EPHEMERIS_DEMO=1 SIMCTL_CHILD_EPHEMERIS_TZ="$REEL_TZ" \
SIMCTL_CHILD_EPHEMERIS_LAT="$REEL_LAT" SIMCTL_CHILD_EPHEMERIS_LON="$REEL_LON" \
SIMCTL_CHILD_EPHEMERIS_PLACE="$REEL_PLACE" \
  xcrun simctl launch "$UDID" "$APP_BUNDLE" >/dev/null 2>&1 || true
sleep 2

# ── Record + run the tour ───────────────────────────────────────────────────
rm -f "$RAW_MOV"
REC_LATENCY="${REC_LATENCY:-0.5}"          # recordVideo takes ~0.5s to actually start
SYSLOG="$DERIVED/reel-syslog.log"
# Stream the sim log for the tour's REEL_T0 / REEL_END markers (reliable NSLog channel).
xcrun simctl spawn "$UDID" log stream --style compact \
  --predicate 'eventMessage CONTAINS "REEL_"' > "$SYSLOG" 2>/dev/null &
LOG_PID=$!

echo "▶ recording"
RSTART=$(date +%s.%N)                       # recording clock reference
xcrun simctl io "$UDID" recordVideo --codec h264 --force "$RAW_MOV" &
REC_PID=$!
sleep 1

echo "▶ tour"
set +e
xcodebuild test-without-building \
  -project "$PROJECT" -scheme "$SCHEME" \
  -destination "id=$UDID" -derivedDataPath "$DERIVED" \
  ${ONLY_TESTING:+-only-testing:"$ONLY_TESTING"} \
  -quiet
TEST_RC=$?
set -e

kill -INT "$REC_PID" 2>/dev/null || true
wait "$REC_PID" 2>/dev/null || true
kill "$LOG_PID" 2>/dev/null || true
xcrun simctl status_bar "$UDID" clear 2>/dev/null || true

[ -s "$RAW_MOV" ] || { echo "❌ no capture produced"; exit 1; }
RAW_LEN=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$RAW_MOV")

# ── Align to the tour's markers: exact head trim + measured content length ──
T0=$(grep -oE 'REEL_T0 [0-9.]+'  "$SYSLOG" 2>/dev/null | tail -1 | awk '{print $2}')
TEND=$(grep -oE 'REEL_END [0-9.]+' "$SYSLOG" 2>/dev/null | tail -1 | awk '{print $2}')
SCENES_RUNTIME="$SCENES"
if [ -n "$T0" ] && [ -n "$TEND" ]; then
  HEAD_TRIM=$(echo "$T0 - $RSTART - $REC_LATENCY" | bc -l)
  CONTENT_LEN=$(echo "$TEND - $T0" | bc -l)
  echo "▶ raw ${RAW_LEN}s -> content ${CONTENT_LEN}s from HEAD ${HEAD_TRIM}s (marker-aligned)"
  # Merge measured per-scene timings so captions land exactly on the footage.
  if "$PYBIN" "$ROOT/marketing/reels/align_scenes.py" "$SCENES" "$SYSLOG" "$DERIVED/scenes.runtime.json"; then
    SCENES_RUNTIME="$DERIVED/scenes.runtime.json"
  fi
else
  echo "⚠ no REEL markers in sim log — falling back to HEAD ${HEAD_TRIM}s / CONTENT ${CONTENT_LEN}s"
fi

# ── Conform ─────────────────────────────────────────────────────────────────
# Full: natural speed, whole walkthrough.
echo "▶ ffmpeg -> full"
# Output-side -ss (after -i) is frame-accurate; input-side snaps to a sparse keyframe and
# starts the content late. A ~1min capture decodes fast, so accuracy wins over speed here.
ffmpeg -y -loglevel error -i "$RAW_MOV" -ss "$HEAD_TRIM" -t "$CONTENT_LEN" -vf "$CONFORM" "${ENC[@]}" "$FULL"

# Preview: speed-fit the (already exact) full cut so the ENTIRE walkthrough fits the cap.
SPEED=$(echo "if ($CONTENT_LEN > $PREVIEW_MAXLEN) $CONTENT_LEN / $PREVIEW_MAXLEN else 1" | bc -l)
echo "▶ ffmpeg -> preview (speed x$SPEED -> <=${PREVIEW_MAXLEN}s)"
ffmpeg -y -loglevel error -i "$FULL" -vf "setpts=PTS/$SPEED,fps=30,format=yuv420p" "${ENC[@]}" "$PREVIEW"

dur() { ffprobe -v error -show_entries format=duration -of csv=p=0 "$1"; }
res() { ffprobe -v error -select_streams v:0 -show_entries stream=width,height -of csv=p=0:s=x "$1"; }
echo
echo "✅ done (test rc=$TEST_RC)"
echo "   raw:     $RAW_MOV"
echo "   full:    $FULL     $(res "$FULL")  $(dur "$FULL")s"
echo "   preview: $PREVIEW  $(res "$PREVIEW")  $(dur "$PREVIEW")s"
[ "$TEST_RC" -eq 0 ] || echo "   ⚠ tour test returned non-zero — reel may be partial"

# ── Framed ad reel: gradient bg + device frame + per-scene captions + branded outro ──
echo
echo "▶ framing (captions + outro)"
"$PYBIN" "$FRAME_PY" --scenes "$SCENES_RUNTIME" --video "$FULL" --app-dir "$APP_DIR" --out-dir "$ASO_DIR"
