#!/usr/bin/env bash
# Definitive capture sweep against the FINAL binary.
#
# Everything before this predates two visible string changes: the SWText refactor (which is what
# actually makes the in-app picker work) and the tab titles, which rendered "Dashboard"/
# "Geomagnetic" in English in every localized Extended-mode shot. Re-shoot, per the rule that a
# screenshot taken before a string change keeps the old wording forever.
set -uo pipefail
cd "$(dirname "$0")"
LOCALES="en de ja fr es"
for loc in $LOCALES; do echo "=== iPhone $loc"; ./make_sim_shots.sh "$loc" 2>&1 | tail -1; done
for loc in $LOCALES; do echo "=== iPad $loc";   PLATFORM=ipad ./make_sim_shots.sh "$loc" 2>&1 | tail -1; done
for loc in $LOCALES; do echo "=== macOS $loc";  ./make_mac_shots.sh "$loc" 2>&1 | tail -1; done
for loc in $LOCALES; do echo "=== watch $loc";  SHOTS_ONLY=1 ./reels/capture_watch.sh "$loc" 2>&1 | tail -1; done
echo "FINAL CAPTURES DONE"
