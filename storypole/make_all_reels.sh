#!/usr/bin/env bash
#
# make_all_reels.sh — capture and render Storypole's App Store previews.
#
#   ./make_all_reels.sh            iPhone 6.9" (886×1920)
#   PLATFORM=ipad ./make_all_reels.sh   iPad 13" (1200×1600)
#
# TWO RULES FROM marketing/reels/README.md THAT DECIDE WHAT SHIPS:
#
# 1. A FRAMED reel is a 2.3.4 rejection as a store preview. `frame_reel.py` output (gradient bg,
#    device bezel, outro card) is for the site and socials ONLY. The store cut comes from
#    `store_preview.py`: full-bleed, no bezel, no letterbox, no outro.
#
# 2. NEVER upload a video-only file. App Store Connect requires a valid AAC track and rejects a
#    preview without one. The scored `_music.mp4` is the default upload.
#
set -euo pipefail
ROOT=/Users/oleksandr/Projects/rootyapps
APP=$ROOT/storypole
PLATFORM="${PLATFORM:-ios}"
BED="$APP/marketing/audio/bed30.wav"

if [ "$PLATFORM" = "ipad" ]; then
  SIM_NAME="${SIM_NAME:-SP-iPad}"; SCENES="$APP/marketing/reels/scenes_ipad.json"; ASPECT=2064x2752
else
  SIM_NAME="${SIM_NAME:-SP-iPhone}"; SCENES="$APP/marketing/reels/scenes.json"; ASPECT=1320x2868
fi
# make_reel.sh writes here — NOT under a locale segment. Looking in aso/en/… made the
# store cut silently skip, and every output shipped with no audio track.
OUT="$APP/marketing/aso/$PLATFORM/video"
mkdir -p "$OUT"

echo "▶ capture walkthrough ($PLATFORM)"
APP_DIR="$APP" PROJECT=storypole.xcodeproj SCHEME=storypole \
APP_BUNDLE=oleksandr.aisixteen.storypole \
SIM_NAME="$SIM_NAME" SCENES="$SCENES" PLATFORM="$PLATFORM" \
  "$ROOT/marketing/reels/make_reel.sh"

FULL=$(find "$OUT" -name "full.mp4" | head -1)
[ -n "$FULL" ] || { echo "no walkthrough produced"; exit 1; }

echo "▶ store cut (full-bleed, scored)"
"$ROOT/marketing/venv/bin/python" "$ROOT/marketing/reels/store_preview.py" \
  --scenes "$SCENES" --video "$FULL" --out-dir "$OUT" \
  --audio "$BED" --source-aspect "$ASPECT"

echo "▶ verifying every cut carries an AAC track"
for f in "$OUT"/store_preview_*.mp4; do
  [ -e "$f" ] || continue
  codec=$(ffprobe -v error -select_streams a:0 -show_entries stream=codec_name -of csv=p=0 "$f")
  printf "  %-52s audio=%s\n" "$(basename "$f")" "${codec:-NONE}"
done
echo "done → $OUT"
