#!/usr/bin/env bash
# Full re-capture against the final build. Earlier runs straddled the positional-key fix, so the
# Extended shots could still carry an English Kp meaning line — invisible unless you look.
set -uo pipefail
cd "$(dirname "$0")"
for loc in en de ja fr es; do
  echo "=== iPhone $loc"; ./make_sim_shots.sh "$loc" 2>&1 | tail -1
done
for loc in en de ja fr es; do
  echo "=== iPad $loc"; PLATFORM=ipad ./make_sim_shots.sh "$loc" 2>&1 | tail -1
done
echo "ALL CAPTURES DONE"
