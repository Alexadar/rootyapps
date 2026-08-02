#!/usr/bin/env bash
# Re-frame the watch reels. fr/es crashed on the UnboundLocalError; ja was framed before the CJK
# font fix and burned tofu into its captions. The captures themselves are fine, so this only
# re-runs the framing step — no re-recording needed.
set -uo pipefail
cd /Users/oleksandr/Projects/rootyapps/eartharound.swift/marketing || exit 1
while pgrep -f 'capture_ios.sh|capture_mac.sh|capture_watch.sh|recordwindow' >/dev/null; do sleep 30; done
for loc in ja fr es; do
  echo "=== reframe watch $loc"
  ./reels/frame_watch.sh "$loc" 2>&1 | tail -2
done
echo "WATCH REFRAME DONE"
