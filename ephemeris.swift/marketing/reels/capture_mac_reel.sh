#!/usr/bin/env bash
#
# capture_mac_reel.sh [locale …] — macOS App Store preview, per locale.
#
#   ./capture_mac_reel.sh de fr ja
#
# Unlike the iPhone/iPad reel there is no XCUITest tour: the Mac cut is assembled from one short
# clip per tab, and the tab is chosen by EPHEMERIS_TAB at launch. That makes it immune to the bug
# that ruined the localized phone reels — no element is ever looked up by its (translated) label.
#
# Recording uses ScreenCaptureKit via `recordwindow --pid`, never `ffmpeg -f avfoundation`:
# avfoundation can only grab a whole display, so the terminal, the dock and any window the user
# touches leak into the "app preview". SCK records the window's OWN composited content, so the
# app never has to be frontmost — which is why every launch here is backgrounded.
#
# Two traps, both handled below and both documented in marketing/reels/README.md:
#   • SwiftUI apps are single-instance — relaunching just refocuses the old window and DROPS the
#     new env, so the tab would never change. pkill -9 and wait for the process to die.
#   • Screen Recording permission must be granted to the calling terminal once, or SCK silently
#     records black frames.
set -uo pipefail

ROOT=/Users/oleksandr/Projects/rootyapps
APP_DIR="$ROOT/ephemeris.swift"
RECORDER="$ROOT/marketing/reels/recordwindow"
PYBIN=/Users/oleksandr/miniconda3/envs/fantastic/bin/python
CLIP_DUR="${CLIP_DUR:-5.8}"        # 5 clips -> 29s, just inside the 30s App Store cap
CANVAS_W=1920; CANVAS_H=1080

APP=$(find ~/Library/Developer/Xcode/DerivedData/ephemeris.swift-*/Build/Products/Debug \
       -maxdepth 1 -name 'Ephemeris.app' 2>/dev/null | head -1)
[ -n "$APP" ] || { echo "❌ no built Ephemeris.app — build the macOS scheme first" >&2; exit 1; }
EXEC="$APP/Contents/MacOS/Ephemeris"
[ -x "$RECORDER" ] || { echo "building recordwindow…"; swiftc -O "$ROOT/marketing/reels/RecordWindow.swift" -o "$RECORDER"; }

KEYS=(chart positions aspects cycle events)
TABS=(0 1 2 3 4)

place_for() {
  case "$1" in
    de) echo "Europe/Berlin|52.52|13.405|Berlin" ;;
    fr) echo "Europe/Paris|48.857|2.352|Paris" ;;
    ja) echo "Asia/Tokyo|35.690|139.692|Tokyo" ;;
    *)  echo "America/Los_Angeles|34.052|-118.244|Los Angeles" ;;
  esac
}

# macOS remembers the window frame per app, and the app is sandboxed so it lives in the
# container, not in ~/Library/Preferences. Without clearing it the reel inherits whatever size
# the last run left — including a previous reel's 1600-wide frame leaking into the user's normal
# window, and a normal 900-wide frame defeating the 16:9 reel sizing.
PREFS=~/Library/Containers/oleksandr.aisixteen.ephemeris/Data/Library/Preferences/oleksandr.aisixteen.ephemeris.plist
# cfprefsd caches the plist and rewrites it, so deleting the file alone does nothing — the
# daemon has to be told to drop it.
clear_window_frame() {
  defaults delete oleksandr.aisixteen.ephemeris 2>/dev/null
  rm -f "$PREFS" 2>/dev/null
  killall -u "$USER" cfprefsd 2>/dev/null
}
trap 'clear_window_frame' EXIT      # leave the user's normal window at its default size

