#!/usr/bin/env bash
#
# capture_reel.sh [locale] — App Store preview reel, iPhone/iPad, driven from inside the app.
#
#   ./capture_reel.sh de
#   PLATFORM=ipad ./capture_reel.sh ja
#
# Replaces capture_reel.sh's XCUITest tour. The app walks its own tabs under EPHEMERIS_REEL=1 and
# emits REEL_T0 / REEL_SCENE / REEL_END itself (see ephemeris/ViewModels/ReelDriver.swift), so:
#
#   • no element lookup, so nothing depends on a translated label or on how a given iOS version
#     exposes its tab bar — the two things that produced three separate silently-wrong reels
#   • no test bundle to build or run, so a capture is ~90s instead of ~6min
#   • the markers come from the same code that performs the switch, so a caption can never be
#     timed against a tab change that did not happen
set -uo pipefail

ROOT=/Users/oleksandr/Projects/rootyapps
APP_DIR="$ROOT/ephemeris.swift"
BUNDLE=oleksandr.aisixteen.ephemeris
PYBIN=/Users/oleksandr/miniconda3/envs/fantastic/bin/python
LOC="${1:-en}"
PLATFORM="${PLATFORM:-ios}"
# WHICH reel. The store allows three previews per device size, and one video cannot sell both the
# live sky and saved natal charts. Everything below is namespaced by this, because the pipeline
# used to assume exactly one reel per device+locale — a single scenes.json and a single output dir.
REEL="${REEL:-sky}"

if [ "$PLATFORM" = ipad ]; then
  SIM_NAME="${SIM_NAME:-Ephemeris-iPadPro13}"; CAPTURE_WH=2064x2752
  _DEV=ipad
else
  SIM_NAME="${SIM_NAME:-Ephemeris-iPhone17ProMax}"; CAPTURE_WH=1320x2868
  _DEV=iphone
fi
SCENES="$APP_DIR/marketing/reels/scenes/$REEL/${_DEV}_${LOC}.json"
[ -f "$SCENES" ] || { echo "no scenes for reel '$REEL' $_DEV/$LOC at $SCENES" >&2; exit 1; }

RAW_DIR="$APP_DIR/marketing/raw/$LOC/$PLATFORM/video/$REEL"
ASO_DIR="$APP_DIR/marketing/aso/$LOC/$PLATFORM/video/$REEL"
DERIVED="$APP_DIR/.build/reel2-$PLATFORM"
mkdir -p "$RAW_DIR" "$ASO_DIR" "$DERIVED"
RAW_MOV="$RAW_DIR/capture.mov"
SYSLOG="$DERIVED/markers-$REEL-$LOC.log"

CANVAS_W=$("$PYBIN" -c "import json,sys;print(json.load(open(sys.argv[1]))['canvas'][0])" "$SCENES")
CANVAS_H=$("$PYBIN" -c "import json,sys;print(json.load(open(sys.argv[1]))['canvas'][1])" "$SCENES")
PREVIEW_MAXLEN=$("$PYBIN" -c "import json,sys;print(json.load(open(sys.argv[1]))['preview_maxlen'])" "$SCENES")

case "$LOC" in
  de) TZ=Europe/Berlin; LAT=52.52; LON=13.405; PLACE=Berlin ;;
  fr) TZ=Europe/Paris;  LAT=48.857; LON=2.352; PLACE=Paris ;;
  ja) TZ=Asia/Tokyo;    LAT=35.690; LON=139.692; PLACE=Tokyo ;;
  *)  TZ=America/Los_Angeles; LAT=34.052; LON=-118.244; PLACE="Los Angeles" ;;
esac

UDID=$(xcrun simctl list devices | grep "$SIM_NAME (" | grep -oE "[0-9A-F-]{36}" | head -1)
[ -n "$UDID" ] || { echo "❌ simulator '$SIM_NAME' not found"; exit 1; }
echo "▶ $REEL reel · $PLATFORM / $LOC on $SIM_NAME ($PLACE)"
xcrun simctl boot "$UDID" 2>/dev/null; xcrun simctl bootstatus "$UDID" -b >/dev/null 2>&1

