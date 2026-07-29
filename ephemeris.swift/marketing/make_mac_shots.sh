#!/usr/bin/env bash
#
# make_mac_shots.sh [locale …] — raw macOS captures into marketing/raw/<locale>/mac.
#
# Uses the shared capture_mac_window.sh rather than plain `screencapture`: that tool launches the
# binary inside the bundle to get an exact pid, then composites THAT window alone via
# ScreenCaptureKit. Plain screencapture photographs whatever is in front, so a notification or a
# second copy of the app lands in the shot instead.
#
# Each locale is shot in a city that belongs to its market — Los Angeles in a German listing reads
# as an untranslated screenshot even when every string is correct. The place is passed by
# environment so nothing is persisted and the developer's own saved location is never disturbed.
#
#   ./make_mac_shots.sh              # de fr ja
#   ./make_mac_shots.sh ja           # one locale
set -uo pipefail

ROOT="/Users/oleksandr/Projects/rootyapps"
APP="$(find ~/Library/Developer/Xcode/DerivedData/ephemeris.swift-*/Build/Products/Debug \
        -maxdepth 1 -name 'Ephemeris.app' 2>/dev/null | head -1)"
[ -n "$APP" ] || { echo "No built Ephemeris.app — build the macOS scheme first." >&2; exit 1; }
CAP="$ROOT/marketing/tools/capture_mac_window.sh"
OUT_ROOT="$ROOT/ephemeris.swift/marketing/raw"

# tab index → filename. Matches the caption order in captions.json; keep them in step.
TABS=(0 1 2 3 4)
NAMES=(01_chart 02_positions 03_aspects 04_cycle 05_events)

place_for() {
  case "$1" in
    de) echo "Europe/Berlin|52.52|13.405|Berlin" ;;
    fr) echo "Europe/Paris|48.857|2.352|Paris" ;;
    ja) echo "Asia/Tokyo|35.690|139.692|Tokyo" ;;
    *)  echo "America/Los_Angeles|34.052|-118.244|Los Angeles" ;;
  esac
}

for LOC in "${@:-de fr ja}"; do
  IFS='|' read -r TZ LAT LON PLACE <<<"$(place_for "$LOC")"
  DEST="$OUT_ROOT/$LOC/mac"
  mkdir -p "$DEST"
  echo "=== $LOC ($PLACE) -> $DEST"
  for i in "${!TABS[@]}"; do
    "$CAP" "$APP" "$DEST/${NAMES[$i]}.png" \
      EPHEMERIS_LANG="$LOC" EPHEMERIS_TAB="${TABS[$i]}" \
      EPHEMERIS_TZ="$TZ" EPHEMERIS_LAT="$LAT" EPHEMERIS_LON="$LON" EPHEMERIS_PLACE="$PLACE" \
      >/dev/null 2>&1 \
      && echo "    ${NAMES[$i]}.png  $(python3 -c "
from PIL import Image; print('x'.join(map(str,Image.open('$DEST/${NAMES[$i]}.png').size)))" 2>/dev/null)" \
      || echo "    ${NAMES[$i]}.png FAILED"
  done
done
