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
# Pass a locale to capture the app running in that language:
#     ./make_sim_shots.sh de       →  raw/de/0N_*.png
# With no argument it captures English into raw/ios/, the original layout.
#
#   raw/<loc>/0N_*.png  →  generate_screenshots.py (aso/<loc>/params.yaml)  →  aso/<loc>/1320x2868/
set -euo pipefail

ROOT="/Users/oleksandr/Projects/rootyapps"
APP_DIR="$ROOT/eartharound.swift"
PROJECT="$APP_DIR/eartharound.swift.xcodeproj"
SCHEME="${SCHEME:-eartharound.swift}"
APP_BUNDLE="${APP_BUNDLE:-oleksandr.aisixteen.eartharound}"
DERIVED="$APP_DIR/.build/shots-dd"
LOC="${1:-en}"                        # BCP-47 tag; English is explicit, not a special case
PLATFORM="${PLATFORM:-ios}"           # ios | ipad — picks the simulator and the raw folder
case "$PLATFORM" in
  ipad) SIM_NAME="${SIM_NAME:-Calc-iPadPro13}" ;;
  *)    SIM_NAME="${SIM_NAME:-Calc-iPhone17ProMax}" ;;
esac
# English keeps the original flat layout (raw/ios); every other language nests under its tag.
RAW_DIR="${RAW_DIR:-$APP_DIR/marketing/raw/$LOC/$PLATFORM}"
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
# Four shots, not five: Simple mode was removed from the app (the root view pins Extended at
# launch), so the two Simple states these used to capture are unreachable — a screenshot of a
# screen no user can open is exactly what Guideline 2.3.3 is about. What is left is the real
# state space: two tabs x two themes.
SHOTS=(
  "01_dashboard_dark|extended|dashboard|dark"
  "02_geomag_dark|extended|geomagnetic|dark"
  "03_dashboard_night|extended|dashboard|night"
  "04_geomag_night|extended|geomagnetic|night"
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
    xcrun simctl launch "$UDID" "$APP_BUNDLE" \
      -AppleLanguages "($LOC)" -AppleLocale "$LOC" >/dev/null
  sleep "$SETTLE"
  # `simctl io screenshot` grabs the whole device screen — there is no per-window filter as there
  # is on macOS. If another agent launches an app on this shared simulator during the settle, we
  # would photograph theirs. Re-launching ours here is a no-op for state (already running) but
  # brings it back to the front, shrinking that window from $SETTLE seconds to about one.
  xcrun simctl launch "$UDID" "$APP_BUNDLE" \
    -AppleLanguages "($LOC)" -AppleLocale "$LOC" >/dev/null 2>&1 || true
  sleep 1
  xcrun simctl io "$UDID" screenshot "$RAW_DIR/$name.png" >/dev/null 2>&1
  echo "   $name  ($mode/$tab/$theme)"
done

xcrun simctl status_bar "$UDID" clear 2>/dev/null || true
echo
echo "✅ raw shots in $RAW_DIR"
echo "   → /Users/oleksandr/miniconda3/envs/fantastic/bin/python $ROOT/marketing/generate_screenshots.py $APP_DIR/marketing/aso/$LOC/$PLATFORM/params.yaml"
