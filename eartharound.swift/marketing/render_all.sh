#!/usr/bin/env bash
# Wait for any running capture sweep, then frame every raw set into store-ready images.
cd "$(dirname "$0")"
PY=/Users/oleksandr/miniconda3/envs/fantastic/bin/python
GEN=/Users/oleksandr/Projects/rootyapps/marketing/generate_screenshots.py
while pgrep -f make_sim_shots >/dev/null; do sleep 10; done
for p in en/ios en/ipad en/mac en/watch de/ios de/ipad ja/ios ja/ipad fr/ios fr/ipad es/ios es/ipad; do
  [ -f "aso/$p/params.yaml" ] || { echo "skip $p (no params)"; continue; }
  echo "=== render $p"
  "$PY" "$GEN" "aso/$p/params.yaml" 2>&1 | tail -2
done
echo "RENDER DONE"
