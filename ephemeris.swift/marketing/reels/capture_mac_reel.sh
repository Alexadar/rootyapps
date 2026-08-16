#!/usr/bin/env bash
#
# capture_mac_reel.sh [locale …] — macOS App Store preview, per locale.
#
#   ./capture_mac_reel.sh de fr ja              # the sky reel
#   REEL=natal ./capture_mac_reel.sh en de      # the natal reel
#
# `REEL` defaults to sky. Everything is namespaced by reel id, matching the phone/iPad pipeline:
#
#   marketing/reels/scenes/<reel>/mac_<loc>.json          captions
#   marketing/raw/<loc>/mac/video/<reel>/clips/           one clip per screen
#   marketing/aso/<loc>/mac/video/<reel>/                 full.mp4 + store_preview_*
#
# This script pointed at `scenes_mac_<loc>.json` until now — files the two-reel reorganisation
# renamed to `scenes/sky/mac_<loc>.json`. It had been broken since, and would have failed on its
# next run rather than producing anything wrong; the Mac previews on the store are still the
# 2026-07-29 ones from before natal charts existed.
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
# sky ships 5 clips, natal 6 — each sized to land just inside the 30s App Store cap.
CLIP_DUR="${CLIP_DUR:-}"           # resolved below, once REEL is known
CANVAS_W=1920; CANVAS_H=1080

APP=$(find ~/Library/Developer/Xcode/DerivedData/ephemeris.swift-*/Build/Products/Debug \
       -maxdepth 1 -name 'Ephemeris.app' 2>/dev/null | head -1)
[ -n "$APP" ] || { echo "❌ no built Ephemeris.app — build the macOS scheme first" >&2; exit 1; }
EXEC="$APP/Contents/MacOS/Ephemeris"
[ -x "$RECORDER" ] || { echo "building recordwindow…"; swiftc -O "$ROOT/marketing/reels/RecordWindow.swift" -o "$RECORDER"; }

REEL="${REEL:-sky}"

# key | TAB | LENS | CHART | TRANSITS | FACET | PARTNER
#
# Five clips per reel, because 5 × 5.8s = 29s and the App Store cap is 30.
#
# The natal clips address the seeded fixture by UUID prefix, exactly as the screenshots do — the
# library sorts by modifiedAt and the fixtures share an instant, so a row index is not stable.
# EPHEMERIS_REEL=1 (set on every launch below, for the 1600×848 window) already seeds that library
# with invented people, so no real birth data can reach a capture.
case "$REEL" in
  sky)
    CLIPS_SPEC=(
      "chart|0|||||"
      "positions|1|||||"
      "aspects|2|||||"
      "cycle|3|||||"
      "events|4|||||"
    ) ;;
  natal)
    # Six beats rather than five, so the practitioner facets this release adds each get one.
    # CLIP_DUR drops to 4.8s below to keep 6 × dur inside the 30s App Store cap.
    CLIPS_SPEC=(
      "library|5|||||"
      "natalwheel|5|wheel|11111111||wheel|"
      "transits|5|wheel|11111111||biwheel|"
      "analysis|5|wheel|11111111||analysis|"
      "returns|5|wheel|11111111||returns|"
      "synastry|5|wheel|11111111||wheel|22222222"
    ) ;;
  *) echo "unknown REEL '$REEL' (expected sky or natal)" >&2; exit 1 ;;
esac
KEYS=()
for spec in "${CLIPS_SPEC[@]}"; do KEYS+=("${spec%%|*}"); done
# 5 × 5.8 = 29.0s, 6 × 4.8 = 28.8s.
[ -n "$CLIP_DUR" ] || CLIP_DUR=$([ "${#KEYS[@]}" -ge 6 ] && echo 4.8 || echo 5.8)

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
  CLIPS="$APP_DIR/marketing/raw/$LOC/mac/video/$REEL/clips"
  ASO_DIR="$APP_DIR/marketing/aso/$LOC/mac/video/$REEL"
  mkdir -p "$CLIPS" "$ASO_DIR"
  SCENES="$APP_DIR/marketing/reels/scenes/$REEL/mac_$LOC.json"
  [ -f "$SCENES" ] || { echo "❌ no scenes file $SCENES" >&2; exit 1; }
  echo "=== $REEL · mac / $LOC ($PLACE)"

  for i in "${!CLIPS_SPEC[@]}"; do
    IFS='|' read -r KEY TAB LENS CHART TRANSITS FACET PARTNER <<<"${CLIPS_SPEC[$i]}"
    pkill -9 -f "MacOS/Ephemeris" 2>/dev/null
    while pgrep -f "MacOS/Ephemeris" >/dev/null; do sleep 0.3; done
    ENVV=(
      EPHEMERIS_LANG="$LOC" EPHEMERIS_TAB="$TAB" EPHEMERIS_TZ="$TZ"
      EPHEMERIS_LAT="$LAT" EPHEMERIS_LON="$LON" EPHEMERIS_PLACE="$PLACE"
      EPHEMERIS_DEMO=1 EPHEMERIS_REEL=1
    )
    [ -n "$LENS" ]     && ENVV+=(EPHEMERIS_LENS="$LENS")
    [ -n "$CHART" ]    && ENVV+=(EPHEMERIS_CHART="$CHART")
    [ -n "$TRANSITS" ] && ENVV+=(EPHEMERIS_TRANSITS="$TRANSITS")
    [ -n "$FACET" ]    && ENVV+=(EPHEMERIS_FACET="$FACET")
    [ -n "$PARTNER" ]  && ENVV+=(EPHEMERIS_PARTNER="$PARTNER")
    # Backgrounded: SCK records the window's own composited content, so it never has to be
    # frontmost, and the user's focus stays where they left it.
    env "${ENVV[@]}" "$EXEC" >/dev/null 2>&1 &
    PID=$!
    sleep 3.3                                   # let the window lay out and the demo start
    "$RECORDER" --pid "$PID" "$CLIP_DUR" "$CLIPS/macclip_$KEY.mov" >/dev/null 2>&1
    kill "$PID" 2>/dev/null
    if [ -s "$CLIPS/macclip_$KEY.mov" ]; then echo "    $KEY.mov"
    else echo "    $KEY.mov ❌ EMPTY (Screen Recording permission?)"; fi
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
  # Reel id in the filename: sky and natal would otherwise overwrite each other's runtime scenes.
  RUNTIME="$APP_DIR/.build/scenes-mac-$REEL-$LOC.runtime.json"
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
