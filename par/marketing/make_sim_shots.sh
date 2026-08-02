#!/usr/bin/env bash
# make_sim_shots.sh — capture raw App Store stills from the simulator.
#
#   boot sim → build → install → clean status bar → per scene: relaunch with PAR_TOOL → screenshot
#
# The deep link is what makes this reproducible: each scene is a launch, not a scripted tap, so a
# reordered picker or a renamed control cannot silently produce five copies of the same screen.
# `ParUITests/DeepLinkTests` pins those slugs, and is the guard that keeps this script honest.
#
# Output lands in marketing/raw/<platform>/NN_name.png — the framing step
# (marketing/generate_screenshots.py) reads that folder and never touches the simulator.
#
#   PLATFORM=ios  bash marketing/make_sim_shots.sh
#   PLATFORM=ipad bash marketing/make_sim_shots.sh
set -euo pipefail

APP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PLATFORM="${PLATFORM:-ios}"

# Par owns these two simulators. The shared Calc-* devices are used by the other calculators in the
# repo, and a capture that shares a booted simulator with another app's run competes for CPU — the
# symptom is a UI-test tour that takes six minutes instead of ninety seconds and times out.
case "$PLATFORM" in
  ios)  SIM_NAME="${SIM_NAME:-Par-iPhone17ProMax}" ;;
  ipad) SIM_NAME="${SIM_NAME:-Par-iPadPro13}" ;;
  *) echo "PLATFORM must be ios or ipad" >&2; exit 2 ;;
esac

SCHEME="${SCHEME:-Par}"
BUNDLE="${BUNDLE:-oleksandr.aisixteen.fincalc}"
DERIVED="${DERIVED:-$APP_DIR/build/dd-shots}"
LANG_CODE="${LANG_CODE:-en}"
LOCALE_CODE="${LOCALE_CODE:-en_US}"
OUT="$APP_DIR/marketing/raw/$PLATFORM"
mkdir -p "$OUT"

# name:tool — the tool is the PAR_TOOL slug. Order is the App Store order, and it is deliberate:
# lead with the solve everyone came for, then the schedule, then the proof of provenance.
if [ "$PLATFORM" = "ipad" ]; then
  SCENES=(
    "01_tvm:tvm"
    "02_amortization:amortization"
    "03_cashflow:cashflow"
    "04_bond:bond"
    "05_dates:dates"
    "06_realestate:realestate"
  )
else
  SCENES=(
    "01_tape:tvm:tape"
    "02_tvm:tvm"
    "03_amortization:amortization"
    "04_bond:bond"
    "05_dates:dates"
    "06_realestate:realestate"
  )
fi

UDID=$(xcrun simctl list devices | grep "$SIM_NAME (" | grep -oE "[0-9A-Fa-f-]{36}" | head -1)
[ -n "$UDID" ] || { echo "simulator '$SIM_NAME' not found" >&2; exit 1; }
echo "▸ $PLATFORM · $SIM_NAME · $UDID"

xcrun simctl boot "$UDID" 2>/dev/null || true
xcrun simctl bootstatus "$UDID" -b >/dev/null

( cd "$APP_DIR" && xcodegen generate >/dev/null )
# The Capture configuration defines PAR_CAPTURE, which presents the calculator directly instead of
# the document browser. A Debug build would screenshot an empty file list.
xcodebuild build -scheme "$SCHEME" -project "$APP_DIR/Par.xcodeproj" -configuration Capture \
  -destination "id=$UDID" -derivedDataPath "$DERIVED" -quiet

APP=$(find "$DERIVED/Build/Products" -maxdepth 2 -name "Par.app" -path "*Capture-iphonesimulator*" | head -1)
[ -n "$APP" ] || { echo "built app not found" >&2; exit 1; }
xcrun simctl install "$UDID" "$APP"

# 9:41, full bars, no carrier name — the same status bar Apple's own screenshots use.
xcrun simctl status_bar "$UDID" override \
  --time "9:41" --operatorName " " --batteryState charged --batteryLevel 100 \
  --cellularBars 4 --wifiBars 3 --dataNetwork wifi 2>/dev/null || true

for entry in "${SCENES[@]}"; do
  name="${entry%%:*}"
  rest="${entry#*:}"
  tool="${rest%%:*}"
  tape=""
  [ "$rest" != "$tool" ] && tape="1"        # a third field asks for the tape to be on screen
  echo "  · $name  (PAR_TOOL=$tool${tape:+, tape})"
  xcrun simctl terminate "$UDID" "$BUNDLE" 2>/dev/null || true
  sleep 0.4
  # -AppleLanguages/-AppleLocale as launch arguments: the simulator's own locale formatted 6.25 as
  # "6,250" and 420000 as "420 000,00". Correct for that locale, wrong for a US listing — and the
  # kind of thing that reaches review unnoticed because the app is not "wrong", just foreign.
  SIMCTL_CHILD_PAR_TOOL="$tool" SIMCTL_CHILD_PAR_TAPE="$tape" \
    xcrun simctl launch "$UDID" "$BUNDLE" \
    -AppleLanguages "($LANG_CODE)" -AppleLocale "$LOCALE_CODE" >/dev/null
  sleep 2.6                      # let the document scene settle and the hero compute
  xcrun simctl io "$UDID" screenshot --type png "$OUT/$name.png" >/dev/null
done

xcrun simctl terminate "$UDID" "$BUNDLE" 2>/dev/null || true
xcrun simctl status_bar "$UDID" clear 2>/dev/null || true

echo "▸ ${#SCENES[@]} stills → $OUT"
ls -1 "$OUT"