( cd "$APP_DIR" && xcodegen generate >/dev/null 2>&1 )
xcodebuild -project "$APP_DIR/ephemeris.swift.xcodeproj" -scheme ephemeris.swift \
  -destination "id=$UDID" -derivedDataPath "$DERIVED" build >/dev/null 2>&1 \
  || { echo "❌ build failed"; exit 1; }
# MUST be constrained to the simulator platform. The watch app also has PRODUCT_NAME=Ephemeris and
# is built alongside (it is embedded in the iOS app), so an unconstrained find can return
# Debug-watchsimulator/Ephemeris.app — which installs with "This app is not made for this device.
# app is compatible with (4) but this device supports (1)", family 4 being watchOS.
APP_PATH=$(find "$DERIVED/Build/Products" -maxdepth 2 -name 'Ephemeris.app' \
  -path '*iphonesimulator*' | head -1)
[ -n "$APP_PATH" ] || { echo "❌ no iphonesimulator build of Ephemeris.app in $DERIVED" >&2; exit 1; }
xcrun simctl install "$UDID" "$APP_PATH" || { echo "❌ install failed"; exit 1; }
xcrun simctl status_bar "$UDID" override --time "9:41" --cellularBars 4 --wifiBars 3 \
  --batteryState charged --batteryLevel 100 >/dev/null 2>&1

# Home screen first, so the launch carries no "◄ PrevApp" breadcrumb in the status bar.
xcrun simctl terminate "$UDID" "$BUNDLE" 2>/dev/null
xcrun simctl launch "$UDID" com.apple.springboard >/dev/null 2>&1
sleep 1

rm -f "$RAW_MOV" "$SYSLOG"
xcrun simctl spawn "$UDID" log stream --style compact --predicate 'eventMessage CONTAINS "REEL_"' > "$SYSLOG" 2>/dev/null &
LOG_PID=$!
for _ in $(seq 1 30); do [ -s "$SYSLOG" ] && break; sleep 0.5; done

echo "▶ recording"
# simctl allows ONE host recording at a time, across every simulator. `kill -INT` returns before
# the recorder has actually released it, so a run that starts the moment the previous one exits
# gets "Resource busy — Host recording is already in progress", writes nothing, and leaves the
# PREVIOUS capture's file sitting on disk. That is how a whole platform's reels were reported as
# 30.00s with audio while being a day old: the failure is loud in the log and invisible in the
# output. Wait for the recorder to be genuinely gone before claiming it.
for _ in $(seq 1 40); do
  pgrep -f "simctl io .* recordVideo" >/dev/null || break
  sleep 0.5
done
if pgrep -f "simctl io .* recordVideo" >/dev/null; then
  echo "❌ another simctl recording is still running — refusing to start" >&2
  exit 1
fi
RSTART=$(date +%s.%N)
xcrun simctl io "$UDID" recordVideo --codec h264 --force "$RAW_MOV" &
REC_PID=$!
sleep 1
# The recorder can fail *after* forking — the error goes to its stderr and the pid still exists
# for a moment. Confirm it survived rather than assuming a successful start.
sleep 1
if ! kill -0 "$REC_PID" 2>/dev/null; then
  echo "❌ recorder exited immediately — the host recorder was busy" >&2
  exit 1
fi

SIMCTL_CHILD_EPHEMERIS_REEL=1 SIMCTL_CHILD_EPHEMERIS_REEL_TOUR="$REEL" \
  SIMCTL_CHILD_EPHEMERIS_DEMO=1 SIMCTL_CHILD_EPHEMERIS_LANG="$LOC" \
