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
# iPhone ships 8 screens and iPad 9; the counts must match captions.json or gen_params.py
# refuses to stamp the params.
set -uo pipefail

ROOT=/Users/oleksandr/Projects/rootyapps
APP_DIR="$ROOT/ephemeris.swift"
BUNDLE=oleksandr.aisixteen.ephemeris
PLATFORM="${PLATFORM:-ios}"

# ── The shot list ────────────────────────────────────────────────────────────
#
#   name | EPHEMERIS_TAB | EPHEMERIS_LENS | EPHEMERIS_CHART | EPHEMERIS_TRANSITS | EPHEMERIS_FACET | EPHEMERIS_PARTNER
#
# Order is the store's listing order, and the first three are what search results show — so the
# first three are the subtitle, made visible: natal chart, transits, houses. The live sky follows;
# it is what the app was, and it is still the reason the numbers are trustworthy, but it is no
# longer the thing being sold. The rest is evidence: positions, aspects, the synodic cycle.
#
# Natal shots address the seeded fixture by **UUID prefix**, never by row index: the library sorts
# by modifiedAt and the fixtures share an instant, so a row index picks a different person per run.
# `1111…` is Olena, born 1990-03-15 14:30 in Berlin — timed, so her chart has houses and angles.
# Nothing here is a real person's birth data.
#
# A shot with a chart id implies EPHEMERIS_SEED_CHARTS; the loop sets it.
if [ "$PLATFORM" = ipad ]; then
  SIM_NAME="${SIM_NAME:-Ephemeris-iPadPro13}"
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
else
  SIM_NAME="${SIM_NAME:-Ephemeris-iPhone17ProMax}"   # 6.9"
  # Eight on the phone. Events is the one dropped: the timeline reads as a bare list of dates
  # without the width to show what they are, and the practitioner surfaces earn the slot.
  SHOTS=(
    "01_natal|5|wheel|11111111||wheel|"
    "02_transits|5|wheel|11111111||biwheel|"
    "03_synastry|5|wheel|11111111||wheel|22222222"
    "04_analysis|5|wheel|11111111||analysis|"
    "05_returns|5|wheel|11111111||returns|"
    "06_houses|5|houses|11111111||wheel|"
    "07_sky|0|||||"
    "08_aspects|2|||||"
  )
fi

