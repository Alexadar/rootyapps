#!/bin/bash
# TrueCourse — macOS app-preview reel via ScreenCaptureKit single-window recording.
# Records per-tool window clips, composites landscape scenes + outro (mac_frame_reel.py).
# Needs Screen Recording permission for the terminal running this.
set -euo pipefail

ROOT=/Users/oleksandr/Projects/rootyapps
APP_DIR="$ROOT/truecourse.swift"
PY=/Users/oleksandr/miniconda3/envs/fantastic/bin/python
MACBIN="$APP_DIR/build/dd-mac/Build/Products/Debug/TrueCourse.app/Contents/MacOS/TrueCourse"
REC="$APP_DIR/tools/recordwindow"
CLIPS=/tmp/tc_macclips; rm -rf "$CLIPS"; mkdir -p "$CLIPS"
OUT="$APP_DIR/marketing/aso/mac/video"; mkdir -p "$OUT"

[ -x "$MACBIN" ] || ( cd "$APP_DIR" && xcodegen generate >/dev/null && \
  xcodebuild -scheme truecourse.swift -destination 'platform=macOS' -derivedDataPath build/dd-mac build >/dev/null )
[ -x "$REC" ] || ( cd "$APP_DIR/tools" && swiftc -O RecordWindow.swift -o recordwindow )

kill_app(){ pkill -9 -f "MacOS/TrueCourse" 2>/dev/null || true
  for _ in 1 2 3 4 5; do pgrep -f "MacOS/TrueCourse" >/dev/null || break; sleep 0.5; done; }

rec(){  # clip  tool  screen  demo
  kill_app; sleep 0.7
  TRUECOURSE_DEMO="${4:-}" TRUECOURSE_SCREEN="${3:-0}" TRUECOURSE_TOOL="$2" "$MACBIN" >/dev/null 2>&1 & sleep 3.3
  local wid
  wid=$("$PY" -c "
import Quartz
wl=Quartz.CGWindowListCopyWindowInfo(Quartz.kCGWindowListOptionOnScreenOnly|Quartz.kCGWindowListExcludeDesktopElements,Quartz.kCGNullWindowID)
print(next((int(w['kCGWindowNumber']) for w in wl if w.get('kCGWindowOwnerName','')=='TrueCourse' and w.get('kCGWindowName','')),''))")
  [ -n "$wid" ] && "$REC" "$wid" 5.5 "$CLIPS/macclip_$1.mov" && echo "  ✓ $1"
}

rec wind     wind     0 1        # demo sweep → live wind triangle
rec airspeed airspeed 0
rec wb       wb       1          # envelope screen (CG chart)
kill_app

echo "Compositing…"
( cd "$ROOT/marketing" && "$PY" reels/mac_frame_reel.py \
    --scenes "$APP_DIR/marketing/reels/scenes_mac.json" --clips-dir "$CLIPS" \
    --app-dir "$APP_DIR" --out-dir "$OUT" )
echo "Mac reel → $OUT/framed_preview_1920x1080.mp4"
