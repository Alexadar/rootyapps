#!/usr/bin/env bash
#
# make_mac_shots.sh — capture Mac window screenshots of Overtone Lab and frame them
# for the Mac App Store (2880×1800 → marketing/aso/mac/2880x1800/).
#
# Needs (grant your Terminal once, System Settings › Privacy & Security):
#   • Screen Recording  — for `screencapture`
# Window geometry is read via Quartz (no Accessibility/Automation needed), so this works
# from a plain shell. Each tool is a fresh launch (force-killed between) so the deep-link
# env (OVERTONELAB_TOOL) actually takes effect.
#
set -euo pipefail
ROOT=/Users/oleksandr/Projects/rootyapps
APP_DIR="$ROOT/overtonelab.swift"
PY=/Users/oleksandr/miniconda3/envs/fantastic/bin/python
MACBIN="$APP_DIR/build/dd-mac/Build/Products/Debug/overtonelab.swift.app/Contents/MacOS/overtonelab.swift"
RAW="$APP_DIR/marketing/raw/mac"; mkdir -p "$RAW"; rm -f "$RAW"/*.png

[ -x "$MACBIN" ] || ( cd "$APP_DIR" && xcodegen generate >/dev/null && \
  xcodebuild -scheme overtonelab.swift -destination 'platform=macOS' -derivedDataPath build/dd-mac build >/dev/null )

kill_app(){ pkill -9 -f "MacOS/overtonelab.swift" 2>/dev/null || true
  for _ in 1 2 3 4 5; do pgrep -f "MacOS/overtonelab.swift" >/dev/null || break; sleep 0.5; done; }

capture(){  # 01_name  toolRawValue
  kill_app; sleep 0.8
  OVERTONELAB_TOOL="$2" "$MACBIN" >/dev/null 2>&1 & sleep 3.2
  local wid
  wid=$("$PY" -c "
import Quartz
wl=Quartz.CGWindowListCopyWindowInfo(Quartz.kCGWindowListOptionOnScreenOnly|Quartz.kCGWindowListExcludeDesktopElements,Quartz.kCGNullWindowID)
print(next((int(w['kCGWindowNumber']) for w in wl if w.get('kCGWindowOwnerName','')=='Overtone Lab' and w.get('kCGWindowName','')), ''))")
  [ -n "$wid" ] && screencapture -o -l "$wid" "$RAW/$1.png" && echo "  ✓ $1"
}

echo "▶ capturing Mac windows"
capture 01_pitch     pitch
capture 02_sabine    sabine
capture 03_thiele    thiele
capture 04_benchmark benchmark
kill_app

echo "▶ framing (2880×1800)"
( cd "$ROOT/marketing" && "$PY" generate_screenshots.py "$APP_DIR/marketing/aso/mac/params.yaml" )
echo "done → $APP_DIR/marketing/aso/mac/2880x1800/"
