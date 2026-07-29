#!/usr/bin/env bash
#
# make_mac_reel.sh — Storypole's macOS App Store preview (1920×1080, full bleed, scored).
#
# WHY THIS IS NOT `mac_frame_reel.py`
#   `mac_frame_reel.py` composes caption-left / window-right with a gradient background. That is
#   framing, and framing is a Guideline 2.3.4 rejection for an app preview. (Apple approved
#   Overtone Lab's framed Mac preview on the same day it rejected the framed iOS one — it is still
#   non-compliant; see marketing/reels/README.md.) So the clips go through `store_preview.py`
#   instead: full bleed, captions drawn ON the app, no bezel, no letterbox, no outro.
#
# WHY 960×540 POINTS
#   Apple wants 1920×1080. The app window is not 16:9, and letterboxing it to fit would itself be
#   framing. So the window is *launched* 16:9 via STORYPOLE_WIN and, on a 2× display, records
#   natively at exactly 1920×1080.
#
# WHY ONE CLIP PER SCENE
#   SwiftUI apps are single-instance: relaunching with a new STORYPOLE_TOOL just foregrounds the
#   old window and drops the env. So each scene is a fresh `pkill` + `open -n -g` + record, and the
#   clips are concatenated afterwards. `-g` keeps every relaunch out of your face;
#   ScreenCaptureKit records the window's own composited content, so it need never be frontmost.
#
set -euo pipefail
ROOT=/Users/oleksandr/Projects/rootyapps
APP="$ROOT/storypole"
PY=/Users/oleksandr/miniconda3/envs/fantastic/bin/python
REC="$ROOT/marketing/reels/recordwindow"
BUNDLE="$APP/build/dd-mac/Build/Products/Debug/Storypole.app"
CLIPS="$APP/marketing/raw/mac/clips"; mkdir -p "$CLIPS"; rm -f "$CLIPS"/*.mov "$CLIPS"/*.mp4
OUT="$APP/marketing/aso/mac/video"; mkdir -p "$OUT"
SECS=7

[ -x "$REC" ] || { echo "building recordwindow"; swiftc -O "$ROOT/marketing/reels/RecordWindow.swift" -o "$REC"; }
[ -d "$BUNDLE" ] || ( cd "$APP" && xcodebuild -scheme storypole -destination 'platform=macOS' \
  -derivedDataPath build/dd-mac build >/dev/null )

kill_app(){ pkill -9 -f "MacOS/Storypole" 2>/dev/null || true
  for _ in 1 2 3 4 5 6; do pgrep -f "MacOS/Storypole" >/dev/null || break; sleep 0.5; done; }

clip(){  # name  tool  tab  demo
  local name="$1" tool="${2:-}" tab="${3:-}" demo="${4:-}"
  kill_app; sleep 0.7
  open -n -g "$BUNDLE" --env STORYPOLE_LANG=en --env STORYPOLE_WIN=960x540 \
                       --env STORYPOLE_TOOL="$tool" --env STORYPOLE_TAB="$tab" \
                       --env STORYPOLE_DEMO="$([ "$demo" = demo ] && echo 1 || echo 0)"
  sleep 3.4                                   # let the window settle before the first frame
  local pid; pid=$(pgrep -f "MacOS/Storypole" | head -1)
  [ -n "$pid" ] || { echo "  ✗ $name — app did not start"; return 1; }
  "$REC" --pid "$pid" "$SECS" "$CLIPS/$name.mov" >/dev/null 2>&1
  [ -s "$CLIPS/$name.mov" ] && echo "  ✓ $name" || { echo "  ✗ $name — empty clip"; return 1; }
}

echo "▶ recording scenes (backgrounded, window-specific)"
clip 1_tape      ""            0  demo
clip 2_layout    equalSpacing  ""
clip 3_lumber    dressedSize   ""
clip 4_reference ""            2
kill_app

echo "▶ conforming to 1920x1080 and concatenating"
: > "$CLIPS/list.txt"
for f in "$CLIPS"/[1-4]_*.mov; do
  ffmpeg -y -i "$f" -vf "scale=1920:1080:force_original_aspect_ratio=increase,crop=1920:1080,fps=30" \
    -an -c:v libx264 -pix_fmt yuv420p "${f%.mov}.mp4" >/dev/null 2>&1
  echo "file '${f%.mov}.mp4'" >> "$CLIPS/list.txt"
done
ffmpeg -y -f concat -safe 0 -i "$CLIPS/list.txt" -c copy "$OUT/full.mp4" >/dev/null 2>&1
DUR=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$OUT/full.mp4")
echo "  walkthrough ${DUR}s"

echo "▶ store cut (full-bleed, scored)"
"$PY" "$ROOT/marketing/reels/store_preview.py" \
  --scenes "$APP/marketing/reels/scenes_mac.json" \
  --video "$OUT/full.mp4" --out-dir "$OUT" \
  --audio "$APP/marketing/audio/bed30.wav" --source-aspect 1920x1080

echo "▶ verifying"
for f in "$OUT"/store_preview_*music.mp4; do
  [ -e "$f" ] || continue
  printf "  %-46s %s\n" "$(basename "$f")" \
    "$(ffprobe -v error -show_entries stream=codec_type,codec_name -of csv=p=0 "$f" | tr '\n' ' ')"
done
echo "done → $OUT"
