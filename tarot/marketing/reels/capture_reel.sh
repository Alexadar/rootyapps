#!/usr/bin/env bash
#
# capture_reel.sh [scenario] — App Store preview reel for Tarot, iPhone simulator.
#
#   ./capture_reel.sh                 # the default scenario
#   ./capture_reel.sh will-i-be-rich
#
# Tarot drives its own take from a FILMING SCENARIO (Tarot/Debug/Scenarios/*.scenario.yaml):
# the deck, skin, method, seed, the three cards, the typed question, the reading text and every
# beat's timing are pinned in that file. So unlike a tour that walks the UI, this reel is
# reproducible to the frame — a re-shoot after a code change is still the same video, and the
# only way to change the cut is to edit the YAML.
#
# The app emits SCENARIO_T0 / SCENARIO_BEAT / SCENARIO_END itself, from the same code that
# performs each beat, so the trim can never be aligned against a beat that did not happen.
#
# Per the shared README: what lands in aso/ is FULL-BLEED. Never frame an App Store preview
# (2.3.4 — Overtone Lab was rejected for exactly that).
set -uo pipefail

ROOT=/Users/oleksandr/Projects/rootyapps
APP_DIR="$ROOT/tarot"
BUNDLE=oleksandr.aisixteen.tarot
SCENARIO="${1:-will-i-be-rich}"
LOC="${LOC:-en}"
PLATFORM=ios

SIM_NAME="${SIM_NAME:-tarot-film}"
CAPTURE_WH=1320x2868          # iPhone 17 Pro Max
CANVAS_W=886; CANVAS_H=1920   # the store's portrait preview canvas

YAML="$APP_DIR/Tarot/Debug/Scenarios/$SCENARIO.scenario.yaml"
[ -f "$YAML" ] || { echo "❌ no scenario at $YAML" >&2; exit 1; }
# A take filmed against placeholder copy is worthless and looks fine in the file listing —
# refuse it here rather than discover it in the cut.
if grep -qi "PLACEHOLDER\|Placeholder for the" "$YAML"; then
  echo "❌ $SCENARIO still holds placeholder passages — capture the real text first:" >&2
  echo "   xcrun simctl launch --console-pty <UDID> $BUNDLE -TAROT_SCENARIO $SCENARIO -TAROT_SCENARIO_LIVE" >&2
  exit 1
fi

RAW_DIR="$APP_DIR/marketing/raw/$LOC/$PLATFORM/video/$SCENARIO"
ASO_DIR="$APP_DIR/marketing/aso/$LOC/$PLATFORM/video/$SCENARIO"
DERIVED="$APP_DIR/.build/reel-$PLATFORM"
mkdir -p "$RAW_DIR" "$ASO_DIR" "$DERIVED"
RAW_MOV="$RAW_DIR/capture.mov"
SYSLOG="$DERIVED/markers-$SCENARIO-$LOC.log"

UDID=$(xcrun simctl list devices | grep "$SIM_NAME (" | grep -oE "[0-9A-F-]{36}" | head -1)
[ -n "$UDID" ] || { echo "❌ simulator '$SIM_NAME' not found — create one (iPhone 17 Pro Max)"; exit 1; }
echo "▶ $SCENARIO · $PLATFORM / $LOC on $SIM_NAME"
xcrun simctl boot "$UDID" 2>/dev/null; xcrun simctl bootstatus "$UDID" -b >/dev/null 2>&1

APP_PATH="${APP_PATH:-}"
if [ -n "$APP_PATH" ]; then
  xcrun simctl install "$UDID" "$APP_PATH" || { echo "❌ install failed"; exit 1; }
fi
xcrun simctl status_bar "$UDID" override --time "9:41" --cellularBars 4 --wifiBars 3 \
  --batteryState charged --batteryLevel 100 2>/dev/null
xcrun simctl terminate "$UDID" "$BUNDLE" 2>/dev/null
sleep 1

