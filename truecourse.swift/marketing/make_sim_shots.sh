#!/bin/bash
# TrueCourse — iOS/iPad App Store screenshots from the simulator.
# One fresh, deep-linked launch per screen; then framed by the shared Python engine.
#   PLATFORM=ios  bash marketing/make_sim_shots.sh
#   PLATFORM=ipad bash marketing/make_sim_shots.sh
set -euo pipefail

ROOT=/Users/oleksandr/Projects/rootyapps
APP="$ROOT/truecourse.swift"
PY=/Users/oleksandr/miniconda3/envs/fantastic/bin/python
BUNDLE=oleksandr.aisixteen.truecourse
PLATFORM="${PLATFORM:-ios}"

if [ "$PLATFORM" = "ipad" ]; then
  UDID=08E036BE-970C-47E3-B868-DA9E3F1D94D2     # Calc-iPadPro13
  RAW="$APP/marketing/raw/ipad"
  # name:tool:screen  (empty tool = catalog/root)
  SCENES=("01_catalog::" "02_wind:wind:0" "03_wb:wb:1" "04_convert:convert:0")
else
  UDID=9B3C38B6-6F0D-4C18-A750-B254301CD9F1     # Calc-iPhone17ProMax (6.9")
  RAW="$APP/marketing/raw/ios"
  SCENES=("01_catalog::" "02_wind:wind:0" "03_airspeed:airspeed:0" "04_altitude:altitude:0" "05_wb:wb:1" "06_convert:convert:0")
fi
DD="$APP/build/dd-shots-$PLATFORM"
mkdir -p "$RAW"; rm -f "$RAW"/*.png

( cd "$APP" && xcodegen generate >/dev/null )
xcrun simctl boot "$UDID" 2>/dev/null || true
xcrun simctl bootstatus "$UDID" -b
xcodebuild -scheme truecourse.swift -destination "id=$UDID" -derivedDataPath "$DD" build >/dev/null
APPPATH=$(find "$DD/Build/Products" -maxdepth 2 -name "*.app" -path "*iphonesimulator*" ! -name "*-Runner.app" | head -1)
xcrun simctl install "$UDID" "$APPPATH" >/dev/null
xcrun simctl status_bar "$UDID" override --time "9:41" --batteryState charged --batteryLevel 100 \
  --cellularBars 4 --wifiBars 3 --dataNetwork wifi 2>/dev/null || true

shot(){  # name  tool(optional)  screen(optional)
  xcrun simctl terminate "$UDID" "$BUNDLE" 2>/dev/null || true; sleep 0.5
  if [ -n "${2:-}" ] && [ -n "${3:-}" ]; then
    SIMCTL_CHILD_TRUECOURSE_TOOL="$2" SIMCTL_CHILD_TRUECOURSE_SCREEN="$3" xcrun simctl launch "$UDID" "$BUNDLE" >/dev/null
  elif [ -n "${2:-}" ]; then
    SIMCTL_CHILD_TRUECOURSE_TOOL="$2" xcrun simctl launch "$UDID" "$BUNDLE" >/dev/null
  else
    xcrun simctl launch "$UDID" "$BUNDLE" >/dev/null
  fi
  sleep 2.8
  xcrun simctl io "$UDID" screenshot "$RAW/$1.png" >/dev/null && echo "  ✓ $1"
}

# Home screen first so the first shot has no "◄ app" breadcrumb.
xcrun simctl launch "$UDID" com.apple.springboard >/dev/null 2>&1 || true
sleep 1.2
for s in "${SCENES[@]}"; do
  IFS=: read -r nm tool scr <<< "$s"
  shot "$nm" "$tool" "$scr"
done
xcrun simctl terminate "$UDID" "$BUNDLE" 2>/dev/null || true
xcrun simctl status_bar "$UDID" clear 2>/dev/null || true

echo "Framing…"
( cd "$ROOT/marketing" && "$PY" generate_screenshots.py "$APP/marketing/aso/$PLATFORM/params.yaml" )
echo "Done → $APP/marketing/aso/$PLATFORM/"
