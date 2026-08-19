#!/usr/bin/env bash
#
# make_sim_shots.sh — raw iPhone/iPad captures into marketing/raw/en/<platform>, then framed.
#
#   ./make_sim_shots.sh              # iPhone 6.9"
#   PLATFORM=ipad ./make_sim_shots.sh
#
# English only, by owner's decision — localized TEXT is cheap and compounds, localized MEDIA is
# not, and tarot has no locale worth the per-locale capture cost yet (§6.6 TEXT SCOPE ≠ MEDIA
# SCOPE).
#
# Every other app in this repo picks a shot's state with a launch env var. Tarot cannot: its
# screens are not modes, they are MOMENTS in a physical draw — a card in flight, three cards
# landing, a reading arriving a word at a time. There is no flag for "card halfway to the second
# position". So the shots come off the FILMING SCENARIO instead: the same pinned deck, seed,
# cards, question and reading text the preview video uses, sampled at chosen beats. The stills and
# the video therefore cannot disagree with each other, and a re-capture after a UI change
# reproduces the same five frames.
#
# Timing is measured from SCENARIO_T0 in the log, never from when we launched. App launch on a
# cold simulator has been observed anywhere from 6 s to 40 s, so a sleep counted from `simctl
# launch` lands on a different beat every run.
set -uo pipefail

ROOT=/Users/oleksandr/Projects/rootyapps
APP_DIR="$ROOT/tarot"
BUNDLE=oleksandr.aisixteen.tarot
PY=/Users/oleksandr/miniconda3/envs/fantastic/bin/python
PLATFORM="${PLATFORM:-ios}"
SCENARIO="${SCENARIO:-will-i-be-rich}"
LOC=en

if [ "$PLATFORM" = ipad ]; then
  SIM_NAME="tarot-shots-ipad"
  DEVTYPE=com.apple.CoreSimulator.SimDeviceType.iPad-Pro-13-inch-M4-16GB
else
  SIM_NAME="tarot-shots-ios"
  DEVTYPE=com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro-Max
fi
RUNTIME=com.apple.CoreSimulator.SimRuntime.iOS-26-5

# ── The shot list: name | seconds after SCENARIO_T0 ──────────────────────────
#
# Beats measured off a real take (they reproduce within 7 ms): question typed 1.67, draw 3.06,
# cards land 5.11 / 7.91 / 10.72, reading panel opens 13.45, reading finishes ~39.
#
#   01 the table, question typed, before anything moves — the product in one frame
#   02 a card in flight — one down, the next crossing the table (the drag runs
#      8.1-9.05, so 8.6 is mid-air; 6.4 caught it still sitting on the deck)
#   03 all three down, before the panel takes the screen
#   04 the reading arriving, mid-write, with the panel open
#   05 the reading complete, scrolled to the synthesis
SHOTS=(
  "01_table|2.2"
  "02_draw|8.6"
  "03_spread|12.6"
  "04_reading|22.0"
  "05_synthesis|40.0"
)

