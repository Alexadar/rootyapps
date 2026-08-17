#!/usr/bin/env bash
#
# run_all_reels.sh [locale …] — every reel × iPhone + iPad, in sequence.
#
#   REELS="sky natal" ./run_all_reels.sh en de fr ja
#   REELS=natal ./run_all_reels.sh en
#
# Sequential on purpose: both platforms build into their own derived-data dir, but a simulator
# records one window at a time, and two concurrent tours would interleave.
#
# Runs on the Ephemeris-* simulators only (see capture_reel.sh) so a sibling app's capture can
# never share a device with this one.
#
# ## Two reels, not one
#
# The App Store takes three previews per device size. `sky` sells the live moment; `natal` sells
# saved birth charts — different products to a buyer, so they get their own videos rather than one
# reel trying to do both. Everything downstream is namespaced by reel id:
#
#   marketing/reels/scenes/<reel>/<iphone|ipad|mac>_<loc>.json     captions + timing
#   marketing/raw/<loc>/<ios|ipad>/video/<reel>/capture.mov        raw capture
#   marketing/aso/<loc>/<ios|ipad>/video/<reel>/                   full.mp4 + store_preview_*
#
# UPLOAD ORDER IS THE LISTING ORDER: the first preview uploaded is the one that autoplays. Decide
# deliberately which of sky/natal leads — see marketing/reels/README.md.
set -uo pipefail
cd "$(dirname "$0")"

REELS=(${REELS:-sky natal})
LOCALES=("${@:-de fr ja}")
[ $# -gt 0 ] && LOCALES=("$@")

for REEL in "${REELS[@]}"; do
  for LOC in "${LOCALES[@]}"; do
    for PLAT in ios ipad; do
      echo "================ $REEL · $PLAT / $LOC  ($(date +%H:%M:%S))"
      if REEL=$REEL PLATFORM=$PLAT ./capture_reel.sh "$LOC" 2>&1 | tail -30; then :; fi
    done
  done
done
echo "ALL REELS DONE $(date +%H:%M:%S)"
