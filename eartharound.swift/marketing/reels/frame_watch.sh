#!/usr/bin/env bash
#
# frame_watch.sh — turn the raw watch walkthrough into a presentable clip.
#
# Same treatment as the iPhone reel (caption band per beat + branded outro), deliberately
# WITHOUT a title card: an intro pane burns the opening seconds, which is exactly where
# social viewers leave. Branding goes at the end.
#
# Canvas is small on purpose (540x960): the watch captures at its native 416x496, so a
# phone-sized canvas would upscale it ~2x and go soft.
#
# Output is for the site and social ONLY — App Store Connect has no watchOS preview slot.
set -euo pipefail

ROOT="/Users/oleksandr/Projects/rootyapps"
APP_DIR="$ROOT/eartharound.swift"
PYBIN="${PYBIN:-/Users/oleksandr/miniconda3/envs/fantastic/bin/python}"
SCENES="$APP_DIR/marketing/reels/scenes_watch.json"
VIDEO_DIR="$APP_DIR/marketing/aso/watch/video"
SRC="$VIDEO_DIR/full.mp4"
DERIVED="$APP_DIR/.build/watch-dd"
BED="${BED:-$APP_DIR/marketing/audio/bed30_space_aurora.wav}"

[ -f "$SRC" ] || { echo "❌ $SRC missing — run capture_watch.sh first"; exit 1; }
mkdir -p "$DERIVED"

# The sim encoder drops frames, so the wall-clock tour is longer than the footage. The three
# beats are equal length by construction, so fit them to whatever was actually captured.
DUR=$("$PYBIN" -c "import subprocess,sys;print(subprocess.run(['ffprobe','-v','error','-show_entries','format=duration','-of','csv=p=0','$SRC'],capture_output=True,text=True).stdout.strip())")
"$PYBIN" - "$SCENES" "$DUR" "$DERIVED/scenes_watch.runtime.json" <<'PY'
import json, sys
cfg, dur, out = json.load(open(sys.argv[1])), float(sys.argv[2]), sys.argv[3]
n = len(cfg["scenes"])
for i, s in enumerate(cfg["scenes"]):
    s["start"] = round(dur * i / n, 3)
    s["end"] = round(dur * (i + 1) / n, 3)
cfg["content_len"] = round(dur, 3)
json.dump(cfg, open(out, "w"), indent=2)
print(f"fitted {n} beats to {dur:.2f}s of footage")
PY

"$PYBIN" "$ROOT/marketing/reels/frame_reel.py" \
  --scenes "$DERIVED/scenes_watch.runtime.json" --video "$SRC" \
  --app-dir "$APP_DIR" --out-dir "$VIDEO_DIR"

W=$("$PYBIN" -c "import json;print(json.load(open('$SCENES'))['canvas'][0])")
H=$("$PYBIN" -c "import json;print(json.load(open('$SCENES'))['canvas'][1])")
FRAMED="$VIDEO_DIR/framed_preview_${W}x${H}.mp4"
OUT="${FRAMED%.mp4}_music.mp4"
DUR2=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$FRAMED")
FADE=$("$PYBIN" -c "print(max(0.2, $DUR2 - 1.6))")

ffmpeg -y -loglevel error -i "$FRAMED" -i "$BED" \
  -filter_complex "[1:a]atrim=0:${DUR2},asetpts=PTS-STARTPTS,\
loudnorm=I=-16:TP=-1.5:LRA=11,afade=t=in:st=0:d=0.8,afade=t=out:st=${FADE}:d=1.6,volume=0.7[a]" \
  -map 0:v -map "[a]" -c:v copy -c:a aac -b:a 256k -ar 44100 -movflags +faststart "$OUT"

echo
echo "✅ framed watch clip: $OUT  $(ffprobe -v error -show_entries format=duration -of csv=p=0 "$OUT")s"
echo "   web/social only — ASC has no watchOS preview slot."
