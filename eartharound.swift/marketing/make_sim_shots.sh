#!/usr/bin/env bash
#
# make_sim_shots.sh — App Store screenshot captures for Earth Around (6.9" iPhone).
#
# The app freezes a single state from launch flags (DemoDriver.applyInitialState), so each
# shot is one launch, no UI driving:
#     EARTHAROUND_MODE=simple|extended   EARTHAROUND_TAB=dashboard|geomagnetic
#     EARTHAROUND_THEME=dark|night
#
# Order matters — the first shots carry most of the decision, so it leads with Simple (the
# first-run default) and only then shows the expert HUD.
#
#   raw/ios/0N_*.png  →  generate_screenshots.py (aso/ios/params.yaml)  →  aso/ios/1320x2868/
set -euo pipefail

ROOT="/Users/oleksandr/Projects/rootyapps"
APP_DIR="$ROOT/eartharound.swift"
PROJECT="$APP_DIR/eartharound.swift.xcodeproj"
SCHEME="${SCHEME:-eartharound.swift}"
APP_BUNDLE="${APP_BUNDLE:-oleksandr.aisixteen.eartharound}"
SIM_NAME="${SIM_NAME:-Calc-iPhone17ProMax}"
DERIVED="$APP_DIR/.build/shots-dd"
RAW_DIR="$APP_DIR/marketing/raw/ios"
SETTLE="${SETTLE:-11}"        # first paint + live NOAA/GFZ fetch

mkdir -p "$RAW_DIR" "$DERIVED"

UDID=$(xcrun simctl list devices | grep "$SIM_NAME (" | grep -oE "[0-9A-Fa-f-]{36}" | head -1)
[ -n "$UDID" ] || { echo "❌ simulator '$SIM_NAME' not found"; exit 1; }
xcrun simctl boot "$UDID" 2>/dev/null || true
xcrun simctl bootstatus "$UDID" -b

echo "▶ build"
xcodebuild build -project "$PROJECT" -scheme "$SCHEME" \
  -destination "id=$UDID" -derivedDataPath "$DERIVED" -quiet
BUILT_APP=$(find "$DERIVED/Build/Products" -maxdepth 2 -name "*.app" -path "*iphonesimulator*" | head -1)
[ -n "$BUILT_APP" ] || { echo "❌ no built .app"; exit 1; }
xcrun simctl install "$UDID" "$BUILT_APP" >/dev/null

xcrun simctl status_bar "$UDID" override \
  --time "9:41" --operatorName " " --batteryState charged --batteryLevel 100 \
  --cellularBars 4 --wifiBars 3 --dataNetwork wifi 2>/dev/null || true

# name|MODE|TAB|THEME
SHOTS=(
  "01_simple_dark|simple|dashboard|dark"
  "02_dashboard_dark|extended|dashboard|dark"
  "03_geomag_dark|extended|geomagnetic|dark"
  "04_geomag_night|extended|geomagnetic|night"
  "05_simple_night|simple|dashboard|night"
)

for spec in "${SHOTS[@]}"; do
  IFS='|' read -r name mode tab theme <<< "$spec"
  xcrun simctl terminate "$UDID" "$APP_BUNDLE" 2>/dev/null || true
  # Bounce through the home screen first, or the status bar keeps the "◄ PrevApp"
  # breadcrumb from whatever ran last in this simulator and it lands in the screenshot.
  xcrun simctl launch "$UDID" com.apple.springboard >/dev/null 2>&1 || true
  sleep 1
  SIMCTL_CHILD_EARTHAROUND_MODE="$mode" \
  SIMCTL_CHILD_EARTHAROUND_TAB="$tab" \
  SIMCTL_CHILD_EARTHAROUND_THEME="$theme" \
    xcrun simctl launch "$UDID" "$APP_BUNDLE" >/dev/null
  sleep "$SETTLE"
  xcrun simctl io "$UDID" screenshot "$RAW_DIR/$name.png" >/dev/null 2>&1
  echo "   $name  ($mode/$tab/$theme)"
done

xcrun simctl status_bar "$UDID" clear 2>/dev/null || true
echo
echo "✅ raw shots in $RAW_DIR"
echo "   → /Users/oleksandr/miniconda3/envs/fantastic/bin/python $ROOT/marketing/generate_screenshots.py $APP_DIR/marketing/aso/ios/params.yaml"
