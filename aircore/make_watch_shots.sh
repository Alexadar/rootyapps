#!/usr/bin/env bash
#
# make_watch_shots.sh — Apple Watch App Store screenshots for AirCore.
#
# The wrist is ONE screen, so the shots are its STATES, not a tour of tools: the glance, the crown
# on the other field, and the state the phone sent. Each is a fresh launch carrying AIRCORE_WRIST
# (see WatchRootView.Seed) — the seed sets the two inputs and nothing else, so every number in the
# frame is still solved by PsychroKit at capture time.
#
# TWO SLOTS, and the default is the one that gates submission:
#   WATCH=s4  (default) Series 6 44mm -> 368x448 -> APP_WATCH_SERIES_4   ← REQUIRED
#   WATCH=s10           Series 10 46mm -> 416x496 -> APP_WATCH_SERIES_10  (optional, bigger)
# Submission fails with STATE_ERROR.SCREENSHOT_REQUIRED.APP_WATCH_SERIES_4 when the 368x448 set is
# missing, and a Series 10 capture does NOT satisfy it — different slot, not merely a larger image.
# Learned on Storypole; this script defaults to the required one so a run that ignores the flag
# still produces the set that matters.
#
# The simulator is created here and DELETED at the end — one sim per app, never a shared one, so a
# concurrent session capturing another app cannot end up with AirCore's frames.
#
#   bash make_watch_shots.sh
#
set -euo pipefail
ROOT=/Users/oleksandr/Projects/rootyapps
APP="$ROOT/aircore"
PY=/Users/oleksandr/miniconda3/envs/fantastic/bin/python
BUNDLE=oleksandr.aisixteen.aircore.watchkitapp
case "${WATCH:-s4}" in
  s10) DEVTYPES="Apple-Watch-Series-11-46mm Apple-Watch-Series-10-46mm"; SUFFIX=46 ;;
  s4|*) DEVTYPES="Apple-Watch-Series-6-44mm Apple-Watch-SE-44mm-2nd-generation"; SUFFIX= ;;
esac
RAW="$APP/marketing/raw/en/watch${SUFFIX}"
DD="$APP/build/dd-watch-shots"
SIM_NAME=AIRC-Watch-Shots

# name:seed — seed is "<dry bulb °C>,<RH 0…1>,<focused field>,<phone state 0|1>".
# Order must match marketing/aso/en/watch/params.yaml `texts`.
SCENES=(
  "01_glance:23.888888888888889,0.5,relativeHumidity,0"    # 75 °F / 50 % — the table case
  "02_crown:35.0,0.4,dryBulb,0"                            # 95 °F / 40 % — focus on dry bulb
  "03_phone:23.888888888888889,0.5,relativeHumidity,1"     # plus what the phone last solved
)

mkdir -p "$RAW"; rm -f "$RAW"/*.png

RUNTIME=$(xcrun simctl list runtimes | awk '/^watchOS/ {print $NF}' | tail -1)
[ -n "$RUNTIME" ] || { echo 'no available watchOS runtime' >&2; exit 1; }

# Try to create, do NOT ask `isCreatable` first: every Apple Watch device type reports
# isCreatable=false on this Xcode and every one of them creates fine. Gating on the flag skipped
# the whole list and failed with "no creatable device type" on a machine that can make all of them.
xcrun simctl delete "$SIM_NAME" >/dev/null 2>&1 || true
UDID=""
for dt in $DEVTYPES; do
  UDID=$(xcrun simctl create "$SIM_NAME" "com.apple.CoreSimulator.SimDeviceType.$dt" "$RUNTIME" 2>/dev/null) && break
  UDID=""
done
[ -n "$UDID" ] || { echo "could not create an Apple Watch simulator from: $DEVTYPES" >&2; exit 1; }
cleanup(){ xcrun simctl shutdown "$UDID" >/dev/null 2>&1 || true
           xcrun simctl delete "$UDID" >/dev/null 2>&1 || true; }
trap cleanup EXIT

# US formatting, pinned at the device rather than inherited from this machine — the Mac recording
# shipped "86,6 °F" for a US-only listing before this was pinned everywhere it is captured.
#
# BEFORE the boot, not after. A booted simulator has already read .GlobalPreferences into cfprefsd,
# so a write at that point is ignored for the rest of the session — the first run of this script
# wrote en_US to a booted device and captured "55,1 °F" anyway.
PLIST="$HOME/Library/Developer/CoreSimulator/Devices/$UDID/data/Library/Preferences/.GlobalPreferences.plist"
mkdir -p "$(dirname "$PLIST")"
/usr/libexec/PlistBuddy -c "Add :AppleLocale string en_US" "$PLIST" 2>/dev/null \
  || /usr/libexec/PlistBuddy -c "Set :AppleLocale en_US" "$PLIST"
/usr/libexec/PlistBuddy -c "Add :AppleLanguages array" "$PLIST" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Add :AppleLanguages:0 string en-US" "$PLIST" 2>/dev/null || true

xcrun simctl boot "$UDID"
xcrun simctl bootstatus "$UDID" -b
# 9:41, to match the iPhone and iPad frames. Best-effort: not every runtime accepts a status-bar
# override, and a real clock in the corner is not worth failing a capture run over.
xcrun simctl status_bar "$UDID" override --time "9:41" >/dev/null 2>&1 || echo "  (status bar override unavailable)"

( cd "$APP" && xcodegen generate >/dev/null )
xcodebuild -project "$APP/aircore.xcodeproj" -scheme AirCoreWatch -destination "id=$UDID" \
  -derivedDataPath "$DD" build >/dev/null
APPPATH=$(find "$DD/Build/Products" -maxdepth 2 -name "AirCore.app" -path "*watchsimulator*" | head -1)
[ -n "$APPPATH" ] || { echo "watch .app not found in $DD" >&2; exit 1; }
xcrun simctl install "$UDID" "$APPPATH" >/dev/null

shot(){  # name  seed
  xcrun simctl terminate "$UDID" "$BUNDLE" >/dev/null 2>&1 || true; sleep 0.6
  SIMCTL_CHILD_AIRCORE_WRIST="$2" xcrun simctl launch "$UDID" "$BUNDLE" >/dev/null
  sleep 5
  xcrun simctl io "$UDID" screenshot --type=png "$RAW/$1.png" >/dev/null
  # Verify the pixels, not the sleep: the watch ground is black, so a frame that has not drawn is
  # black too — mean alone cannot tell them apart, but a drawn frame has contrast and a blank one
  # has none.
  "$PY" - "$RAW/$1.png" <<'PYEOF' || { echo "  ✗ $1 — frame looks blank"; return 1; }
import sys
from PIL import Image
import numpy as np
a = np.asarray(Image.open(sys.argv[1]).convert("RGB")).astype(float)
sys.exit(0 if a.std() > 18 else 1)
PYEOF
  echo "  ✓ $1  $("$PY" -c "from PIL import Image; print('x'.join(map(str, Image.open('$RAW/$1.png').size)))")"
}

echo "▶ capturing watch screens"
for s in "${SCENES[@]}"; do shot "${s%%:*}" "${s#*:}"; done
xcrun simctl terminate "$UDID" "$BUNDLE" >/dev/null 2>&1 || true

echo "▶ framing"
( cd "$ROOT/marketing" && "$PY" generate_screenshots.py "$APP/marketing/aso/en/watch${SUFFIX}/params.yaml" )
echo "done → $APP/marketing/aso/en/watch${SUFFIX}/"
