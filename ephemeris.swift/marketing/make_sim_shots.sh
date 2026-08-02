#!/usr/bin/env bash
#
# make_sim_shots.sh — raw iPhone/iPad captures into marketing/raw/<locale>/<platform>.
#
#   PLATFORM=ios  ./make_sim_shots.sh de fr ja
#   PLATFORM=ipad ./make_sim_shots.sh de fr ja
#
# One fresh launch per screen: the tab is chosen at launch via EPHEMERIS_TAB rather than by
# tapping, so a capture can never race an in-flight animation. Environment reaches the app
# through simctl's SIMCTL_CHILD_ prefix.
#
# The status bar is pinned to 9:41 / full bars / full battery — Apple's own marketing
# convention, and it stops a real low-battery icon from dating the screenshots.
#
# iPhone ships 4 screens and iPad 5; the counts must match captions.json or gen_params.py
# refuses to stamp the params.
set -uo pipefail

ROOT=/Users/oleksandr/Projects/rootyapps
APP_DIR="$ROOT/ephemeris.swift"
BUNDLE=oleksandr.aisixteen.ephemeris
PLATFORM="${PLATFORM:-ios}"

if [ "$PLATFORM" = ipad ]; then
  SIM_NAME="${SIM_NAME:-Ephemeris-iPadPro13}"
  NAMES=(01_chart 02_positions 03_aspects 04_cycle 05_events); TABS=(0 1 2 3 4)
else
  SIM_NAME="${SIM_NAME:-Ephemeris-iPhone17ProMax}"   # 6.9"
  NAMES=(01_chart 02_positions 03_aspects 04_cycle);           TABS=(0 1 2 3)
fi

place_for() {
  case "$1" in
    de) echo "Europe/Berlin|52.52|13.405|Berlin" ;;
    fr) echo "Europe/Paris|48.857|2.352|Paris" ;;
    ja) echo "Asia/Tokyo|35.690|139.692|Tokyo" ;;
    *)  echo "America/Los_Angeles|34.052|-118.244|Los Angeles" ;;
  esac
}

# Resolved by name, never a hardcoded UDID: a re-created simulator gets a new UDID, and a
# stale one silently falls through to whichever device matches first — possibly another
# app's. Exit loudly instead.
UDID=$(xcrun simctl list devices | grep "$SIM_NAME (" | grep -oE "[0-9A-F-]{36}" | head -1)
[ -n "$UDID" ] || { echo "simulator '$SIM_NAME' not found — create it first" >&2; exit 1; }
echo "simulator $SIM_NAME = $UDID"
DD="$APP_DIR/build/dd-shots-$PLATFORM"
xcrun simctl boot "$UDID" 2>/dev/null || true
xcrun simctl bootstatus "$UDID" -b >/dev/null
echo "building for ${PLATFORM}…"   # braced: a bare $PLATFORM… swallows the ellipsis into the name
( cd "$APP_DIR" && xcodebuild -project ephemeris.swift.xcodeproj -scheme ephemeris.swift \
    -destination "id=$UDID" -derivedDataPath "$DD" build >/dev/null 2>&1 ) \
  || { echo "build failed" >&2; exit 1; }
APP_PATH=$(find "$DD/Build/Products" -maxdepth 2 -name 'Ephemeris.app' | head -1)
xcrun simctl install "$UDID" "$APP_PATH"
xcrun simctl status_bar "$UDID" override --time "9:41" \
  --cellularMode active --cellularBars 4 --wifiMode active --wifiBars 3 --batteryState charged --batteryLevel 100

# Throwaway launch, discarded. If another app (a sibling app's capture run) was last in the
# foreground, iOS shows a "◀ Earth Around" return-to-app breadcrumb in the status bar — and it
# survives into our FIRST launch only, so shot 01 of each run would ship with another product's
# name on it. status_bar override does not suppress it; burning one launch does.
xcrun simctl launch "$UDID" "$BUNDLE" >/dev/null 2>&1 || true
sleep 3
xcrun simctl terminate "$UDID" "$BUNDLE" 2>/dev/null || true
sleep 1

for LOC in "${@:-de fr ja}"; do
  IFS='|' read -r TZ LAT LON PLACE <<<"$(place_for "$LOC")"
  DEST="$APP_DIR/marketing/raw/$LOC/$PLATFORM"
  mkdir -p "$DEST"
  echo "=== $LOC / $PLATFORM ($PLACE)"
  for i in "${!TABS[@]}"; do
    xcrun simctl terminate "$UDID" "$BUNDLE" 2>/dev/null || true
    SIMCTL_CHILD_EPHEMERIS_LANG="$LOC" \
    SIMCTL_CHILD_EPHEMERIS_TAB="${TABS[$i]}" \
    SIMCTL_CHILD_EPHEMERIS_TZ="$TZ" \
    SIMCTL_CHILD_EPHEMERIS_LAT="$LAT" \
    SIMCTL_CHILD_EPHEMERIS_LON="$LON" \
    SIMCTL_CHILD_EPHEMERIS_PLACE="$PLACE" \
      xcrun simctl launch "$UDID" "$BUNDLE" >/dev/null
    sleep 4
    xcrun simctl io "$UDID" screenshot --type=png "$DEST/${NAMES[$i]}.png" >/dev/null 2>&1 \
      && echo "    ${NAMES[$i]}.png" || echo "    ${NAMES[$i]}.png FAILED"
  done
  xcrun simctl terminate "$UDID" "$BUNDLE" 2>/dev/null || true
done
