#!/usr/bin/env bash
#
# make_mac_shots.sh — Mac App Store screenshot captures for Earth Around.
#
#   ./make_mac_shots.sh          # English → raw/en/mac/
#   ./make_mac_shots.sh de       # German  → raw/de/mac/
#
# Capture goes through marketing/tools/capture_mac_window.sh (ScreenCaptureKit, selected BY PID).
#
# The previous version had two faults that only appear when more than one agent is working:
#   • it found the window by matching kCGOwnerName == "Earth Around", so with two copies running
#     it captured whichever Quartz listed first — a coin flip, and the wrong shot still looks
#     completely plausible, which is how it ships;
#   • it ran `pkill -f "Earth Around.app/Contents/MacOS"` between shots, killing every copy on
#     the machine including another agent's.
# Both are fixed by owning a pid: launch the binary directly (not `open`, which may just activate
# an existing instance), capture that pid, and kill only that pid.
#
#   raw/<loc>/mac/0N_*.png  →  generate_screenshots.py (aso/<loc>/mac/params.yaml)
set -euo pipefail

ROOT="/Users/oleksandr/Projects/rootyapps"
APP_DIR="$ROOT/eartharound.swift"
PROJECT="$APP_DIR/eartharound.swift.xcodeproj"
CAPTURE="$ROOT/marketing/tools/capture_mac_window.sh"
PYBIN="${PYBIN:-/Users/oleksandr/miniconda3/envs/fantastic/bin/python}"

LOC="${1:-en}"
RAW_DIR="${RAW_DIR:-$APP_DIR/marketing/raw/$LOC/mac}"
DERIVED="$APP_DIR/.build/mac-shots-dd"
mkdir -p "$RAW_DIR" "$DERIVED"

echo "▶ build (macOS)"
xcodebuild build -project "$PROJECT" -scheme eartharound.swift \
  -destination 'platform=macOS' -configuration Debug -derivedDataPath "$DERIVED" \
  -allowProvisioningUpdates -quiet
APP=$(find "$DERIVED/Build/Products" -maxdepth 2 -name "*.app" | head -1)
[ -n "$APP" ] || { echo "❌ no built .app"; exit 1; }

# name|MODE|TAB|THEME — same story order as the iPhone set.
# Four shots, not five: Simple mode was removed from the app (the root view pins Extended at
# launch), so the two Simple states these used to capture are unreachable. What is left is the
# real state space: two tabs x two themes.
SHOTS=(
  "01_dashboard_dark|extended|dashboard|dark"
  "02_geomag_dark|extended|geomagnetic|dark"
  "03_dashboard_night|extended|dashboard|night"
  "04_geomag_night|extended|geomagnetic|night"
)

for spec in "${SHOTS[@]}"; do
  IFS='|' read -r name mode tab theme <<< "$spec"
  # One launch per shot: the app freezes a single state from these flags, so there is no UI to
  # drive, and a fresh pid each time keeps the capture selector unambiguous.
  LAUNCH_ARGS="-AppleLanguages ($LOC) -AppleLocale $LOC" SETTLE="${SETTLE:-11}" \
    "$CAPTURE" "$APP" "$RAW_DIR/$name.png" \
      "EARTHAROUND_MODE=$mode" "EARTHAROUND_TAB=$tab" "EARTHAROUND_THEME=$theme" >/dev/null
  echo "   $name  ($mode/$tab/$theme)  $(sips -g pixelWidth -g pixelHeight "$RAW_DIR/$name.png" | awk '/pixel/{printf "%s ", $2}')"
done

echo
echo "✅ raw mac shots in $RAW_DIR"
echo "   → $PYBIN $ROOT/marketing/generate_screenshots.py $APP_DIR/marketing/aso/$LOC/mac/params.yaml"
