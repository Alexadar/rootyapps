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

# name | TAB | LENS | CHART | TRANSITS | FACET | PARTNER
#
# Matches the caption order in captions.json — `mac` there is 8 long, and gen_params.py refuses to
# stamp the params if the counts disagree. Same order and same reasoning as make_sim_shots.sh:
# natal, transits and houses lead because they are what the subtitle now promises and what an App
# Store search result shows.
#
# Natal shots address the seeded fixture by UUID prefix, never a row index — `all()` sorts by
# modifiedAt and the fixtures share an instant, so an index picks a different person per run.
SHOTS=(
  "01_natal|5|wheel|11111111||wheel|"
  "02_transits|5|wheel|11111111||biwheel|"
  "03_synastry|5|wheel|11111111||wheel|22222222"
  "04_analysis|5|wheel|11111111||analysis|"
  "05_returns|5|wheel|11111111||returns|"
  "06_houses|5|houses|11111111||wheel|"
  "07_sky|0|||||"
  "08_aspects|2|||||"
  "09_events|4|||||"
)

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
  # The previous shot plan's files must go first. Nothing downstream deletes, and the framer pairs
  # captions to captures by sorted filename taking the first N — so a leftover `01_chart.png` beside
  # the new `01_natal.png` shifts every caption by one. `video/` underneath is a different pipeline.
  rm -f "$DEST"/*.png
  echo "=== $LOC ($PLACE) -> $DEST"
  for SHOT in "${SHOTS[@]}"; do
    IFS='|' read -r NAME TAB LENS CHART TRANSITS FACET PARTNER <<<"$SHOT"
    ENVV=(
      EPHEMERIS_LANG="$LOC" EPHEMERIS_TAB="$TAB"
      EPHEMERIS_TZ="$TZ" EPHEMERIS_LAT="$LAT" EPHEMERIS_LON="$LON" EPHEMERIS_PLACE="$PLACE"
      # Launch as an accessory: the window is drawn and capturable, but the app never takes the
      # foreground. Without this every launch here steals the owner's focus.
      EPHEMERIS_CAPTURE=1
    )
    [ -n "$LENS" ]     && ENVV+=(EPHEMERIS_LENS="$LENS")
    [ -n "$TRANSITS" ] && ENVV+=(EPHEMERIS_TRANSITS="$TRANSITS")
    [ -n "$FACET" ]    && ENVV+=(EPHEMERIS_FACET="$FACET")
    [ -n "$PARTNER" ]  && ENVV+=(EPHEMERIS_PARTNER="$PARTNER" EPHEMERIS_SEED_CHARTS=1)
    # Invented people at fixed instants — a capture must never be able to reach the developer's
    # real iCloud charts and put someone's birth data on the App Store.
    [ -n "$CHART" ]    && ENVV+=(EPHEMERIS_CHART="$CHART" EPHEMERIS_SEED_CHARTS=1)
    "$CAP" "$APP" "$DEST/$NAME.png" "${ENVV[@]}" >/dev/null 2>&1 \
      && echo "    $NAME.png  $(/opt/homebrew/bin/python3 -c "
from PIL import Image; print('x'.join(map(str,Image.open('$DEST/$NAME.png').size)))" 2>/dev/null)" \
      || echo "    $NAME.png FAILED"
  done
done
