#!/usr/bin/env bash
#
# score_ios.sh — mux a music bed into the framed iOS preview and produce the App Store upload.
#
# Split from capture_ios.sh on purpose: the bed can be re-picked without re-recording the app.
#   BED=marketing/audio/<bed>.wav marketing/reels/score_ios.sh
#
# App Store Connect REJECTS a preview with no audio track ("unsupported or corrupted audio"),
# so the scored _music.mp4 — not the silent framed_preview — is the file to upload.
set -euo pipefail

APP_DIR="/Users/oleksandr/Projects/rootyapps/eartharound.swift"
LOC="${1:-en}"
BED="${BED:-$APP_DIR/marketing/audio/bed30_space_aurora.wav}"
# The bed is language-agnostic: every locale is scored with the SAME generated audio, so no
# existing bed is regenerated or overwritten (its prompt/seed live beside it in audio/*.txt).
V="${V:-$APP_DIR/marketing/aso/$LOC/ios/video/framed_preview_886x1920.mp4}"
OUT="${V%.mp4}_music.mp4"

[ -f "$BED" ] || { echo "❌ bed not found: $BED"; exit 1; }
[ -f "$V" ]   || { echo "❌ preview not found: $V (run capture_ios.sh first)"; exit 1; }

DUR=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$V")
FADE_OUT=$(echo "$DUR - 1.8" | bc -l)

# loudnorm first: the raw generations peak near 0 dBFS, and the bed must sit UNDER the app,
# not compete with it. -16 LUFS is the streaming-ish target; volume 0.7 keeps it a bed.
ffmpeg -y -loglevel error -i "$V" -i "$BED" \
  -filter_complex "[1:a]atrim=0:${DUR},asetpts=PTS-STARTPTS,\
loudnorm=I=-16:TP=-1.5:LRA=11,\
afade=t=in:st=0:d=1.0,afade=t=out:st=${FADE_OUT}:d=1.8,volume=0.7[a]" \
  -map 0:v -map "[a]" -c:v copy -c:a aac -b:a 256k -ar 44100 -movflags +faststart "$OUT"

echo "✅ scored: $OUT"
ffprobe -v error -show_entries format=duration -of csv=p=0 "$OUT" | awk '{printf "   duration: %.2fs (Apple cap 30s)\n", $1}'
ffprobe -v error -show_entries stream=codec_type,codec_name -of csv=p=0 "$OUT" | sed 's/^/   stream: /'
