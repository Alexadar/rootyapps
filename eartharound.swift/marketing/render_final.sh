#!/usr/bin/env bash
# Frame every screenshot set once all capture work is done. Deliberately NOT run alongside a
# reel capture: PIL rendering pegs the CPU and the simulator/window-server encoders drop frames
# under load, which silently shortens the footage.
cd "$(dirname "$0")"
PY=/Users/oleksandr/miniconda3/envs/fantastic/bin/python
GEN=/Users/oleksandr/Projects/rootyapps/marketing/generate_screenshots.py
while pgrep -f 'capture_ios.sh|capture_mac.sh|capture_watch.sh|recordwindow' >/dev/null; do sleep 30; done
for loc in en de ja fr es; do
  for plat in ios ipad mac watch; do
    [ -f "aso/$loc/$plat/params.yaml" ] || continue
    printf '%-14s ' "$loc/$plat"
    "$PY" "$GEN" "aso/$loc/$plat/params.yaml" 2>&1 | tail -1
  done
done
echo "RENDER ALL DONE"
