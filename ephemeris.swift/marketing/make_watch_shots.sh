#!/usr/bin/env bash
#
# make_watch_shots.sh [locale …] — raw Apple Watch captures into marketing/raw/<locale>/watch.
#
# 416x496 is the Series 10 46mm size, which is the APP_WATCH_SERIES_10 App Store slot. Captured
# on a simulator rather than the paired device because the store wants exact pixel dimensions and
# a real watch screenshot arrives via the phone at whatever size that watch happens to be.
#
# The opening screen is chosen with EPHEMERIS_SCREEN so all four come from one build; without it
# each screenshot would need its own compile.
set -uo pipefail

ROOT=/Users/oleksandr/Projects/rootyapps
APP_DIR="$ROOT/ephemeris.swift"
BUNDLE=oleksandr.aisixteen.ephemeris.watchkitapp
SIM_NAME="${SIM_NAME:-Ephemeris-Watch46}"

SCREENS=(wheel now positions events)
NAMES=(01_chart 02_now 03_positions 04_events)

place_for() {
  case "$1" in
    de) echo "Europe/Berlin|52.52|13.405|Berlin" ;;
    fr) echo "Europe/Paris|48.857|2.352|Paris" ;;
    ja) echo "Asia/Tokyo|35.690|139.692|Tokyo" ;;
    *)  echo "America/Los_Angeles|34.052|-118.244|Los Angeles" ;;
  esac
}

UDID=$(xcrun simctl list devices | grep "$SIM_NAME (" | grep -oE "[0-9A-F-]{36}" | head -1)
[ -n "$UDID" ] || { echo "simulator '$SIM_NAME' not found" >&2; exit 1; }
xcrun simctl boot "$UDID" 2>/dev/null; xcrun simctl bootstatus "$UDID" -b >/dev/null 2>&1

DD="$APP_DIR/.build/watch46"
( cd "$APP_DIR" && xcodebuild -project ephemeris.swift.xcodeproj -scheme EphemerisWatch \
    -destination "id=$UDID" -derivedDataPath "$DD" build -allowProvisioningUpdates >/dev/null 2>&1 ) \
  || { echo "build failed" >&2; exit 1; }
APP=$(find "$DD/Build/Products" -maxdepth 2 -name 'Ephemeris.app' -path "*watchsimulator*" | head -1)

for LOC in "${@:-en}"; do
  IFS='|' read -r TZ LAT LON PLACE <<<"$(place_for "$LOC")"
  DEST="$APP_DIR/marketing/raw/$LOC/watch"
  mkdir -p "$DEST"
  echo "=== watch / $LOC ($PLACE)"
  xcrun simctl uninstall "$UDID" "$BUNDLE" >/dev/null 2>&1
  xcrun simctl install "$UDID" "$APP" >/dev/null 2>&1
  for i in "${!SCREENS[@]}"; do
    xcrun simctl terminate "$UDID" "$BUNDLE" 2>/dev/null
    SIMCTL_CHILD_EPHEMERIS_SCREEN="${SCREENS[$i]}" \
    SIMCTL_CHILD_EPHEMERIS_LANG="$LOC" \
    SIMCTL_CHILD_EPHEMERIS_TZ="$TZ" SIMCTL_CHILD_EPHEMERIS_LAT="$LAT" \
    SIMCTL_CHILD_EPHEMERIS_LON="$LON" SIMCTL_CHILD_EPHEMERIS_PLACE="$PLACE" \
      xcrun simctl launch "$UDID" "$BUNDLE" >/dev/null 2>&1
    sleep 6
    xcrun simctl io "$UDID" screenshot --type=png "$DEST/${NAMES[$i]}.png" >/dev/null 2>&1 \
      && echo "    ${NAMES[$i]}.png  $(python3 -c "
from PIL import Image; print('x'.join(map(str, Image.open('$DEST/${NAMES[$i]}.png').size)))" 2>/dev/null)" \
      || echo "    ${NAMES[$i]}.png FAILED"
  done
  xcrun simctl terminate "$UDID" "$BUNDLE" 2>/dev/null
done
echo "WATCH SHOTS DONE"
