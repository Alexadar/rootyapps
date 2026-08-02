#!/usr/bin/env bash
#
# make_watch_shots.sh — App Store screenshots for the Storypole watch app.
#
# App Store Connect takes Apple Watch screenshots under the SAME app record as the iOS app,
# because the watch app ships embedded in the phone app rather than as its own SKU.
#
#   ./make_watch_shots.sh          → marketing/raw/en/watch/  (Series 10, 46mm — 416x496)
#   WATCH=ultra ./make_watch_shots.sh   → Ultra 3, 49mm (448x552)
#
# Screens are chosen with STORYPOLE_WATCH_TOOL, since the watch app resumes the last-used tool and
# would otherwise capture whatever the previous run left behind. `list` selects the catalog.
#
# NOTE ON VALIDATION: the watch UI resolves to the DARK token set (`Color(light:dark:)` returns the
# dark value on watchOS), so unlike the phone this frame is dark. The check is inverted again —
# copying the phone's `mean > 150` here would reject every good frame.
#
set -euo pipefail
ROOT=/Users/oleksandr/Projects/rootyapps
APP=$ROOT/storypole
PY=/Users/oleksandr/miniconda3/envs/fantastic/bin/python
BUNDLE=oleksandr.aisixteen.storypole.watchkitapp

case "${WATCH:-s6}" in
  ultra) SIM_NAME=SP-WatchUltra; TYPE=com.apple.CoreSimulator.SimDeviceType.Apple-Watch-Ultra-3-49mm ;;
  s10)   SIM_NAME=SP-Watch;      TYPE=com.apple.CoreSimulator.SimDeviceType.Apple-Watch-Series-10-46mm ;;
  # DEFAULT — 368x448, the ONLY watch size App Store Connect actually requires.
  # Submission fails with STATE_ERROR.SCREENSHOT_REQUIRED.APP_WATCH_SERIES_4 if this set is
  # missing, and a Series 10 capture (416x496) does NOT satisfy it — different slot.
  s6|*)  SIM_NAME=SP-Watch44;    TYPE=com.apple.CoreSimulator.SimDeviceType.Apple-Watch-Series-6-44mm ;;
esac
RAW="$APP/marketing/raw/en/watch${WATCHSUFFIX:-}"; mkdir -p "$RAW"; rm -f "$RAW"/*.png
DD="$APP/build/dd-watch-shots"

UDID=$(xcrun simctl list devices | grep "$SIM_NAME (" | grep -oE "[0-9A-Fa-f-]{36}" | head -1 || true)
if [ -z "$UDID" ]; then
  UDID=$(xcrun simctl create "$SIM_NAME" "$TYPE" com.apple.CoreSimulator.SimRuntime.watchOS-26-5)
  echo "created $SIM_NAME $UDID"
fi
xcrun simctl boot "$UDID" 2>/dev/null || true
xcrun simctl bootstatus "$UDID" -b >/dev/null

echo "▶ build + install watch app"
xcodebuild -scheme StorypoleWatch -destination "id=$UDID" -derivedDataPath "$DD" \
  build CODE_SIGNING_ALLOWED=NO >/dev/null
APPPATH=$(find "$DD/Build/Products" -maxdepth 2 -name "Storypole.app" -path "*watchsimulator*" | head -1)
[ -n "$APPPATH" ] || { echo "❌ no watch app built"; exit 1; }
xcrun simctl install "$UDID" "$APPPATH" >/dev/null

valid(){ "$PY" - "$1" <<'PYEOF'
import sys
from PIL import Image
import numpy as np
a = np.asarray(Image.open(sys.argv[1]).convert("RGB")).astype(float)
mean, std = a.mean(), a.std()
# watchOS resolves Storypole's tokens to the DARK set — inverse of the phone check.
ok = mean < 120 and std > 8
print(f"    mean={mean:.1f} std={std:.1f} -> {'ok' if ok else 'REJECT'}", file=sys.stderr)
sys.exit(0 if ok else 1)
PYEOF
}

shot(){  # name  tool  demo
  local name="$1" tool="$2" demo="${3:-}" try
  for try in 1 2 3; do
    xcrun simctl terminate "$UDID" "$BUNDLE" 2>/dev/null || true; sleep 0.7
    SIMCTL_CHILD_STORYPOLE_LANG=en SIMCTL_CHILD_STORYPOLE_WATCH_TOOL="$tool" \
    SIMCTL_CHILD_STORYPOLE_DEMO="$([ "$demo" = demo ] && echo 1 || echo)" \
      xcrun simctl launch "$UDID" "$BUNDLE" >/dev/null
    sleep $((2 + try))
    xcrun simctl io "$UDID" screenshot "$RAW/$name.png" >/dev/null 2>&1
    if valid "$RAW/$name.png"; then echo "  ✓ $name"; return 0; fi
    echo "  … $name looked wrong, retry $try"
  done
  echo "  ✗ $name FAILED validation"; return 1
}

echo "▶ capturing watch"
shot 01_tape      tapeCalc  demo
shot 02_convert   convert
shot 03_pitch     roofPitch
shot 04_list      list
xcrun simctl terminate "$UDID" "$BUNDLE" 2>/dev/null || true

PARAMS="$APP/marketing/aso/en/watch/params.yaml"
if [ -f "$PARAMS" ]; then
  echo "▶ framing"; ( cd "$ROOT/marketing" && "$PY" generate_screenshots.py "$PARAMS" )
else
  echo "raws in $RAW (no params.yaml — watch frames often ship unframed)"
fi
echo "done"
