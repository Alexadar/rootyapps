#!/usr/bin/env bash
# make_reels.sh — record Par's app-preview reels on simulators Par owns, one at a time.
#
# Wraps ../marketing/reels/make_reel.sh with two things that shared tooling cannot assume:
#
#   1. Dedicated devices. Par-iPhone17ProMax / Par-iPadPro13 exist so a Par capture never lands on
#      Calc-* or MarineNav-*, which the other apps in this repo drive.
#   2. Exclusive use. Every other simulator is shut down first. A reel is a real-time screen
#      recording driven by a UI test; when three simulators are booted the tour's element queries
#      slow from ~0.3s to ~3s each, which stretches 50s of content past the point where it can be
#      speed-fit under Apple's 30s cap — and at worst times the tour out mid-recording.
#
#   bash marketing/make_reels.sh          # both platforms
#   bash marketing/make_reels.sh ios      # one
set -euo pipefail

APP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROOT="$(cd "$APP_DIR/.." && pwd)"
WANTED="${1:-both}"

isolate() {
  local keep="$1"
  xcrun simctl list devices | grep Booted | grep -oE "[0-9A-Fa-f-]{36}" | while read -r udid; do
    [ "$udid" = "$keep" ] || { echo "  · shutting down $udid"; xcrun simctl shutdown "$udid" || true; }
  done
}

record() {
  local platform="$1" sim="$2" scenes="$3"
  local udid
  udid=$(xcrun simctl list devices | grep "$sim (" | grep -oE "[0-9A-Fa-f-]{36}" | head -1)
  [ -n "$udid" ] || { echo "❌ simulator '$sim' not found — create it first"; exit 1; }
  echo "▶ $platform on $sim ($udid)"
  isolate "$udid"
  APP_DIR="$APP_DIR" PROJECT="$APP_DIR/Par.xcodeproj" SCHEME=ParReel \
    APP_BUNDLE=oleksandr.aisixteen.fincalc PLATFORM="$platform" SIM_NAME="$sim" \
    SCENES="$scenes" bash "$ROOT/marketing/reels/make_reel.sh"
  # align_scenes writes the measured windows here; store_preview.py needs them per platform, and the
  # next platform's run overwrites the file.
  cp "$APP_DIR/.build/reel-dd/scenes.runtime.json" "$APP_DIR/marketing/reels/runtime_$platform.json"
  echo "  measured windows -> marketing/reels/runtime_$platform.json"
}

[ "$WANTED" = "both" ] || [ "$WANTED" = "ios" ] && \
  record ios  Par-iPhone17ProMax "$APP_DIR/marketing/reels/scenes.json"
[ "$WANTED" = "both" ] || [ "$WANTED" = "ipad" ] && \
  record ipad Par-iPadPro13      "$APP_DIR/marketing/reels/scenes_ipad.json"

echo "✅ reels recorded"