rm -f "$RAW_MOV" "$SYSLOG"
xcrun simctl spawn "$UDID" log stream --style compact --predicate 'eventMessage CONTAINS "SCENARIO_"' > "$SYSLOG" 2>/dev/null &
LOG_PID=$!
for _ in $(seq 1 30); do [ -s "$SYSLOG" ] && break; sleep 0.5; done

echo "▶ recording"
# simctl allows ONE host recording at a time, across every simulator, and `kill -INT` returns
# before the slot is released — a run started too soon writes nothing and leaves the PREVIOUS
# capture on disk, which reads as success. Wait for the recorder to be genuinely gone.
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
sleep 2
# The recorder can fail AFTER forking; confirm it survived rather than assuming.
if ! kill -0 "$REC_PID" 2>/dev/null; then
  echo "❌ recorder exited immediately — the host recorder was busy" >&2
  exit 1
fi

xcrun simctl launch "$UDID" "$BUNDLE" \
  -TAROT_SCENARIO "$SCENARIO" -AppleLanguages "(en)" >/dev/null

# The scenario is ~13s to the reading panel plus its hold; stop on SCENARIO_END, bail at 90s.
for _ in $(seq 1 240); do grep -q "SCENARIO_END" "$SYSLOG" 2>/dev/null && break; sleep 0.5; done
# Margin, not politeness. `log stream` delivers with its own latency and the recorder needs a
# moment to flush, so stopping 1 s after the marker once cut 1.65 s off the tail — the take ran
# to 37.03 s against a 38.71 s content length, and ffmpeg silently produced the short file.
sleep 3
kill -INT "$REC_PID" 2>/dev/null; wait "$REC_PID" 2>/dev/null
# simctl's recorder outlives our child briefly and keeps the host slot; drain it or the NEXT
# capture fails.
for _ in $(seq 1 40); do
  pgrep -f "simctl io .* recordVideo" >/dev/null || break
  sleep 0.5
done
kill "$LOG_PID" 2>/dev/null
xcrun simctl terminate "$UDID" "$BUNDLE" 2>/dev/null
xcrun simctl status_bar "$UDID" clear 2>/dev/null

# The file is created and flushed asynchronously; judge it only once it stops growing.
_prev=-1
for _ in $(seq 1 60); do
  _cur=$(stat -f%z "$RAW_MOV" 2>/dev/null || echo 0)
  [ "$_cur" = "$_prev" ] && [ "$_cur" -gt 0 ] && break
  _prev=$_cur; sleep 0.5
done
[ -s "$RAW_MOV" ] || { echo "❌ no capture produced"; exit 1; }

if grep -q "SCENARIO_WARN" "$SYSLOG"; then
  echo "⚠️  $(grep -o 'SCENARIO_WARN.*' "$SYSLOG" | tail -1)" >&2
fi

T0=$(grep -oE 'SCENARIO_T0 [a-z0-9-]+ [0-9.]+' "$SYSLOG" | tail -1 | awk '{print $3}')
TEND=$(grep -oE 'SCENARIO_END [0-9.]+' "$SYSLOG" | tail -1 | awk '{print $2}')
[ -n "$T0" ] && [ -n "$TEND" ] || { echo "❌ no SCENARIO markers — refusing to guess the trim"; exit 1; }
CONTENT_LEN=$(echo "$TEND - $T0" | bc -l)

