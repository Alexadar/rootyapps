#!/usr/bin/env bash
#
# make_sim_shots.sh — App Store screenshot captures for AirCore.
#
# Each shot is one launch driven by the deep-link hook, no UI driving:
#     AIRCORE_TOOL=<Tool raw value>       (empty = the catalogue)
#
#     ./make_sim_shots.sh                 → raw/en/ios
#     PLATFORM=ipad ./make_sim_shots.sh   → raw/en/ipad
#
#   raw/en/<platform>/NN_*.png → generate_screenshots.py (aso/en/<platform>/params.yaml)
#                              → aso/en/<platform>/<WxH>/
#
# English only, deliberately: AirCore ships en-US at 1.0 and the store record has no other
# locales, so there is no `$LOC` loop here to fall out of sync with the app.
#
# The two rules this script exists to enforce, both learned elsewhere in this repo by shipping
# the bug:
#
# 1. DEDICATED SIMULATORS. Other apps are captured on this machine at the same time, and a shared
#    sim means another session's app is frontmost when the screenshot fires. That has already
#    produced an "Overtone Lab" screenshot that was actually a different app in Japanese. The
#    AIRC-Shot-* sims exist so nothing else ever runs here — and they are deliberately NOT the
#    AIRC-iPhone/iPad/Watch sims that run_tests.sh creates and deletes.
#
# 2. VERIFY THE PIXELS, NEVER TRUST `sleep`. Every frame is checked before it is kept: not blank,
#    not the launch screen, and light like this app actually is. A silent bad frame is worse than
#    a failed run, because a failed run stops and a bad frame ships.
#
# Runs headless: simctl only, Simulator.app is never opened, so it cannot steal focus.
set -euo pipefail
ROOT=/Users/oleksandr/Projects/rootyapps
APP=$ROOT/aircore
PY=/Users/oleksandr/miniconda3/envs/fantastic/bin/python
BUNDLE=oleksandr.aisixteen.aircore
LOC=en
PLATFORM="${PLATFORM:-ios}"            # ios | ipad

if [ "$PLATFORM" = "ipad" ]; then
  SIM_NAME="${SIM_NAME:-AIRC-Shot-iPad}"
  DEVICE_TYPES=(com.apple.CoreSimulator.SimDeviceType.iPad-Pro-13-inch-M4-8GB
                com.apple.CoreSimulator.SimDeviceType.iPad-Pro-11-inch-M4-8GB)
  # The sidebar layout shows breadth in one frame, so the catalogue shot is redundant here.
  SCENES=("01_psychrometrics:psychrometrics" "02_duct:duct" "03_mixing:mixing" "04_pipe:pipe")
else
  SIM_NAME="${SIM_NAME:-AIRC-Shot-iPhone}"
  DEVICE_TYPES=(com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro-Max
                com.apple.CoreSimulator.SimDeviceType.iPhone-16-Pro-Max)
  # Leads with the chart — the hard part and the differentiator — then the catalogue, which is
  # the commercial argument (one app instead of four).
  SCENES=("01_psychrometrics:psychrometrics" "02_catalog:" "03_duct:duct"
          "04_airsideHeat:airsideHeat" "05_mixing:mixing" "06_pipe:pipe")
fi

