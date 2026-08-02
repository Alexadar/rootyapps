#!/usr/bin/env bash
#
# finish_reels.sh — generate every remaining App Store preview.
#
# iPhone reels are regenerated too, even though the de/fr/ja ones were already verified good:
# those were driven by the old XCUITest tour, and mixing two drivers means two different pacings
# across one storefront's assets. One driver, one pacing, everywhere.
#
# Sequential: a simulator records one window at a time, and the macOS pass records the real
# desktop, so nothing here may overlap with anything else.
set -uo pipefail
cd "$(dirname "$0")"

for LOC in en de fr ja; do
  for PLAT in ios ipad; do
    echo "### $PLAT / $LOC  $(date +%H:%M:%S)"
    PLATFORM=$PLAT ./capture_reel.sh "$LOC" 2>&1 | grep -E "✅|❌|marker-aligned|content .* HEAD"
  done
done

echo "### macOS all locales  $(date +%H:%M:%S)"
./capture_mac_reel.sh en de fr ja 2>&1 | grep -E "^===|✅|❌|store preview|EMPTY|\.mov$"

echo "FINISH_REELS DONE $(date +%H:%M:%S)"