# LENGTH comes from the markers; START comes from the picture. They are different questions and
# only one of them has a trustworthy clock.
#
# The markers are stamped with wall time, so mapping them onto video time assumes the recorder
# runs at exactly real speed. It does not: this capture averaged 49.7 fps against a nominal 60,
# and the resulting few seconds of drift put HEAD past the true start — ffmpeg then ran out of
# source and wrote a file 1.65 s short at the tail. CONTENT_LEN is safe because it is a
# difference of two app-clock stamps, so the drift cancels.
#
# For START, the launch has three visually distinct phases and luminance separates them cleanly:
# the system launch screen is white (~232), the app's own launch curtain is near-black (~25),
# and the loaded table sits around 60. So: the first frame in the table's band, confirmed by
# three consecutive samples so a fade passing through the band cannot trigger it.
echo "▶ locating the loaded frame"
SCAN=$(ffmpeg -loglevel info -i "$RAW_MOV" -vf "fps=4,scale=16:16,signalstats,metadata=print" \
  -f null - 2>&1 | grep -oE "pts_time:[0-9.]+|YAVG=[0-9.]+" | paste - -)
HEAD_TRIM=$(printf '%s\n' "$SCAN" | awk -F'[:=\t]' '
  $4 >= 50 && $4 <= 120 { run++; if (run == 3) { print $2; exit } }
  $4 < 50 || $4 > 120   { run = 0 }')
if [ -z "$HEAD_TRIM" ]; then
  echo "❌ could not find the loaded app in the capture — refusing to guess the trim" >&2
  exit 1
fi
echo "▶ content ${CONTENT_LEN}s (markers) from HEAD ${HEAD_TRIM}s (first loaded frame)"
echo "▶ beats:"; grep -oE 'SCENARIO_BEAT [a-z0-9_]+ [0-9.]+' "$SYSLOG" | awk '{printf "   %-12s %ss\n", $2, $3}'

# Full-bleed conform. No pad colour trickery and no bezel: this is the store artefact.
CONFORM="scale=${CANVAS_W}:${CANVAS_H}:force_original_aspect_ratio=decrease,pad=${CANVAS_W}:${CANVAS_H}:(ow-iw)/2:(oh-ih)/2:color=black,fps=30,format=yuv420p"
FULL="$ASO_DIR/full.mp4"
ffmpeg -y -loglevel error -i "$RAW_MOV" -ss "$HEAD_TRIM" -t "$CONTENT_LEN" -vf "$CONFORM" \
  -c:v libx264 -profile:v high -crf 20 -preset medium -movflags +faststart -an "$FULL"

# The trim maps wall-clock markers onto video time, which holds only while the recorder keeps
# up. If it drops behind, ffmpeg runs out of source and writes a SHORT file without complaining
# — the one failure mode that looks like a healthy capture. Compare what we got with what we
# asked for.
GOT=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$FULL")
SHORT=$(echo "$CONTENT_LEN - $GOT > 0.3" | bc -l)
if [ "$SHORT" = "1" ]; then
  echo "❌ cut is ${GOT}s but the content is ${CONTENT_LEN}s — the recording ended early" >&2
  echo "   the tail of the reading is missing; re-shoot rather than ship this" >&2
  exit 1
fi

# Prove it, rather than trusting the arithmetic: the whole point of the scan above is that the
# first frame is the app. A white opener is exactly the kind of defect that looks fine in every
# log line and only exists in the picture.
OPEN_Y=$(ffmpeg -loglevel info -i "$FULL" -t 0.1 -vf "scale=16:16,signalstats,metadata=print" \
  -f null - 2>&1 | grep -oE "YAVG=[0-9.]+" | head -1 | cut -d= -f2)
if [ -n "$OPEN_Y" ] && [ "$(echo "$OPEN_Y > 100" | bc -l)" = "1" ]; then
  echo "❌ the cut opens on a bright frame (YAVG $OPEN_Y) — that is the launch screen" >&2
  exit 1
fi
echo "▶ opening frame YAVG $OPEN_Y (dark — the app, not the launch screen)"

echo "✅ raw  $RAW_MOV"
echo "✅ full $FULL  ($(ffprobe -v error -show_entries format=duration -of csv=p=0 "$FULL")s)"
echo "next: captions + bed via $ROOT/marketing/reels/store_preview.py (needs a scenes.json)"
