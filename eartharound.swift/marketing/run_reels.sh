#!/usr/bin/env bash
# iPhone preview reels per locale, queued behind the screenshot sweep (they share the simulator).
#
# English is NOT re-recorded: its reel is already captured and SCORED, and the bed's prompt/seed
# live beside it. English copy did not change, so the existing cut is still accurate.
set -uo pipefail
cd "$(dirname "$0")"
while pgrep -f 'make_sim_shots|make_mac_shots|capture_watch' >/dev/null; do sleep 20; done
for loc in de ja fr es; do
  echo "=== reel $loc"
  ./reels/capture_ios.sh "$loc" 2>&1 | tail -2
  echo "--- scoring $loc"
  ./reels/score_ios.sh "$loc" 2>&1 | tail -1
done
echo "REELS DONE"
