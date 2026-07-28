#!/usr/bin/env bash
#
# make_sim_shots.sh — App Store screenshot captures for Overtone Lab, per language.
#
# Each shot is one launch driven by the deep-link env hooks — no UI driving:
#     OVERTONELAB_TOOL=<tool raw value>   OVERTONELAB_LANG=<bcp47>
#
#     ./make_sim_shots.sh            → English  → raw/en/ios
#     ./make_sim_shots.sh de         → German   → raw/de/ios
#     PLATFORM=ipad ./make_sim_shots.sh ja      → Japanese → raw/ja/ipad
#
#   raw/<loc>/<platform>/0N_*.png → generate_screenshots.py (aso/<loc>/<platform>/params.yaml)
#                                 → aso/<loc>/<platform>/<WxH>/
#
# TWO RULES THIS SCRIPT EXISTS TO ENFORCE (both learned by shipping the bug):
#
# 1. DEDICATED SIMULATORS. Other apps are captured on this machine at the same time. Shared sims
#    mean another session's app is frontmost when your screenshot fires — this pipeline produced
#    an "Overtone Lab" screenshot that was actually Earth Around in Japanese, and another that was
#    a mortgage calculator. OTL-iPhone / OTL-iPad exist so nothing else ever runs here.
#
# 2. VERIFY THE PIXELS, NEVER TRUST `sleep`. After each launch the frame is checked: not blank,
#    not the white launch screen, and dark like this app actually is. A silent bad frame is worse
#    than a failed run, because it ships.
#
# Runs HEADLESS: simctl only, Simulator.app is never opened, so it cannot steal focus while you
# are working.
set -euo pipefail
ROOT=/Users/oleksandr/Projects/rootyapps
APP=$ROOT/overtonelab.swift
PY=/Users/oleksandr/miniconda3/envs/fantastic/bin/python
BUNDLE=oleksandr.aisixteen.overtonelab
LOC="${1:-en}"                         # BCP-47 tag; English is explicit, not a special case
PLATFORM="${PLATFORM:-ios}"            # ios | ipad

if [ "$PLATFORM" = "ipad" ]; then
  SIM_NAME="${SIM_NAME:-OTL-iPad}"
  SCENES=("01_catalog:" "02_sabine:sabine" "03_thiele:thiele" "04_partch:partch")
else
  SIM_NAME="${SIM_NAME:-OTL-iPhone}"
  SCENES=("01_catalog:" "02_tempo:tempo" "03_pitch:pitch" "04_sabine:sabine" "05_benchmark:benchmark" "06_sra:sra")
fi
RAW="$APP/marketing/raw/$LOC/$PLATFORM"
PARAMS="$APP/marketing/aso/$LOC/$PLATFORM/params.yaml"
DD="$APP/build/dd-shots-$PLATFORM"
mkdir -p "$RAW"; rm -f "$RAW"/*.png

UDID=$(xcrun simctl list devices | grep "$SIM_NAME (" | grep -oE "[0-9A-Fa-f-]{36}" | head -1)
[ -n "$UDID" ] || { echo "❌ dedicated simulator '$SIM_NAME' not found — create it with:"; \
  echo "   xcrun simctl create '$SIM_NAME' <deviceType> com.apple.CoreSimulator.SimRuntime.iOS-26-5"; exit 1; }
xcrun simctl boot "$UDID" 2>/dev/null || true
xcrun simctl bootstatus "$UDID" -b >/dev/null

echo "▶ build + install ($PLATFORM, $LOC) on $SIM_NAME"
xcodebuild -scheme overtonelab.swift -destination "id=$UDID" -derivedDataPath "$DD" build >/dev/null
APPPATH=$(find "$DD/Build/Products" -maxdepth 2 -name "*.app" -path "*iphonesimulator*" ! -name "*-Runner.app" | head -1)
xcrun simctl install "$UDID" "$APPPATH" >/dev/null
xcrun simctl status_bar "$UDID" override --time "9:41" --batteryState charged --batteryLevel 100 \
  --cellularBars 4 --wifiBars 3 --dataNetwork wifi 2>/dev/null || true

# Is this frame our dark UI, or a white launch screen / someone else's app / nothing?
valid_shot(){ "$PY" - "$1" <<'PYEOF'
import sys
from PIL import Image
import numpy as np
a = np.asarray(Image.open(sys.argv[1]).convert("RGB")).astype(float)
mean, std = a.mean(), a.std()
# Overtone Lab is a near-black studio UI: low mean, but real content so not a flat black frame.
sys.exit(0 if (mean < 90 and std > 6) else 1)
PYEOF
}

shot(){  # name  tool(optional)
  local name="$1" tool="${2:-}" try
  for try in 1 2 3; do
    xcrun simctl terminate "$UDID" "$BUNDLE" 2>/dev/null || true; sleep 0.6
    SIMCTL_CHILD_OVERTONELAB_LANG="$LOC" SIMCTL_CHILD_OVERTONELAB_TOOL="$tool" \
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
  echo "⚠ no params at $PARAMS — run marketing/gen_params.py first; raws are in $RAW"
fi
