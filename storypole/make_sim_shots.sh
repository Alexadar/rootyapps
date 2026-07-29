#!/usr/bin/env bash
#
# make_sim_shots.sh — App Store screenshot captures for Storypole, per language.
#
# Each shot is one launch driven by the deep-link env hooks — no UI driving:
#     STORYPOLE_TOOL=<tool raw value>   STORYPOLE_TAB=<n>   STORYPOLE_LANG=<bcp47>
#
#     ./make_sim_shots.sh                → English → marketing/raw/en/ios
#     PLATFORM=ipad ./make_sim_shots.sh  → English → marketing/raw/en/ipad
#
#   raw/<loc>/<platform>/0N_*.png → marketing/generate_screenshots.py
#                                 → aso/<loc>/<platform>/<WxH>/
#
# TWO RULES THIS SCRIPT EXISTS TO ENFORCE (both learned by shipping the bug, see overtonelab):
#
# 1. DEDICATED SIMULATORS. Other apps are captured on this machine at the same time. On a shared
#    sim another session's app is frontmost when your screenshot fires — that pipeline once
#    produced an "Overtone Lab" screenshot that was actually Earth Around in Japanese. SP-iPhone
#    and SP-iPad exist so nothing else ever runs here.
#
# 2. VERIFY THE PIXELS, NEVER TRUST `sleep`. Each frame is checked before it is kept. A silent bad
#    frame is worse than a failed run, because it ships.
#
#    ⚠️ Storypole's check is the INVERSE of overtonelab's. That app is a near-black studio UI and
#    asserts `mean < 90`; Storypole is a LIGHT jobsite instrument (warm paper, SP.background
#    #F4F1EA) and asserts `mean > 150`. Copying the dark check here would reject every good frame
#    and pass a black one.
#
# Runs HEADLESS: simctl only, Simulator.app is never opened, so it cannot steal focus.
set -euo pipefail
ROOT=/Users/oleksandr/Projects/rootyapps
APP=$ROOT/storypole
PY=/Users/oleksandr/miniconda3/envs/fantastic/bin/python
BUNDLE=oleksandr.aisixteen.storypole
LOC="${1:-en}"
PLATFORM="${PLATFORM:-ios}"            # ios | ipad

if [ "$PLATFORM" = "ipad" ]; then
  SIM_NAME="${SIM_NAME:-SP-iPad}"
  # iPad shows the split view, so the catalog shot carries far more of the app.
  SCENES=("01_calc::0:demo" "02_spacing:equalSpacing::" "03_boardfeet:boardFeet::" "04_reference::2:")
else
  SIM_NAME="${SIM_NAME:-SP-iPhone}"
  SCENES=("01_calc::0:demo" "02_tools::1:" "03_spacing:equalSpacing::" \
          "04_oncenter:onCenter::" "05_dressed:dressedSize::" "06_reference::2:")
fi
RAW="$APP/marketing/raw/$LOC/$PLATFORM"
PARAMS="$APP/marketing/aso/$LOC/$PLATFORM/params.yaml"
DD="$APP/build/dd-shots-$PLATFORM"
mkdir -p "$RAW"; rm -f "$RAW"/*.png

UDID=$(xcrun simctl list devices | grep "$SIM_NAME (" | grep -oE "[0-9A-Fa-f-]{36}" | head -1 || true)
[ -n "$UDID" ] || { echo "❌ dedicated simulator '$SIM_NAME' not found. Create it:"; \
  echo "   xcrun simctl create SP-iPhone com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro-Max com.apple.CoreSimulator.SimRuntime.iOS-26-5"; exit 1; }
xcrun simctl boot "$UDID" 2>/dev/null || true
xcrun simctl bootstatus "$UDID" -b >/dev/null

echo "▶ build + install ($PLATFORM, $LOC) on $SIM_NAME"
xcodebuild -scheme storypole -destination "id=$UDID" -derivedDataPath "$DD" build >/dev/null
APPPATH=$(find "$DD/Build/Products" -maxdepth 2 -name "*.app" -path "*iphonesimulator*" ! -name "*-Runner.app" | head -1)
xcrun simctl install "$UDID" "$APPPATH" >/dev/null
xcrun simctl status_bar "$UDID" override --time "9:41" --batteryState charged --batteryLevel 100 \
  --cellularBars 4 --wifiBars 3 --dataNetwork wifi 2>/dev/null || true

# Is this frame Storypole's light UI, or a launch screen / someone else's app / nothing?
valid_shot(){ "$PY" - "$1" <<'PYEOF'
import sys
from PIL import Image
import numpy as np
a = np.asarray(Image.open(sys.argv[1]).convert("RGB")).astype(float)
mean, std = a.mean(), a.std()
# Storypole is a LIGHT instrument on warm paper: high mean, but real content so not a flat
# white launch screen. A blank white frame has std ~0; a real screen has cards, keys and a blade.
ok = mean > 150 and std > 12
print(f"mean={mean:.1f} std={std:.1f} -> {'ok' if ok else 'REJECT'}", file=sys.stderr)
sys.exit(0 if ok else 1)
PYEOF
}

shot(){  # name  tool  tab  demo
  local name="$1" tool="${2:-}" tab="${3:-}" demo="${4:-}" try
  for try in 1 2 3; do
    xcrun simctl terminate "$UDID" "$BUNDLE" 2>/dev/null || true; sleep 0.6
    SIMCTL_CHILD_STORYPOLE_LANG="$LOC" \
    SIMCTL_CHILD_STORYPOLE_TOOL="$tool" \
    SIMCTL_CHILD_STORYPOLE_TAB="$tab" \
    SIMCTL_CHILD_STORYPOLE_DEMO="$([ "$demo" = demo ] && echo 1 || echo)" \
      xcrun simctl launch "$UDID" "$BUNDLE" >/dev/null
    sleep $((2 + try))
    xcrun simctl io "$UDID" screenshot "$RAW/$name.png" >/dev/null 2>&1
    if valid_shot "$RAW/$name.png"; then echo "  ✓ $name"; return 0; fi
    echo "  … $name looked wrong, retry $try"
  done
  echo "  ✗ $name FAILED validation — refusing to ship a frame I cannot verify"; return 1
}

# Home screen first, so the first launch carries no "◄ PrevApp" status-bar breadcrumb.
xcrun simctl launch "$UDID" com.apple.springboard >/dev/null 2>&1 || true
sleep 1.2

echo "▶ capturing $LOC/$PLATFORM"
for s in "${SCENES[@]}"; do
  IFS=':' read -r n t b d <<< "$s"
  shot "$n" "$t" "$b" "$d"
done
xcrun simctl terminate "$UDID" "$BUNDLE" 2>/dev/null || true
xcrun simctl status_bar "$UDID" clear 2>/dev/null || true

if [ -f "$PARAMS" ]; then
  echo "▶ framing"
  ( cd "$ROOT/marketing" && "$PY" generate_screenshots.py "$PARAMS" )
  echo "done → $APP/marketing/aso/$LOC/$PLATFORM/"
else
  echo "⚠ no params at $PARAMS — raws are in $RAW"
fi
