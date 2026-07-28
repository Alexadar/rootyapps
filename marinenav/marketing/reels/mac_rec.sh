#!/usr/bin/env bash
#
# mac_rec.sh — Marine Nav's parameters for the SHARED Mac store recorder.
#
# This is a wrapper, deliberately NOT a copy: all the logic (ScreenCaptureKit single-window
# capture, LaunchServices launch, fill-the-frame conform, concat) lives in
# marketing/reels/mac_store_rec.sh and is called in place, so fixes there reach this app.
# CLAUDE.md: "Never fork these scripts into an app directory."
#
# Only three things are app-specific:
#   TOOL_ARG   Marine Nav picks its opening tool from a launch ARGUMENT (ContentView.initialTool
#              reads `-tool <raw>`), not from an env var like the other apps.
#   CROP       an exact 16:9 region of the 2200x1520 window. x=12 clears the rounded corners and
#              shadow (dark edge bands read as framing under 2.3.4); y=110 drops the empty title
#              bar, which the default width-scale + top-crop kept at the cost of slicing the tide
#              chart in half. 2176/1224 is exactly 16:9, so the scale is pure resampling.
#   PRE_LAUNCH pin the app to `day` so the video matches the light Mac screenshots even though
#              this machine runs Dark.
#
#   SECS=6 marinenav/marketing/reels/mac_rec.sh
#
set -euo pipefail
ROOT=/Users/oleksandr/Projects/rootyapps

APP_DIR="$ROOT/marinenav" \
APP_NAME="Marine Nav" \
SCHEME=marinenav \
TOOL_ARG="-tool" \
SCENES="${SCENES:-tides currents declination distanceBearing sightReduction}" \
SECS="${SECS:-6}" \
CROP="2176:1224:12:110" \
PRE_LAUNCH='defaults write oleksandr.aisixteen.marinenav marine.mode day' \
  exec "$ROOT/marketing/reels/mac_store_rec.sh"