RAW="$APP_DIR/marketing/raw/$LOC/$PLATFORM"
mkdir -p "$RAW"
# Nothing downstream deletes, and the framer pairs captions to captures by sorted filename taking
# the first N — one leftover PNG shifts every caption onto the wrong screen (§6.6 STALE OUTPUTS).
rm -f "$RAW"/*.png

DERIVED="$APP_DIR/.build/dd-shots-$PLATFORM"

# A capture that is mostly bright did not render the app: every tarot screen is a dark table, and
# the two things that produce a light frame are the white launch screen and a `simctl io
# screenshot` that succeeded before first paint — both of which write a valid PNG and exit 0.
valid() { "$PY" - "$1" <<'PYEOF'
import sys
from PIL import Image
import numpy as np
a = np.asarray(Image.open(sys.argv[1]).convert("L")).astype(float)
h, w = a.shape
mean, std = a.mean(), a.std()
rendered = mean < 150 and std > 8

# A SYSTEM NOTIFICATION BANNER is the defect this catches. A fresh simulator posts "Ready for
# Apple Intelligence" a minute or so after first boot, and it landed square across shot 04 of
# the first run — a light rounded rectangle over the app, in a store screenshot. It cannot be
# turned off through simctl, it is timing-dependent so it moves between runs, and every other
# check here passes happily with it present.
#
# The app's own chrome in this band is dark, so a run of bright ROWS is unambiguous. Rows, not
# pixels: the small light "New Draw" button never makes a whole row bright, a banner does.
band = a[int(h * 0.03):int(h * 0.18)]
runs = best = 0
for r in band.mean(axis=1):
    runs = runs + 1 if r > 110 else 0
    best = max(best, runs)
banner = best >= 8

ok = rendered and not banner
why = "ok" if ok else ("BANNER" if banner else "REJECT")
print(f"    mean={mean:.1f} std={std:.1f} brightrows={best} -> {why}", file=sys.stderr)
sys.exit(0 if ok else 1)
PYEOF
}

UDID=$(xcrun simctl list devices | grep "$SIM_NAME (" | grep -oE "[0-9A-F-]{36}" | head -1)
if [ -z "$UDID" ]; then
  echo "▶ creating $SIM_NAME"
  UDID=$(xcrun simctl create "$SIM_NAME" "$DEVTYPE" "$RUNTIME") || exit 1
fi
echo "▶ $PLATFORM on $SIM_NAME ($UDID)"
xcrun simctl boot "$UDID" 2>/dev/null; xcrun simctl bootstatus "$UDID" -b >/dev/null 2>&1

echo "▶ building"
( cd "$APP_DIR" && xcodebuild -project tarot.xcodeproj -scheme tarot \
    -destination "id=$UDID" -derivedDataPath "$DERIVED" build >/dev/null 2>&1 ) \
  || { echo "❌ build failed" >&2; exit 1; }
APP_PATH=$(find "$DERIVED/Build/Products" -maxdepth 2 -path '*iphonesimulator*' -name 'Tarot.app' | head -1)
[ -n "$APP_PATH" ] || { echo "❌ no simulator Tarot.app under $DERIVED" >&2; exit 1; }
# Fatal, not a warning: a failed install means every shot below is of the OLD binary.
xcrun simctl install "$UDID" "$APP_PATH" || { echo "❌ install failed — refusing to shoot a stale build" >&2; exit 1; }
xcrun simctl status_bar "$UDID" override --time "9:41" --cellularMode active --cellularBars 4 \
  --wifiMode active --wifiBars 3 --batteryState charged --batteryLevel 100 2>/dev/null

# One throwaway launch. After another app's simulator run, iOS shows a "◀ AppName" return
# breadcrumb in the status bar that survives into the FIRST launch only — shot 01 would ship with
# somebody else's product name on it.
xcrun simctl launch "$UDID" "$BUNDLE" >/dev/null 2>&1 || true
sleep 4
xcrun simctl terminate "$UDID" "$BUNDLE" 2>/dev/null || true
sleep 1

MARKERS=$(mktemp)
xcrun simctl spawn "$UDID" log stream --style compact \
  --predicate 'eventMessage CONTAINS "SCENARIO_"' > "$MARKERS" 2>/dev/null &
LOG_PID=$!
trap 'kill $LOG_PID 2>/dev/null; rm -f "$MARKERS"' EXIT
for _ in $(seq 1 30); do [ -s "$MARKERS" ] && break; sleep 0.5; done

echo "▶ running the scenario"
xcrun simctl launch "$UDID" "$BUNDLE" -TAROT_SCENARIO "$SCENARIO" -AppleLanguages "(en)" >/dev/null

# T0 is emitted only after the launch curtain has dissolved, so it is the first frame of the
# loaded app — the same anchor the reel capture trims against.
T0=""
for _ in $(seq 1 240); do
  if grep -q "SCENARIO_T0" "$MARKERS" 2>/dev/null; then T0=$(date +%s.%N); break; fi
  sleep 0.25
done
[ -n "$T0" ] || { echo "❌ the scenario never started — no SCENARIO_T0" >&2; exit 1; }
echo "  T0 seen"

FAILED=0
for SHOT in "${SHOTS[@]}"; do
  IFS='|' read -r NAME AT <<<"$SHOT"
  # Absolute deadlines against T0, so a slow screenshot never pushes the next shot late.
  while :; do
    NOW=$(date +%s.%N)
    REMAIN=$(echo "$T0 + $AT - $NOW" | bc -l)
    [ "$(echo "$REMAIN <= 0" | bc -l)" = "1" ] && break
    sleep "$(echo "if ($REMAIN > 0.4) 0.4 else $REMAIN" | bc -l)"
  done
  xcrun simctl io "$UDID" screenshot "$RAW/$NAME.png" >/dev/null 2>&1
  if valid "$RAW/$NAME.png"; then echo "  ✓ $NAME (t+${AT}s)"; else echo "  ✗ $NAME"; FAILED=1; fi
done

kill $LOG_PID 2>/dev/null
xcrun simctl terminate "$UDID" "$BUNDLE" 2>/dev/null
xcrun simctl status_bar "$UDID" clear 2>/dev/null
[ "$FAILED" = 0 ] || { echo "❌ at least one capture did not render — not framing a bad set" >&2; exit 1; }

PARAMS="$APP_DIR/marketing/aso/$LOC/$PLATFORM/params.yaml"
if [ -f "$PARAMS" ]; then
  echo "▶ framing"
  ( cd "$ROOT/marketing" && "$PY" generate_screenshots.py "$PARAMS" ) || exit 1
  echo "✅ $APP_DIR/marketing/aso/$LOC/$PLATFORM/"
else
  echo "⚠ no params at $PARAMS — raws are in $RAW"
fi

# One simulator per app, deleted when the run ends: concurrent sessions capture in their own.
if [ "${KEEP_SIM:-0}" != 1 ]; then
  xcrun simctl shutdown "$UDID" 2>/dev/null
  xcrun simctl delete "$UDID" && echo "▶ $SIM_NAME deleted"
fi
