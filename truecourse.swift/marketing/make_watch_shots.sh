#!/bin/bash
# TrueCourse — Apple Watch App Store screenshots from the simulator.
# One fresh, deep-linked launch per tool (TRUECOURSE_TOOL); then framed with titles by the shared
# Python engine. 416x496 = Series 10 46mm = the APP_WATCH_SERIES_10 store slot.
#   bash marketing/make_watch_shots.sh
set -euo pipefail

ROOT=/Users/oleksandr/Projects/rootyapps
APP="$ROOT/truecourse.swift"
PY=/Users/oleksandr/miniconda3/envs/fantastic/bin/python
BUNDLE=oleksandr.aisixteen.truecourse.watchkitapp
UDID=92FFCA5A-563B-4168-8C8D-0996661EAF5D          # TrueCourse-Watch (Series 10 46mm)
RAW="$APP/marketing/raw/watch"

# name:tool  — order must match aso/watch/params.yaml `texts`.
SCENES=("01_wind:wind" "02_altitude:altitude" "03_fuel:fuel" "04_wb:wb" "05_convert:convert")
DD="$APP/build/dd-watch-shots"
mkdir -p "$RAW"; rm -f "$RAW"/*.png

( cd "$APP" && xcodegen generate >/dev/null )
xcrun simctl boot "$UDID" 2>/dev/null || true
xcrun simctl bootstatus "$UDID" -b
xcodebuild -scheme TrueCourseWatch -destination "id=$UDID" -derivedDataPath "$DD" build >/dev/null
APPPATH=$(find "$DD/Build/Products" -maxdepth 2 -name "TrueCourse.app" -path "*watchsimulator*" | head -1)
[ -n "$APPPATH" ] || { echo "watch .app not found in $DD" >&2; exit 1; }
xcrun simctl uninstall "$UDID" "$BUNDLE" >/dev/null 2>&1 || true
xcrun simctl install "$UDID" "$APPPATH" >/dev/null

shot(){  # name  tool
  xcrun simctl terminate "$UDID" "$BUNDLE" 2>/dev/null || true; sleep 0.5
  SIMCTL_CHILD_TRUECOURSE_TOOL="$2" xcrun simctl launch "$UDID" "$BUNDLE" >/dev/null
  sleep 5
  xcrun simctl io "$UDID" screenshot --type=png "$RAW/$1.png" >/dev/null \
    && echo "  ✓ $1  $($PY -c "from PIL import Image; print('x'.join(map(str, Image.open('$RAW/$1.png').size)))" 2>/dev/null)"
}

for s in "${SCENES[@]}"; do
  IFS=: read -r nm tool <<< "$s"
  shot "$nm" "$tool"
done
xcrun simctl terminate "$UDID" "$BUNDLE" 2>/dev/null || true

echo "Framing…"
( cd "$ROOT/marketing" && "$PY" generate_screenshots.py "$APP/marketing/aso/watch/params.yaml" )
echo "Done → $APP/marketing/aso/watch/"
