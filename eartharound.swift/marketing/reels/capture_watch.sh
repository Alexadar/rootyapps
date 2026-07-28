#!/usr/bin/env bash
#
# capture_watch.sh — Apple Watch marketing assets for Earth Around.
#
# Produces TWO things with different fates:
#   1. marketing/raw/watch/0{1,2,3}_*.png  — 416x496 page captures. These feed
#      generate_screenshots.py and ARE uploadable (APP_WATCH_SERIES_10, --platform IOS).
#   2. marketing/aso/watch/video/full.mp4  — a walkthrough for the site/social ONLY.
#      App Store Connect has NO watchOS app-preview slot: Apple's preview spec has no
#      watch row, ASC Help scopes previews to iOS/macOS/tvOS/visionOS, and the API's
#      previewType enum contains zero watch values. Do not try to upload it.
#
# Unlike the iPhone sim, watchOS does NOT support `simctl status_bar override`, so the
# capture shows the simulator's real clock — there is no 9:41 to force.
set -euo pipefail

ROOT="/Users/oleksandr/Projects/rootyapps"
APP_DIR="$ROOT/eartharound.swift"
PROJECT="$APP_DIR/eartharound.swift.xcodeproj"
SCHEME="${SCHEME:-SpaceWeatherWatch}"
APP_BUNDLE="${APP_BUNDLE:-oleksandr.aisixteen.eartharound.watchkitapp}"
SIM_NAME="${SIM_NAME:-SW-Watch-S11}"
DERIVED="$APP_DIR/.build/watch-dd"
LOC="${1:-en}"                 # BCP-47 tag; English is explicit, not a special case
_WSCENES="$APP_DIR/marketing/reels/scenes_watch.json"
[ "$LOC" = en ] || _WSCENES="$APP_DIR/marketing/reels/scenes_watch_$LOC.json"
SCENES="${SCENES:-$_WSCENES}"
SHOTS_ONLY="${SHOTS_ONLY:-0}"  # 1 = stills only, skip the walkthrough recording
RAW_DIR="$APP_DIR/marketing/raw/$LOC/watch"
VIDEO_DIR="$APP_DIR/marketing/aso/$LOC/watch/video"
SETTLE="${SETTLE:-9}"          # first paint + live fetch

mkdir -p "$RAW_DIR/video" "$VIDEO_DIR" "$DERIVED"

UDID=$(xcrun simctl list devices | grep "$SIM_NAME (" | grep -oE "[0-9A-Fa-f-]{36}" | head -1)
[ -n "$UDID" ] || { echo "❌ watch simulator '$SIM_NAME' not found"; exit 1; }
echo "▶ watch simulator $SIM_NAME = $UDID"
xcrun simctl boot "$UDID" 2>/dev/null || true
xcrun simctl bootstatus "$UDID" -b

echo "▶ build"
xcodebuild build -project "$PROJECT" -scheme "$SCHEME" \
  -destination "id=$UDID" -derivedDataPath "$DERIVED" -quiet

BUILT_APP=$(find "$DERIVED/Build/Products" -maxdepth 2 -name "*.app" -path "*watchsimulator*" | head -1)
[ -n "$BUILT_APP" ] || { echo "❌ no built watch .app"; exit 1; }
xcrun simctl install "$UDID" "$BUILT_APP" >/dev/null

# ── 1. One screenshot per page, each frozen via the static flag ─────────────
PAGES=(readout geomag wind)
for i in 0 1 2; do
  xcrun simctl terminate "$UDID" "$APP_BUNDLE" 2>/dev/null || true
  SIMCTL_CHILD_EARTHAROUND_THEME="${THEME:-dark}" \
  SIMCTL_CHILD_EARTHAROUND_WATCH_PAGE=$i xcrun simctl launch "$UDID" "$APP_BUNDLE" \
    -AppleLanguages "($LOC)" -AppleLocale "$LOC" >/dev/null
  sleep "$SETTLE"
  OUT=$(printf "%s/%02d_%s.png" "$RAW_DIR" $((i + 1)) "${PAGES[$i]}")
  xcrun simctl io "$UDID" screenshot "$OUT" >/dev/null 2>&1
  echo "   captured $(basename "$OUT")  $(sips -g pixelWidth -g pixelHeight "$OUT" | awk '/pixel/{printf "%s ", $2}')"
