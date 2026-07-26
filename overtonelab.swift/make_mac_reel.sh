#!/usr/bin/env bash
#
# make_mac_reel.sh — Mac app-preview reel (1920×1080), captured the CORRECT way.
#
# macOS window video must use ScreenCaptureKit (SCContentFilter desktopIndependentWindow) —
# it records ONLY the target window, occlusion-proof, no other windows. ffmpeg/avfoundation
# can only grab a whole display, so other windows leak in. tools/RecordWindow.swift wraps SCK.
#
# Needs Screen Recording permission for your Terminal.
#
set -euo pipefail
ROOT=/Users/oleksandr/Projects/rootyapps
APP_DIR="$ROOT/overtonelab.swift"
PY=/Users/oleksandr/miniconda3/envs/fantastic/bin/python
MACBIN="$APP_DIR/build/dd-mac/Build/Products/Debug/Overtone Lab.app/Contents/MacOS/Overtone Lab"
REC="$APP_DIR/tools/recordwindow"
CLIPS=/tmp/otl_macclips; rm -rf "$CLIPS"; mkdir -p "$CLIPS"
BED="$APP_DIR/marketing/audio/jazz_groove.wav"
OUT="$APP_DIR/marketing/aso/mac/video"; mkdir -p "$OUT"

# build the app + the SCK recorder if needed
[ -x "$MACBIN" ] || ( cd "$APP_DIR" && xcodegen generate >/dev/null && \
  xcodebuild -scheme overtonelab.swift -destination 'platform=macOS' -derivedDataPath build/dd-mac build >/dev/null )
[ -x "$REC" ] || ( cd "$APP_DIR/tools" && swiftc -O RecordWindow.swift -o recordwindow )

kill_app(){ pkill -9 -f "MacOS/Overtone Lab" 2>/dev/null || true
  for _ in 1 2 3 4 5; do pgrep -f "MacOS/Overtone Lab" >/dev/null || break; sleep 0.4; done; }
rec(){  # clip  tool  [demo]
  kill_app; sleep 0.7
  OVERTONELAB_DEMO="${3:-}" OVERTONELAB_TOOL="$2" "$MACBIN" >/dev/null 2>&1 & sleep 3.3
  local wid
  wid=$("$PY" -c "
import Quartz
wl=Quartz.CGWindowListCopyWindowInfo(Quartz.kCGWindowListOptionOnScreenOnly|Quartz.kCGWindowListExcludeDesktopElements,Quartz.kCGNullWindowID)
print(next((int(w['kCGWindowNumber']) for w in wl if w.get('kCGWindowOwnerName','')=='Overtone Lab' and w.get('kCGWindowName','')),''))")
  "$REC" "$wid" 5.5 "$CLIPS/macclip_$1.mov" && echo "  ✓ $1"
}

echo "▶ recording windows (ScreenCaptureKit)"
rec tempo     tempo     1     # demo sweep → live recompute
rec sabine    sabine
rec benchmark benchmark
kill_app

echo "▶ assembling"
( cd "$ROOT/marketing" && "$PY" reels/mac_frame_reel.py \
    --scenes reels/overtonelab_scenes_mac.json --clips-dir "$CLIPS" \
    --app-dir "$APP_DIR" --out-dir "$OUT" )

V="$OUT/framed_preview_1920x1080.mp4"
DUR=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$V")
ffmpeg -y -i "$V" -i "$BED" -filter_complex \
  "[1:a]atrim=0:${DUR},asetpts=PTS-STARTPTS,afade=t=in:st=0:d=0.6,afade=t=out:st=$(echo "$DUR-1.5"|bc):d=1.5,volume=0.85[a]" \
  -map 0:v -map "[a]" -c:v copy -c:a aac -b:a 256k -ar 44100 -movflags +faststart "${V%.mp4}_music.mp4"
echo "done → ${V%.mp4}_music.mp4"
