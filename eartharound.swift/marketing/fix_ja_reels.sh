#!/usr/bin/env bash
# Re-run the Japanese iPhone/iPad/Mac reels: the first pass burned tofu boxes into the captions
# because frame_reel.py's bold face has no CJK glyphs. Full re-capture rather than re-framing —
# capture_ios.sh writes its marker-aligned timing to a single shared runtime file that later
# locales overwrote, so re-framing now would use nominal timing and drift the captions.
set -uo pipefail
cd /Users/oleksandr/Projects/rootyapps/eartharound.swift/marketing || exit 1
while pgrep -f 'run_all_reels|capture_ios.sh|capture_mac.sh|capture_watch.sh|recordwindow|generate_screenshots' >/dev/null; do sleep 30; done

echo "=== ja iPhone";  ./reels/capture_ios.sh ja 2>&1 | tail -1
./reels/score_ios.sh ja 2>&1 | tail -1
echo "=== ja iPad";    PLATFORM=ipad ./reels/capture_ios.sh ja 2>&1 | tail -1
V="$PWD/aso/ja/ipad/video/framed_preview_1200x1600.mp4" ./reels/score_ios.sh ja 2>&1 | tail -1
echo "=== ja Mac";     ./reels/capture_mac.sh ja 2>&1 | tail -1
V="$PWD/aso/ja/mac/video/framed_preview_1920x1080.mp4" ./reels/score_ios.sh ja 2>&1 | tail -1
echo "JA REELS FIXED"
