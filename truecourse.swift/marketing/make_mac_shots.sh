#!/bin/bash
# TrueCourse — macOS App Store screenshots (native window capture).
#   bash marketing/make_mac_shots.sh
set -euo pipefail

ROOT=/Users/oleksandr/Projects/rootyapps
APP_DIR="$ROOT/truecourse.swift"
PY=/Users/oleksandr/miniconda3/envs/fantastic/bin/python
MACBIN="$APP_DIR/build/dd-mac/Build/Products/Debug/TrueCourse.app/Contents/MacOS/TrueCourse"
RAW="$APP_DIR/marketing/raw/mac"; mkdir -p "$RAW"; rm -f "$RAW"/*.png

[ -x "$MACBIN" ] || ( cd "$APP_DIR" && xcodegen generate >/dev/null && \
  xcodebuild -scheme truecourse.swift -destination 'platform=macOS' -derivedDataPath build/dd-mac build >/dev/null )

kill_app(){ pkill -9 -f "MacOS/TrueCourse" 2>/dev/null || true
  for _ in 1 2 3 4 5; do pgrep -f "MacOS/TrueCourse" >/dev/null || break; sleep 0.5; done; }

capture(){  # 01_name  tool  screen(optional)
  kill_app; sleep 0.8
  TRUECOURSE_SCREEN="${3:-0}" TRUECOURSE_TOOL="$2" "$MACBIN" >/dev/null 2>&1 & sleep 3.2
  local wid
  wid=$("$PY" -c "
import Quartz
wl=Quartz.CGWindowListCopyWindowInfo(Quartz.kCGWindowListOptionOnScreenOnly|Quartz.kCGWindowListExcludeDesktopElements,Quartz.kCGNullWindowID)
print(next((int(w['kCGWindowNumber']) for w in wl if w.get('kCGWindowOwnerName','')=='TrueCourse' and w.get('kCGWindowName','')), ''))")
  [ -n "$wid" ] && screencapture -o -l "$wid" "$RAW/$1.png" && echo "  ✓ $1"
}

capture 01_wind     wind     0
capture 02_airspeed airspeed 0
capture 03_wb       wb       1
capture 04_convert  convert  0
kill_app

echo "Framing…"
( cd "$ROOT/marketing" && "$PY" generate_screenshots.py "$APP_DIR/marketing/aso/mac/params.yaml" )
echo "Done → $APP_DIR/marketing/aso/mac/"