done

# ── 2. Walkthrough video (web/social only — see header) ────────────────────
if [ "$SHOTS_ONLY" = "1" ]; then
  echo "✅ stills only ($LOC) in $RAW_DIR"
  exit 0
fi
echo "▶ recording walkthrough"
xcrun simctl terminate "$UDID" "$APP_BUNDLE" 2>/dev/null || true
SYSLOG="$DERIVED/watch-syslog.log"; rm -f "$SYSLOG"
xcrun simctl spawn "$UDID" log stream --style compact \
  --predicate 'eventMessage CONTAINS "REEL_"' > "$SYSLOG" 2>/dev/null &
LOG_PID=$!

RAW_MOV="$RAW_DIR/video/capture.mov"; rm -f "$RAW_MOV"
RSTART=$(date +%s.%N)
xcrun simctl io "$UDID" recordVideo --codec h264 --force "$RAW_MOV" &
REC_PID=$!
sleep 1
SIMCTL_CHILD_EARTHAROUND_THEME="${THEME:-dark}" SIMCTL_CHILD_EARTHAROUND_DEMO=1 xcrun simctl launch "$UDID" "$APP_BUNDLE" >/dev/null

for _ in $(seq 1 45); do
  grep -q "REEL_END" "$SYSLOG" 2>/dev/null && break
  sleep 1
done
grep -q "REEL_END" "$SYSLOG" 2>/dev/null || echo "⚠ tour never reached REEL_END"
sleep "${DRAIN:-4}"
kill -INT "$REC_PID" 2>/dev/null || true; wait "$REC_PID" 2>/dev/null || true
kill "$LOG_PID" 2>/dev/null || true
[ -s "$RAW_MOV" ] || { echo "❌ no capture produced"; exit 1; }

# Trim to the tour's own REEL_T0 marker, not a guessed offset: the beats are equal by
# construction, so frame_watch.sh can fit captions to even thirds — but only if the footage
# starts exactly at T0. A guessed head trim slides every caption off its page.
T0=$(grep -oE 'REEL_T0 [0-9.]+' "$SYSLOG" | tail -1 | awk '{print $2}')
TEND=$(grep -oE 'REEL_END [0-9.]+' "$SYSLOG" | tail -1 | awk '{print $2}')
if [ -n "${T0:-}" ] && [ -n "${TEND:-}" ]; then
  HEAD_TRIM=$(echo "$T0 - $RSTART - ${REC_LATENCY:-0.5}" | bc -l)
  CONTENT_LEN=$(echo "$TEND - $T0" | bc -l)
  echo "▶ marker-aligned: head ${HEAD_TRIM}s, content ${CONTENT_LEN}s"
else
  HEAD_TRIM="${HEAD_TRIM:-2.0}"; CONTENT_LEN=""
  echo "⚠ no REEL markers — falling back to head ${HEAD_TRIM}s"
fi

# The sim encoder drops frames, so the footage holds less time than the wall clock. Clamp
# to what actually exists, and let the framer fit the beats to that.
RAW_LEN=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$RAW_MOV")
AVAIL=$(echo "$RAW_LEN - $HEAD_TRIM - 0.1" | bc -l)
if [ -n "$CONTENT_LEN" ] && [ "$(echo "$AVAIL < $CONTENT_LEN" | bc -l)" -eq 1 ]; then
  CONTENT_LEN=$AVAIL
fi
ffmpeg -y -loglevel error -i "$RAW_MOV" -ss "$HEAD_TRIM" ${CONTENT_LEN:+-t "$CONTENT_LEN"} \
  -vf "fps=30,format=yuv420p" -c:v libx264 -profile:v high -crf 20 -preset medium \
  -movflags +faststart -an "$VIDEO_DIR/full.mp4"

echo
echo "✅ watch capture done"
echo "   screenshots: $RAW_DIR/0{1,2,3}_*.png  → generate_screenshots.py ($APP_DIR/marketing/aso/watch/params.yaml)"
echo "   video:       $VIDEO_DIR/full.mp4  $(ffprobe -v error -show_entries format=duration -of csv=p=0 "$VIDEO_DIR/full.mp4")s  (web/social only — ASC has no watch preview slot)"
