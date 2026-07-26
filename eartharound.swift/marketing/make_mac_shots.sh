#!/usr/bin/env bash
#
# make_mac_shots.sh — App Store screenshot captures for Earth Around on macOS.
#
# Captures the app's own window by CGWindowID (screencapture -l), not the screen: no
# focus stealing, no desktop or other windows in frame, and no Accessibility permission.
# Screen Recording permission for the calling terminal IS required.
#
# States come from the same launch flags the simulator captures use, passed straight to
# the binary because `open` does not forward the environment.
#
#   raw/mac/0N_*.png  →  generate_screenshots.py (aso/mac/params.yaml)  →  aso/mac/2880x1800/
set -euo pipefail

ROOT="/Users/oleksandr/Projects/rootyapps"
APP_DIR="$ROOT/eartharound.swift"
PROJECT="$APP_DIR/eartharound.swift.xcodeproj"
DERIVED="$APP_DIR/.build/mac-shots-dd"
RAW_DIR="$APP_DIR/marketing/raw/mac"
PYBIN="${PYBIN:-/Users/oleksandr/miniconda3/envs/fantastic/bin/python}"
SETTLE="${SETTLE:-11}"

mkdir -p "$RAW_DIR" "$DERIVED"

echo "▶ build"
xcodebuild build -project "$PROJECT" -scheme eartharound.swift \
  -destination 'platform=macOS' -derivedDataPath "$DERIVED" \
  -allowProvisioningUpdates -quiet
BIN="$DERIVED/Build/Products/Debug/Earth Around.app/Contents/MacOS/Earth Around"
[ -x "$BIN" ] || { echo "❌ no built mac binary at $BIN"; exit 1; }

window_id() {
  "$PYBIN" - <<'PY'
import Quartz, sys
wins = Quartz.CGWindowListCopyWindowInfo(
    Quartz.kCGWindowListOptionOnScreenOnly | Quartz.kCGWindowListExcludeDesktopElements,
    Quartz.kCGNullWindowID)
for w in wins:
    if w.get("kCGOwnerName") == "Earth Around" and w.get("kCGWindowLayer", 0) == 0:
        b = w["kCGWindowBounds"]
        if b["Height"] > 300:                      # skip menu-bar/utility windows
            print(int(w["kCGWindowNumber"])); sys.exit(0)
sys.exit(1)
PY
}

# name|MODE|TAB|THEME
SHOTS=(
  "01_simple_dark|simple|dashboard|dark"
  "02_dashboard_dark|extended|dashboard|dark"
  "03_geomag_dark|extended|geomagnetic|dark"
  "04_simple_night|simple|dashboard|night"
)

for spec in "${SHOTS[@]}"; do
  IFS='|' read -r name mode tab theme <<< "$spec"
  pkill -f "Earth Around.app/Contents/MacOS" 2>/dev/null || true
  sleep 1
  EARTHAROUND_MODE="$mode" EARTHAROUND_TAB="$tab" EARTHAROUND_THEME="$theme" "$BIN" &
  APP_PID=$!
  sleep "$SETTLE"
  WID=$(window_id) || { echo "❌ could not find the app window (is Screen Recording allowed?)"; kill $APP_PID 2>/dev/null || true; exit 1; }
  screencapture -x -o -l "$WID" "$RAW_DIR/$name.png"
  echo "   $name  ($mode/$tab/$theme)  $(sips -g pixelWidth -g pixelHeight "$RAW_DIR/$name.png" | awk '/pixel/{printf "%s ", $2}')"
  kill $APP_PID 2>/dev/null || true
done

pkill -f "Earth Around.app/Contents/MacOS" 2>/dev/null || true
echo
echo "✅ raw mac shots in $RAW_DIR"
echo "   → $PYBIN $ROOT/marketing/generate_screenshots.py $APP_DIR/marketing/aso/mac/params.yaml"
