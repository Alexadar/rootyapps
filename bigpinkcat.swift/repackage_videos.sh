#!/usr/bin/env bash
# repackage_videos.sh
# Usage:
#   ./repackage_videos.sh check <dir>          # list video codec info (ffprobe)
#   ./repackage_videos.sh repackage <dir>      # produce *_fixed.mp4 next to originals
#   ./repackage_videos.sh repackage <dir> --in-place  # overwrite originals (safe: uses temp then move)
#   ./repackage_videos.sh single <file> [--in-place]
#
# Places: call with directory that contains output_story/video (it will recurse).
# Requires: ffmpeg and ffprobe on PATH.
set -euo pipefail

PROG="$(basename "$0")"
FFMPEG="$(command -v ffmpeg || true)"
FFPROBE="$(command -v ffprobe || true)"

if [ -z "$FFMPEG" ] || [ -z "$FFPROBE" ]; then
  echo "ffmpeg and ffprobe are required and must be on PATH."
  echo "Install via brew: brew install ffmpeg"
  exit 2
fi

print_usage() {
  cat <<EOF
$PROG - Repackage videos to H.264 (baseline) + AAC
Usage:
  $PROG check <dir>
  $PROG repackage <dir> [--in-place]
  $PROG single <file> [--in-place]
EOF
}

# Print codec info for every mp4/mov under a directory
cmd_check() {
  local dir="$1"
  find "$dir" -type f \( -iname '*.mp4' -o -iname '*.mov' \) -print0 | while IFS= read -r -d '' f; do
    printf "\n== %s ==\n" "$f"
    "$FFPROBE" -v error -show_entries format=format_name,duration:stream=index,codec_type,codec_name,profile,width,height -of default=noprint_wrappers=1:nokey=1 "$f"
  done
}

# Repackage a single file -> output path. If in_place true then replace original.
repackage_file() {
  local src="$1"
  local in_place="${2:-false}"
  if [ ! -f "$src" ]; then
    echo "File not found: $src" >&2
    return 1
  fi

  local base="${src%.*}"
  local out="${base}_fixed.mp4"

  # If user requested in-place, create tmp file then move to original name (preserve extension as mp4)
  if [ "$in_place" = "true" ]; then
    out="$(mktemp "${base}.XXXXXX.mp4")"
  fi

  echo "Repackaging: $src -> $out"
  # Recommended safe ffmpeg options for compatibility:
  # - libx264 baseline profile, yuv420p pixel format, movflags+faststart for progressive start
  "$FFMPEG" -hide_banner -y -i "$src" \
    -c:v libx264 -profile:v baseline -level 3.0 -pix_fmt yuv420p -preset medium -crf 20 \
    -c:a aac -b:a 128k -movflags +faststart "$out"

  if [ "$in_place" = "true" ]; then
    # Overwrite original atomically
    mv -f "$out" "${base}.mp4"
    echo "Replaced original with ${base}.mp4"
  else
    echo "Created: $out"
  fi
}

# Repackage recursively
cmd_repackage() {
  local dir="$1"
  local in_place="${2:-false}"
  find "$dir" -type f \( -iname '*.mp4' -o -iname '*.mov' \) -print0 | while IFS= read -r -d '' f; do
    repackage_file "$f" "$in_place"
  done
}

if [ $# -lt 2 ]; then
  print_usage
  exit 1
fi

action="$1"
target="$2"
case "$action" in
  check)
    cmd_check "$target"
    ;;
  repackage)
    in_place_flag="false"
    if [ "${3:-}" = "--in-place" ]; then
      in_place_flag="true"
    fi
    cmd_repackage "$target" "$in_place_flag"
    ;;
  single)
    in_place_flag="false"
    if [ "${3:-}" = "--in-place" ]; then
      in_place_flag="true"
    fi
    repackage_file "$target" "$in_place_flag"
    ;;
  *)
    print_usage
    exit 1
    ;;
esac