# Proves the frame actually shows the app.
#
# `simctl io screenshot` succeeds and writes a valid PNG whether or not the app has drawn — so a
# shot taken while the app is still launching is a blank white page with an exit code of 0 and a
# filename in the log that looks exactly like the six good ones beside it. That is how one such
# frame reached this run: en/ipad/01_sky was 99.9% white on a cold simulator.
#
# The app's every screen is a dark star field, so brightness is a sufficient discriminator: a
# capture that is mostly light did not render. Retried once — the cause is a race, not a defect —
# and fatal if it happens twice, because the alternative is a white rectangle in the App Store.
check_rendered() {
  local f="$1"
  python3 - "$f" <<'PY' || { echo "    ^ blank frame, retrying once"; return 1; }
import sys
from PIL import Image
px = list(Image.open(sys.argv[1]).convert("L").resize((160, 160)).getdata())
sys.exit(1 if sum(1 for p in px if p > 170) / len(px) > 0.25 else 0)
PY
}

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
# Constrained to the iOS-simulator products dir. The watch app is ALSO called Ephemeris.app and
# also sits under Build/Products, so an unfiltered `find … | head -1` picks whichever the
# filesystem lists first — and when it picks the watch one, simctl refuses it ("compatible with (4)
# but this device supports (1)") and the run carries on screenshotting whatever was already
# installed. Seven files appear, the log ends in success, and the images are of the previous build.
APP_PATH=$(find "$DD/Build/Products" -maxdepth 2 -path '*iphonesimulator*' -name 'Ephemeris.app' | head -1)
[ -n "$APP_PATH" ] || { echo "no iOS-simulator Ephemeris.app under $DD/Build/Products" >&2; exit 1; }
# Fatal, not a warning: a failed install means every shot below is of the OLD binary.
xcrun simctl install "$UDID" "$APP_PATH" \
  || { echo "install failed — refusing to shoot a stale build" >&2; exit 1; }
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
  # Clear the previous shot plan's captures FIRST. Nothing downstream deletes, and the framer pairs
  # captions to captures by sorted filename taking the first N — so one leftover `01_chart.png`
  # sitting beside the new `01_sky.png` shifts every caption by one and ships a confident line over
  # the wrong screen. Only the top-level PNGs go; `video/` underneath is a different pipeline.
  rm -f "$DEST"/*.png
  echo "=== $LOC / $PLATFORM ($PLACE)"
  for SHOT in "${SHOTS[@]}"; do
    IFS='|' read -r NAME TAB LENS CHART TRANSITS FACET PARTNER <<<"$SHOT"
    xcrun simctl terminate "$UDID" "$BUNDLE" 2>/dev/null || true
    # Only exported when non-empty: LaunchOverride treats an empty value as absent, but an empty
    # EPHEMERIS_LENS would still shadow nothing while an empty EPHEMERIS_CHART reads as "no match"
    # — being explicit here is cheaper than reasoning about that at every call site.
    ENVV=(
      SIMCTL_CHILD_EPHEMERIS_LANG="$LOC"
      SIMCTL_CHILD_EPHEMERIS_TAB="$TAB"
      SIMCTL_CHILD_EPHEMERIS_TZ="$TZ"
      SIMCTL_CHILD_EPHEMERIS_LAT="$LAT"
      SIMCTL_CHILD_EPHEMERIS_LON="$LON"
      SIMCTL_CHILD_EPHEMERIS_PLACE="$PLACE"
    )
    [ -n "$LENS" ]     && ENVV+=(SIMCTL_CHILD_EPHEMERIS_LENS="$LENS")
    [ -n "$TRANSITS" ] && ENVV+=(SIMCTL_CHILD_EPHEMERIS_TRANSITS="$TRANSITS")
    [ -n "$FACET" ]    && ENVV+=(SIMCTL_CHILD_EPHEMERIS_FACET="$FACET")
    # A partner implies the seeded library too — the pairing needs two charts.
    [ -n "$PARTNER" ]  && ENVV+=(SIMCTL_CHILD_EPHEMERIS_PARTNER="$PARTNER"
                                 SIMCTL_CHILD_EPHEMERIS_SEED_CHARTS=1)
    # The seeded library is invented people at fixed instants — a capture must never be able to
    # reach the developer's real iCloud charts and put someone's birth data on the App Store.
    [ -n "$CHART" ]    && ENVV+=(SIMCTL_CHILD_EPHEMERIS_CHART="$CHART"
                                 SIMCTL_CHILD_EPHEMERIS_SEED_CHARTS=1)
    # Natal shots push a detail screen after the library's `.task` loads, so they need longer than
    # a top-level tab that is already on screen at first frame.
    [ -n "$CHART" ] && SETTLE=6 || SETTLE=4
    for ATTEMPT in 1 2; do
      env "${ENVV[@]}" xcrun simctl launch "$UDID" "$BUNDLE" >/dev/null
      sleep "$SETTLE"
      xcrun simctl io "$UDID" screenshot --type=png "$DEST/${NAME}.png" >/dev/null 2>&1 \
        && echo "    ${NAME}.png" || echo "    ${NAME}.png FAILED"
      check_rendered "$DEST/${NAME}.png" && break
      [ "$ATTEMPT" = 2 ] && { echo "    ${NAME}.png STILL BLANK — refusing to ship it" >&2; exit 1; }
      xcrun simctl terminate "$UDID" "$BUNDLE" 2>/dev/null || true
      SETTLE=$((SETTLE + 6))
    done
  done
  xcrun simctl terminate "$UDID" "$BUNDLE" 2>/dev/null || true
done
