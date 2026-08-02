#!/usr/bin/env bash
# All preview reels: iPhone, iPad, Mac, watch × en/de/ja/fr/es.
#
# Absolute cd, not `dirname "$0"`: this gets launched from whatever directory the caller happens
# to be in, and a relative resolution silently put it one level above reels/ — every script then
# reported "No such file or directory" and the whole run exited in seconds having recorded nothing.
#
# English IS re-recorded now. The old exemption ("English copy did not change") only ever covered
# STRINGS — on 2026-07-28 the Simple/Extended toggle was removed from the app, so every reel shot
# before that date shows a control that no longer exists, in every locale including English. The
# scored bed is untouched by this: capture re-records the footage, score_ios re-muxes the SAME
# audio/bed30_space_aurora.wav, and no bed is regenerated.
#
# Strictly sequential — each capture records real time, so a job running alongside drops frames.
set -uo pipefail
cd /Users/oleksandr/Projects/rootyapps/eartharound.swift/marketing || exit 1

for loc in en de ja fr es; do
  echo "=== iPhone reel $loc"
  ./reels/capture_ios.sh "$loc" 2>&1 | tail -2
  ./reels/score_ios.sh "$loc" 2>&1 | tail -1
done
for loc in en de ja fr es; do
  echo "=== iPad reel $loc"
  PLATFORM=ipad ./reels/capture_ios.sh "$loc" 2>&1 | tail -2
  V="$PWD/aso/$loc/ipad/video/framed_preview_1200x1600.mp4" ./reels/score_ios.sh "$loc" 2>&1 | tail -1
done
for loc in en de ja fr es; do
  echo "=== Mac reel $loc"
  ./reels/capture_mac.sh "$loc" 2>&1 | tail -2
  V="$PWD/aso/$loc/mac/video/framed_preview_1920x1080.mp4" ./reels/score_ios.sh "$loc" 2>&1 | tail -1
done
for loc in en de ja fr es; do
  echo "=== watch reel $loc"
  ./reels/capture_watch.sh "$loc" 2>&1 | tail -2
  ./reels/frame_watch.sh "$loc" 2>&1 | tail -1
done
echo "ALL REELS DONE"