for LOC in "${@:-de fr ja}"; do
  IFS='|' read -r TZ LAT LON PLACE <<<"$(place_for "$LOC")"
  CLIPS="$APP_DIR/marketing/raw/$LOC/mac/video/clips"
  ASO_DIR="$APP_DIR/marketing/aso/$LOC/mac/video"
  mkdir -p "$CLIPS" "$ASO_DIR"
  SCENES="$APP_DIR/marketing/reels/scenes_mac.json"
  [ "$LOC" = en ] || SCENES="$APP_DIR/marketing/reels/scenes_mac_$LOC.json"
  echo "=== mac / $LOC ($PLACE)"

  for i in "${!TABS[@]}"; do
    pkill -9 -f "MacOS/Ephemeris" 2>/dev/null
    while pgrep -f "MacOS/Ephemeris" >/dev/null; do sleep 0.3; done
    # -g keeps focus where the user left it; SCK does not need the window frontmost.
    EPHEMERIS_LANG="$LOC" EPHEMERIS_TAB="${TABS[$i]}" EPHEMERIS_TZ="$TZ" \
    EPHEMERIS_LAT="$LAT" EPHEMERIS_LON="$LON" EPHEMERIS_PLACE="$PLACE" EPHEMERIS_DEMO=1 \
    EPHEMERIS_REEL=1 \
      "$EXEC" >/dev/null 2>&1 &
    PID=$!
    sleep 3.3                                   # let the window lay out and the demo start
    "$RECORDER" --pid "$PID" "$CLIP_DUR" "$CLIPS/macclip_${KEYS[$i]}.mov" >/dev/null 2>&1
    kill "$PID" 2>/dev/null
    if [ -s "$CLIPS/macclip_${KEYS[$i]}.mov" ]; then echo "    ${KEYS[$i]}.mov"
    else echo "    ${KEYS[$i]}.mov ❌ EMPTY (Screen Recording permission?)"; fi
  done
  pkill -9 -f "MacOS/Ephemeris" 2>/dev/null

  # ── full-bleed walkthrough: hard cuts, so each scene's window is exactly known ──
  LIST="$CLIPS/concat.txt"; : > "$LIST"
  for k in "${KEYS[@]}"; do echo "file '$CLIPS/macclip_$k.mov'" >> "$LIST"; done
  FULL="$ASO_DIR/full.mp4"
  ffmpeg -y -v error -f concat -safe 0 -i "$LIST" \
    -vf "scale=${CANVAS_W}:${CANVAS_H}:force_original_aspect_ratio=decrease,pad=${CANVAS_W}:${CANVAS_H}:(ow-iw)/2:(oh-ih)/2:color=black,fps=30,format=yuv420p" \
    -c:v libx264 -profile:v high -crf 20 -preset medium -movflags +faststart -an "$FULL"

  # Hard cuts mean the timeline is deterministic — scene i owns [i*CLIP_DUR, (i+1)*CLIP_DUR].
  # No marker alignment needed, and no chance of the caption drift the phone reels hit.
  RUNTIME="$APP_DIR/.build/scenes-mac-$LOC.runtime.json"
  mkdir -p "$APP_DIR/.build"
  "$PYBIN" - "$SCENES" "$RUNTIME" "$CLIP_DUR" <<'PY'
import json, sys
src, dst, dur = sys.argv[1], sys.argv[2], float(sys.argv[3])
d = json.load(open(src))
for i, s in enumerate(d["scenes"]):
    s["start"], s["end"] = round(i * dur, 3), round((i + 1) * dur, 3)
d["content_len"] = round(len(d["scenes"]) * dur, 3)
d["preview_maxlen"] = 30
json.dump(d, open(dst, "w"), ensure_ascii=False, indent=2)
print(f"runtime scenes -> {dst}  ({d['content_len']}s)")
PY

  echo "▶ store preview (full-bleed, 2.3.4-compliant)"
  "$PYBIN" "$ROOT/marketing/reels/store_preview.py" \
    --scenes "$RUNTIME" --video "$FULL" --out-dir "$ASO_DIR" \
    --audio "$APP_DIR/marketing/audio/bed30_appstore.wav" --source-aspect "${CANVAS_W}x${CANVAS_H}"

  for f in "$ASO_DIR"/store_preview_*_music.mp4; do
    [ -e "$f" ] || continue
    ffprobe -v error -show_entries stream=codec_type -of csv=p=0 "$f" | grep -q audio \
      || echo "❌ $f has no audio stream — App Store Connect will reject it"
  done
done
echo "MAC REELS DONE"
