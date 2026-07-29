#!/usr/bin/env bash
#
# remux_beds.sh — re-score every already-rendered store preview with the current music bed.
#
# Re-muxes rather than re-renders: the video is stream-copied, so this is seconds per file and
# cannot disturb footage that has already been verified frame by frame.
#
# The filter chain is a deliberate copy of the one in marketing/reels/store_preview.py — if that
# changes, change it here too, or reels scored by the pipeline and reels scored by this script
# will differ in a way nobody notices until someone unmutes two of them back to back.
set -uo pipefail

APP_DIR=/Users/oleksandr/Projects/rootyapps/ephemeris.swift
BED="${BED:-$APP_DIR/marketing/audio/bed30_appstore.wav}"
[ -s "$BED" ] || { echo "❌ no bed at $BED" >&2; exit 1; }
echo "bed: $BED"

n=0
# Only the video-only variants are sources; *_music.mp4 are outputs and must not be re-fed.
while IFS= read -r V; do
  case "$V" in *_music.mp4) continue ;; esac
  DUR=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$V") || continue
  OUT="${V%.mp4}_music.mp4"
  ffmpeg -y -v error -i "$V" -i "$BED" \
    -filter_complex "[1:a]atrim=0:${DUR},asetpts=PTS-STARTPTS,afade=t=in:st=0:d=0.6,afade=t=out:st=$(echo "$DUR-1.5"|bc):d=1.5,volume=0.85[a]" \
    -map 0:v -map "[a]" -c:v copy -c:a aac -b:a 256k -ar 44100 -movflags +faststart "$OUT" || continue
  # An upload without a valid AAC track is rejected as "unsupported or corrupted audio".
  if ffprobe -v error -show_entries stream=codec_type -of csv=p=0 "$OUT" | grep -q audio; then
    echo "  ✓ ${OUT#$APP_DIR/marketing/aso/}"
    n=$((n+1))
  else
    echo "  ❌ ${OUT#$APP_DIR/marketing/aso/} has no audio stream"
  fi
done < <(find "$APP_DIR/marketing/aso" -name "store_preview_*.mp4" | sort)

echo "re-scored $n files"
