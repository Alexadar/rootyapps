#!/usr/bin/env bash
#
# make_mac_shots.sh — Mac window screenshots of Tarot, framed for the Mac App Store
# (→ marketing/aso/en/mac/<WxH>/).
#
# Needs, once, System Settings › Privacy & Security › Screen Recording for the terminal this runs
# from. It does NOT need Accessibility or Automation: the window is captured through
# ScreenCaptureKit by pid, never through AppleScript, and the app is launched with `open -n -g`
# so it never takes the foreground. A capture run must not move the user's focus.
#
# ONE launch, five stills, timed from the app's own SCENARIO_T0 marker.
#
# The first version launched five times with a fixed SETTLE measured from launch, and the frames
# drifted off their captions: Mac launch overhead is variable and larger than the estimate, so the
# 4.6 s "menu with the question typed" shot actually landed on the draw screen three seconds
# later. SETTLE cannot fix that — the thing it measures from is the thing that varies. T0 is
# emitted by the app after its launch curtain dissolves, so every offset below is measured from a
# moment the app defines, exactly as the simulator shot script does.
set -uo pipefail

ROOT=/Users/oleksandr/Projects/rootyapps
APP_DIR="$ROOT/tarot"
PY=/Users/oleksandr/miniconda3/envs/fantastic/bin/python
SHOOTER="$ROOT/marketing/tools/capturewindow"
SCENARIO="${SCENARIO:-will-i-be-rich}"
DERIVED="$APP_DIR/.build/dd-mac"
APPBUNDLE="$DERIVED/Build/Products/Debug/Tarot.app"
RAW="$APP_DIR/marketing/raw/en/mac"

# Same beats as the phone and iPad sets, so all three listings show the same five moments.
SHOTS=(
  "01_table|2.2"
  "02_draw|8.6"
  "03_spread|12.6"
  "04_reading|22.0"
  "05_synthesis|40.0"
)

mkdir -p "$RAW"
rm -f "$RAW"/*.png    # nothing downstream deletes; a leftover shifts every caption by one

[ -x "$SHOOTER" ] || { echo "building capturewindow…"; swiftc -O "$ROOT/marketing/tools/CaptureWindow.swift" -o "$SHOOTER"; }

echo "▶ building the Mac app"
( cd "$APP_DIR" && xcodegen generate >/dev/null && \
  xcodebuild -project tarot.xcodeproj -scheme tarot -destination 'platform=macOS' \
    -derivedDataPath "$DERIVED" build >/dev/null 2>&1 ) || { echo "❌ build failed" >&2; exit 1; }
[ -d "$APPBUNDLE" ] || { echo "❌ no app at $APPBUNDLE" >&2; exit 1; }

valid() { "$PY" - "$1" <<'PYEOF'
import sys
from PIL import Image
import numpy as np
a = np.asarray(Image.open(sys.argv[1]).convert("L")).astype(float)
mean, std = a.mean(), a.std()
ok = mean < 150 and std > 8
print(f"    mean={mean:.1f} std={std:.1f} -> {'ok' if ok else 'REJECT'}", file=sys.stderr)
sys.exit(0 if ok else 1)
PYEOF
}

MARKERS=$(mktemp)
log stream --style compact --predicate 'eventMessage CONTAINS "SCENARIO_"' > "$MARKERS" 2>/dev/null &
LOG_PID=$!
cleanup() { kill "$LOG_PID" 2>/dev/null; [ -n "${PID:-}" ] && kill "$PID" 2>/dev/null; rm -f "$MARKERS"; }
trap cleanup EXIT
sleep 2

echo "▶ launching (backgrounded — this will not take your focus)"
# `|| true`: pgrep exits 1 when nothing matches, which is the normal case, and pipefail would
# otherwise abort the script before it launched anything.
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

T0=""
for _ in $(seq 1 240); do
  if grep -q "SCENARIO_T0" "$MARKERS" 2>/dev/null; then T0=$(date +%s.%N); break; fi
  sleep 0.25
done
[ -n "$T0" ] || { echo "❌ the scenario never started — no SCENARIO_T0" >&2; exit 1; }
echo "  T0 seen (pid $PID)"

FAILED=0
for SHOT in "${SHOTS[@]}"; do
  IFS='|' read -r NAME AT <<<"$SHOT"
  # Absolute deadlines against T0, so a slow capture never pushes the next shot late.
  while :; do
    REMAIN=$(echo "$T0 + $AT - $(date +%s.%N)" | bc -l)
    [ "$(echo "$REMAIN <= 0" | bc -l)" = "1" ] && break
    sleep "$(echo "if ($REMAIN > 0.3) 0.3 else $REMAIN" | bc -l)"
  done
  "$SHOOTER" --pid "$PID" --out "$RAW/$NAME.png" --largest >/dev/null 2>&1
  if [ -f "$RAW/$NAME.png" ] && valid "$RAW/$NAME.png"; then
    echo "  ✓ $NAME (T0+${AT}s)"
  else
    echo "  ✗ $NAME"; FAILED=1
  fi
done

kill "$PID" 2>/dev/null; PID=""
[ "$FAILED" = 0 ] || { echo "❌ at least one capture did not render — not framing a bad set" >&2; exit 1; }

PARAMS="$APP_DIR/marketing/aso/en/mac/params.yaml"
if [ -f "$PARAMS" ]; then
  echo "▶ framing"
  ( cd "$ROOT/marketing" && "$PY" generate_screenshots.py "$PARAMS" ) || exit 1
  echo "✅ $APP_DIR/marketing/aso/en/mac/"
else
  echo "⚠ no params at $PARAMS — raws are in $RAW"
fi