RAW="$APP/marketing/raw/$LOC/$PLATFORM"
PARAMS="$APP/marketing/aso/$LOC/$PLATFORM/params.yaml"
DD="$APP/build/dd-shots-$PLATFORM"
mkdir -p "$RAW"
rm -f "$RAW"/*.png          # nothing in this pipeline deletes; stale frames get framed silently

RUNTIME=$(xcrun simctl list runtimes | awk '/^iOS/ {print $NF}' | tail -1)
UDID=$(xcrun simctl list devices -j | "$PY" -c "
import json,sys
d = json.load(sys.stdin)['devices']
print(next((x['udid'] for g in d.values() for x in g if x['name'] == '$SIM_NAME'), ''))")
if [ -z "$UDID" ]; then
  for dt in "${DEVICE_TYPES[@]}"; do
    if UDID=$(xcrun simctl create "$SIM_NAME" "$dt" "$RUNTIME" 2>/dev/null); then break; fi
  done
  [ -n "$UDID" ] || { echo "❌ could not create $SIM_NAME on $RUNTIME"; exit 1; }
  PLIST="$HOME/Library/Developer/CoreSimulator/Devices/$UDID/data/Library/Preferences/.GlobalPreferences.plist"
  mkdir -p "$(dirname "$PLIST")"
  /usr/libexec/PlistBuddy -c "Add :AppleLocale string en_US" "$PLIST" 2>/dev/null \
    || /usr/libexec/PlistBuddy -c "Set :AppleLocale en_US" "$PLIST"
  echo "created $SIM_NAME  $UDID"
fi

xcrun simctl boot "$UDID" 2>/dev/null || true
xcrun simctl bootstatus "$UDID" -b >/dev/null

echo "▶ build + install ($PLATFORM) on $SIM_NAME"
xcodebuild -project "$APP/aircore.xcodeproj" -scheme aircore -destination "id=$UDID" \
  -derivedDataPath "$DD" build >/dev/null
APPPATH=$(find "$DD/Build/Products" -maxdepth 2 -name "*.app" -path "*iphonesimulator*" \
  ! -name "*-Runner.app" | head -1)
xcrun simctl install "$UDID" "$APPPATH" >/dev/null
xcrun simctl status_bar "$UDID" override --time "9:41" --batteryState charged --batteryLevel 100 \
  --cellularBars 4 --wifiBars 3 --dataNetwork wifi 2>/dev/null || true

# Is this frame AirCore, or a white launch screen / someone else's app / nothing?
# AirCore's water-breeze ground is light (#F0F7FB), so a valid frame is BRIGHT — but a blank white
# launch screen is brighter still and perfectly flat, which is what the standard deviation catches.
valid_shot(){ "$PY" - "$1" <<'PYEOF'
import sys
from PIL import Image
import numpy as np
a = np.asarray(Image.open(sys.argv[1]).convert("RGB")).astype(float)
mean, std = a.mean(), a.std()
sys.exit(0 if (mean > 140 and std > 12) else 1)
PYEOF
}

shot(){  # name  tool(optional)
  local name="$1" tool="${2:-}" try
  for try in 1 2 3; do
    xcrun simctl terminate "$UDID" "$BUNDLE" 2>/dev/null || true; sleep 0.6
    SIMCTL_CHILD_AIRCORE_TOOL="$tool" SIMCTL_CHILD_AIRCORE_RESET=1 \
      xcrun simctl launch "$UDID" "$BUNDLE" >/dev/null
    sleep $((2 + try))
    xcrun simctl io "$UDID" screenshot "$RAW/$name.png" >/dev/null 2>&1
    if valid_shot "$RAW/$name.png"; then echo "  ✓ $name"; return 0; fi
    echo "  … $name looked wrong (blank or foreign frame), retry $try"
  done
  echo "  ✗ $name FAILED validation — refusing to ship a frame I cannot verify"; return 1
}

# Home screen first, so the first launch carries no "◄ PrevApp" status-bar breadcrumb.
xcrun simctl launch "$UDID" com.apple.springboard >/dev/null 2>&1 || true
sleep 1.2

echo "▶ capturing $LOC/$PLATFORM"
for s in "${SCENES[@]}"; do shot "${s%%:*}" "${s##*:}"; done
xcrun simctl terminate "$UDID" "$BUNDLE" 2>/dev/null || true
xcrun simctl status_bar "$UDID" clear 2>/dev/null || true

if [ -f "$PARAMS" ]; then
  echo "▶ framing"
  ( cd "$ROOT/marketing" && "$PY" generate_screenshots.py "$PARAMS" )
  echo "done → $APP/marketing/aso/$LOC/$PLATFORM/"
else
  echo "⚠ no params at $PARAMS — raws are in $RAW"
fi
