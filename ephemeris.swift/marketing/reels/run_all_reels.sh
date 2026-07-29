#!/usr/bin/env bash
#
# run_all_reels.sh [locale …] — every iPhone + iPad reel, in sequence.
#
# Sequential on purpose: both platforms build into their own derived-data dir, but a simulator
# records one window at a time, and two concurrent tours would interleave taps.
#
# Runs on the Ephemeris-* simulators only (see capture_reel.sh) so a sibling app's capture can
# never share a device with this one.
set -uo pipefail
cd "$(dirname "$0")"

LOCALES=("${@:-de fr ja}")
[ $# -gt 0 ] && LOCALES=("$@")

for LOC in "${LOCALES[@]}"; do
  for PLAT in ios ipad; do
    echo "================ $PLAT / $LOC  ($(date +%H:%M:%S))"
    if PLATFORM=$PLAT ./capture_reel.sh "$LOC" 2>&1 | tail -30; then :; fi
  done
done
echo "ALL REELS DONE $(date +%H:%M:%S)"