SIMCTL_CHILD_EPHEMERIS_TZ="$TZ" SIMCTL_CHILD_EPHEMERIS_LAT="$LAT" \
SIMCTL_CHILD_EPHEMERIS_LON="$LON" SIMCTL_CHILD_EPHEMERIS_PLACE="$PLACE" \
  xcrun simctl launch "$UDID" "$BUNDLE" >/dev/null

# The tour is 34s of dwell plus launch and settle; stop once REEL_END lands, or bail at 75s.
for _ in $(seq 1 150); do grep -q "REEL_END" "$SYSLOG" 2>/dev/null && break; sleep 0.5; done
sleep 1
kill -INT "$REC_PID" 2>/dev/null; wait "$REC_PID" 2>/dev/null
# `wait` returns when our child exits, but simctl's recorder is a separate process that outlives
# it briefly and keeps the host slot. Not draining it here is what made the NEXT platform fail.
for _ in $(seq 1 40); do
  pgrep -f "simctl io .* recordVideo" >/dev/null || break
  sleep 0.5
done
kill "$LOG_PID" 2>/dev/null
xcrun simctl terminate "$UDID" "$BUNDLE" 2>/dev/null
xcrun simctl status_bar "$UDID" clear 2>/dev/null

# simctl creates and flushes the file asynchronously; judge it only once it stops growing.
_prev=-1
for _ in $(seq 1 60); do
  _cur=$(stat -f%z "$RAW_MOV" 2>/dev/null || echo 0)
  [ "$_cur" = "$_prev" ] && [ "$_cur" -gt 0 ] && break
  _prev=$_cur; sleep 0.5
done
[ -s "$RAW_MOV" ] || { echo "❌ no capture produced"; exit 1; }

T0=$(grep -oE 'REEL_T0 [0-9.]+' "$SYSLOG" | tail -1 | awk '{print $2}')
TEND=$(grep -oE 'REEL_END [0-9.]+' "$SYSLOG" | tail -1 | awk '{print $2}')
[ -n "$T0" ] && [ -n "$TEND" ] || { echo "❌ no REEL markers — refusing to guess caption timing"; exit 1; }
HEAD_TRIM=$(echo "$T0 - $RSTART - 0.5" | bc -l)
CONTENT_LEN=$(echo "$TEND - $T0" | bc -l)
echo "▶ content ${CONTENT_LEN}s from HEAD ${HEAD_TRIM}s (marker-aligned)"

SCENES_RUNTIME="$DERIVED/scenes-$REEL-$LOC.runtime.json"
"$PYBIN" "$ROOT/marketing/reels/align_scenes.py" "$SCENES" "$SYSLOG" "$SCENES_RUNTIME" \
  || SCENES_RUNTIME="$SCENES"

CONFORM="scale=${CANVAS_W}:${CANVAS_H}:force_original_aspect_ratio=decrease,pad=${CANVAS_W}:${CANVAS_H}:(ow-iw)/2:(oh-ih)/2:color=black,fps=30,format=yuv420p"
FULL="$ASO_DIR/full.mp4"
ffmpeg -y -loglevel error -i "$RAW_MOV" -ss "$HEAD_TRIM" -t "$CONTENT_LEN" -vf "$CONFORM" \
  -c:v libx264 -profile:v high -crf 20 -preset medium -movflags +faststart -an "$FULL"

echo "▶ store preview (full-bleed, 2.3.4-compliant)"
"$PYBIN" "$ROOT/marketing/reels/store_preview.py" \
  --scenes "$SCENES_RUNTIME" --video "$FULL" --out-dir "$ASO_DIR" \
  --audio "$APP_DIR/marketing/audio/bed30_appstore.wav" --source-aspect "$CAPTURE_WH"

for f in "$ASO_DIR"/store_preview_*_music.mp4; do
  [ -e "$f" ] || continue
  ffprobe -v error -show_entries stream=codec_type -of csv=p=0 "$f" | grep -q audio \
    || echo "❌ $f has no audio stream — App Store Connect will reject it"
done
echo "✅ $PLATFORM / $LOC done"
