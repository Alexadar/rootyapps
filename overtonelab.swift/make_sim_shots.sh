#!/usr/bin/env bash
#
# make_sim_shots.sh — capture raw App Store screenshots from an iOS/iPad Simulator via the
# OVERTONELAB_TOOL deep-link (a fresh launch per screen), then frame them with generate_screenshots.py.
#   PLATFORM=ios  make_sim_shots.sh   → iPhone catalog + tools → raw/ios_clean → aso/ios
#   PLATFORM=ipad make_sim_shots.sh   → iPad split-view screens → raw/ipad     → aso/ipad
#
set -euo pipefail
ROOT=/Users/oleksandr/Projects/rootyapps
APP=$ROOT/overtonelab.swift
PY=/Users/oleksandr/miniconda3/envs/fantastic/bin/python
BUNDLE=oleksandr.aisixteen.overtonelab
PLATFORM="${PLATFORM:-ios}"

if [ "$PLATFORM" = "ipad" ]; then
  UDID=08E036BE-970C-47E3-B868-DA9E3F1D94D2      # Calc-iPadPro13
  RAW="$APP/marketing/raw/ipad"
  SCENES=("01_pitch:pitch" "02_sabine:sabine" "03_thiele:thiele" "04_partch:partch")
else
  UDID=9B3C38B6-6F0D-4C18-A750-B254301CD9F1      # Calc-iPhone17ProMax
  RAW="$APP/marketing/raw/ios_clean"
  SCENES=("01_catalog:" "02_tempo:tempo" "03_pitch:pitch" "04_sabine:sabine" "05_benchmark:benchmark" "06_sra:sra")
fi
mkdir -p "$RAW"; rm -f "$RAW"/*.png
DD="$APP/build/dd-shots-$PLATFORM"

xcrun simctl boot "$UDID" 2>/dev/null || true
xcrun simctl bootstatus "$UDID" -b

echo "▶ build + install ($PLATFORM)"
xcodebuild -scheme overtonelab.swift -destination "id=$UDID" -derivedDataPath "$DD" build >/dev/null
APPPATH=$(find "$DD/Build/Products" -maxdepth 2 -name "*.app" -path "*iphonesimulator*" ! -name "*-Runner.app" | head -1)
xcrun simctl install "$UDID" "$APPPATH" >/dev/null
xcrun simctl status_bar "$UDID" override --time "9:41" --batteryState charged --batteryLevel 100 \
  --cellularBars 4 --wifiBars 3 --dataNetwork wifi 2>/dev/null || true

shot(){  # name  tool(optional)
  xcrun simctl terminate "$UDID" "$BUNDLE" 2>/dev/null || true; sleep 0.5
  if [ -n "${2:-}" ]; then
    SIMCTL_CHILD_OVERTONELAB_TOOL="$2" xcrun simctl launch "$UDID" "$BUNDLE" >/dev/null
  else
    xcrun simctl launch "$UDID" "$BUNDLE" >/dev/null
  fi
  sleep 2.8
  xcrun simctl io "$UDID" screenshot "$RAW/$1.png" >/dev/null && echo "  ✓ $1"
}

# Return to the home screen first, so the first launch has no "◄ PrevApp" status-bar breadcrumb.
xcrun simctl terminate "$UDID" oleksandr.aisixteen.ephemeris 2>/dev/null || true
xcrun simctl launch "$UDID" com.apple.springboard >/dev/null 2>&1 || true
sleep 1.2

echo "▶ capturing"
for s in "${SCENES[@]}"; do shot "${s%%:*}" "${s##*:}"; done
xcrun simctl terminate "$UDID" "$BUNDLE" 2>/dev/null || true
xcrun simctl status_bar "$UDID" clear 2>/dev/null || true

echo "▶ framing"
( cd "$ROOT/marketing" && "$PY" generate_screenshots.py "$APP/marketing/aso/$PLATFORM/params.yaml" )
echo "done → $APP/marketing/aso/$PLATFORM/"
