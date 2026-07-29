#!/usr/bin/env bash
# Par — macOS App Store screenshots.
#
# Uses marketing/tools/capture_mac_window.sh, which launches the binary inside the bundle, waits for
# THAT pid to own a window, and composites it via ScreenCaptureKit. That matters for three reasons:
# it photographs Par's window rather than whatever is in front of it, it works while the machine is
# in use, and it kills only the instance it started — so a parallel capture elsewhere survives.
#
# The binary is the Capture configuration. Par's shipping build is a DocumentGroup app that opens a
# document browser first, which is no use for a screenshot; PAR_CAPTURE opens straight onto a
# calculator with a seeded tape beside it.
#
#   bash marketing/make_mac_shots.sh
set -euo pipefail

ROOT=/Users/oleksandr/Projects/rootyapps
APP_DIR="$ROOT/par"
PY=/Users/oleksandr/miniconda3/envs/fantastic/bin/python
APP="$APP_DIR/build/dd-mac/Build/Products/Capture/Par.app"
CAP="$ROOT/marketing/tools/capture_mac_window.sh"
RAW="$APP_DIR/marketing/raw/mac"; mkdir -p "$RAW"; rm -f "$RAW"/*.png

[ -d "$APP" ] || { echo "❌ build first: xcodebuild -scheme Par -configuration Capture -destination 'platform=macOS' -derivedDataPath build/dd-mac build"; exit 1; }

# en_US for the same reason the simulator captures force it: the machine's own locale renders 6.25
# as "6,250" and 420000 as "420 000,00" — correct there, wrong for a US listing.
export LAUNCH_ARGS='-AppleLanguages (en) -AppleLocale en_US'

# The same six tools as the iPad set: at a regular width the tape is already beside the calculator,
# so no slot is spent showing it alone.
for scene in 01_tvm:tvm 02_amortization:amortization 03_cashflow:cashflow \
             04_bond:bond 05_dates:dates 06_realestate:realestate; do
  name="${scene%%:*}"; tool="${scene##*:}"
  echo "  · $name (PAR_TOOL=$tool)"
  SETTLE=3 bash "$CAP" "$APP" "$RAW/$name.png" "PAR_TOOL=$tool" >/dev/null
done

echo "▸ framing"
( cd "$ROOT/marketing" && "$PY" generate_screenshots.py "$APP_DIR/marketing/aso/mac/params.yaml" )
echo "✅ $APP_DIR/marketing/aso/mac/"
