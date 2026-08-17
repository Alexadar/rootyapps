#!/bin/bash
# AirCore — Kits, then iPhone + iPad + watch, in parallel. macOS is NOT run here.
#
# Usage:
#   ./run_tests.sh                 # everything: Kit suites, then the three simulator runs
#   ./run_tests.sh --dry-run       # print the plan, boot nothing
#   ./run_tests.sh --kits-only     # just the SPM oracle suites (fast, no simulator)
#   ./run_tests.sh --keep-sims     # leave the throwaway sims behind
#   ./run_tests.sh --only iphone   # one destination (iphone | ipad | watch)
#
# Why it is shaped this way
#
#   • The Kit suites run first and run alone. They are the product — if an oracle is red there is
#     no point booting a simulator to find out the UI still draws.
#   • One `build-for-testing` per platform family, then `test-without-building` per sim. Two
#     concurrent `xcodebuild test` runs against one -derivedDataPath fight over the same products.
#   • A separate -derivedDataPath for iOS and for watchOS: different products entirely.
#   • A distinct -resultBundlePath per run, or the last writer wins and a failure disappears.
#   • Destinations by UDID, never by name. Other sessions run their own simulators, and a name
#     lookup can land in one of theirs.
#   • Throwaway AIRC-* sims, deleted at the end. No other app's simulator is touched.
#   • Locale pinned to en_US at creation. A fresh sim can boot into a comma-decimal region, and
#     then every formatted number fails on its separator rather than on the arithmetic.
#   • macOS is excluded on purpose: it seizes the screen, it is single-instance, and parallel runs
#     put several copies of one app in a focus fight. Run it deliberately, not by default.
set -euo pipefail
cd "$(dirname "$0")"

DRY=0; KEEP=0; ONLY=""; KITS_ONLY=0
while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run)   DRY=1 ;;
    --keep-sims) KEEP=1 ;;
    --kits-only) KITS_ONLY=1 ;;
    --only)      ONLY="${2:-}"; shift ;;
    *) echo "unknown flag: $1" >&2; exit 2 ;;
  esac
  shift
done

PROJECT=aircore.xcodeproj
IOS_SCHEME=aircore
WATCH_SCHEME=AirCoreWatch
OUT=build/testrun

KITS=(
  Kits/Foundation/UnitsKit
  Kits/Foundation/AltitudeKit
  Kits/Foundation/FluidKit
  Kits/Air/PsychroKit
  Kits/Air/HeatKit
  Kits/Air/FanKit
  Kits/Duct/DuctKit
  Kits/Water/PipeKit
)

# ── the oracles ───────────────────────────────────────────────────────────────
echo "── Kit oracle suites ─────────────────────────────────────────────"
kit_failures=0
for kit in "${KITS[@]}"; do
  printf '%-28s ' "$(basename "$kit")"
  if [ "$DRY" = 1 ]; then echo "(dry run)"; continue; fi
  if out=$(cd "$kit" && swift test 2>&1); then
    echo "$out" | grep -oE 'Test run with [0-9]+ tests? in [0-9]+ suites? passed' | tail -1
  else
    echo "FAILED"
    echo "$out" | grep -E 'error:|recorded an issue' | head -20
    kit_failures=$((kit_failures + 1))
  fi
done
[ "$kit_failures" -gt 0 ] && { echo "$kit_failures Kit suite(s) red — stopping."; exit 1; }
[ "$KITS_ONLY" = 1 ] && exit 0

# ── sims ──────────────────────────────────────────────────────────────────────
IOS_RUNTIME=$(xcrun simctl list runtimes | awk '/^iOS/ {print $NF}' | tail -1)
WATCH_RUNTIME=$(xcrun simctl list runtimes | awk '/^watchOS/ {print $NF}' | tail -1)

# Device types are not interchangeable with runtimes: `simctl` happily lists an iPad Pro (1st
# generation) that the current iOS refuses to run on, and the name-sorted "last iPad Pro" is
# exactly that one. So try candidates in order and take the first the runtime will actually create.
first_creatable() {   # first_creatable <name> <runtime> <devicetype>...
  local name="$1" runtime="$2"; shift 2
  local existing
  existing=$(xcrun simctl list devices -j | python3 -c "
import json,sys
devices = json.load(sys.stdin)['devices']
print(next((d['udid'] for group in devices.values() for d in group if d['name'] == '$name'), ''))")
  if [ -n "$existing" ]; then echo "$existing"; return; fi
  for devicetype in "$@"; do
    local new
    if new=$(xcrun simctl create "$name" "$devicetype" "$runtime" 2>/dev/null); then
      pin_locale "$new"
      echo "$new"
      return
    fi
  done
  echo "could not create $name on $runtime" >&2
  return 1
}

pin_locale() {
  local plist="$HOME/Library/Developer/CoreSimulator/Devices/$1/data/Library/Preferences/.GlobalPreferences.plist"
  mkdir -p "$(dirname "$plist")"
  /usr/libexec/PlistBuddy -c "Add :AppleLocale string en_US" "$plist" 2>/dev/null \
    || /usr/libexec/PlistBuddy -c "Set :AppleLocale en_US" "$plist"
  /usr/libexec/PlistBuddy -c "Add :AppleLanguages array" "$plist" 2>/dev/null || true
  /usr/libexec/PlistBuddy -c "Add :AppleLanguages:0 string en" "$plist" 2>/dev/null || true
}

IPHONE=$(first_creatable AIRC-iPhone "$IOS_RUNTIME" \
  com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro \
  com.apple.CoreSimulator.SimDeviceType.iPhone-16-Pro \
  com.apple.CoreSimulator.SimDeviceType.iPhone-15-Pro)
IPAD=$(first_creatable AIRC-iPad "$IOS_RUNTIME" \
  com.apple.CoreSimulator.SimDeviceType.iPad-Pro-13-inch-M4-8GB \
  com.apple.CoreSimulator.SimDeviceType.iPad-Pro-11-inch-M4-8GB \
  com.apple.CoreSimulator.SimDeviceType.iPad-Air-11-inch-M2 \
  com.apple.CoreSimulator.SimDeviceType.iPad-Pro--12-9-inch---6th-generation-)
WATCH=$(first_creatable AIRC-Watch "$WATCH_RUNTIME" \
  com.apple.CoreSimulator.SimDeviceType.Apple-Watch-Series-10-42mm \
  com.apple.CoreSimulator.SimDeviceType.Apple-Watch-Series-9-41mm)

echo
echo "iPhone $IPHONE"
echo "iPad   $IPAD"
echo "watch  $WATCH"
[ "$DRY" = 1 ] && { echo "(dry run — nothing booted, nothing built)"; exit 0; }

cleanup() {
  [ "$KEEP" = 1 ] && { echo "sims kept: AIRC-iPhone AIRC-iPad AIRC-Watch"; return; }
  for udid in "$IPHONE" "$IPAD" "$WATCH"; do
    xcrun simctl shutdown "$udid" >/dev/null 2>&1 || true
    xcrun simctl delete   "$udid" >/dev/null 2>&1 || true
  done
  echo "throwaway sims deleted"
}
trap cleanup EXIT

rm -rf "$OUT"; mkdir -p "$OUT"


run_ios=1; run_ipad=1; run_watch=1
case "$ONLY" in
  iphone) run_ipad=0; run_watch=0 ;;
  ipad)   run_ios=0;  run_watch=0 ;;
  watch)  run_ios=0;  run_ipad=0 ;;
  "")     ;;
  *) echo "unknown --only value: $ONLY" >&2; exit 2 ;;
esac

# Boot each simulator and *wait* for it, rather than letting xcodebuild race it.
#
# A freshly created device is not ready the moment `simctl create` returns, and installing onto one
# that is still coming up fails two different ways: "Application failed preflight checks (Busy)" on
# iOS, and "Unknown application display identifier" on watchOS — the second of which looks exactly
# like a broken app bundle and is not. `bootstatus -b` is the wait that makes both go away.
boot() {
  xcrun simctl boot "$1" >/dev/null 2>&1 || true
  xcrun simctl bootstatus "$1" -b >/dev/null 2>&1 || true
}
[ "$run_ios" = 1 ]   && boot "$IPHONE"
[ "$run_ipad" = 1 ]  && boot "$IPAD"
[ "$run_watch" = 1 ] && boot "$WATCH"

echo
echo "── building for testing ──────────────────────────────────────────"
if [ "$run_ios" = 1 ] || [ "$run_ipad" = 1 ]; then
  xcodebuild -project "$PROJECT" -scheme "$IOS_SCHEME" \
    -destination "generic/platform=iOS Simulator" \
    -derivedDataPath "$OUT/dd-ios" build-for-testing >"$OUT/build-ios.log" 2>&1 \
    || { echo "iOS build failed:"; grep -E 'error:' "$OUT/build-ios.log" | head -20; exit 1; }
fi
if [ "$run_watch" = 1 ]; then
  xcodebuild -project "$PROJECT" -scheme "$WATCH_SCHEME" \
    -destination "generic/platform=watchOS Simulator" \
    -derivedDataPath "$OUT/dd-watch" build-for-testing >"$OUT/build-watch.log" 2>&1 \
    || { echo "watchOS build failed:"; grep -E 'error:' "$OUT/build-watch.log" | head -20; exit 1; }
fi

echo "── running ───────────────────────────────────────────────────────"
pids=()
run() {  # run <label> <scheme> <derived> <udid>
  xcodebuild -project "$PROJECT" -scheme "$2" -derivedDataPath "$3" \
    -destination "id=$4" -resultBundlePath "$OUT/$1.xcresult" \
    test-without-building >"$OUT/$1.log" 2>&1 &
  pids+=("$!:$1")
}
[ "$run_ios" = 1 ]   && run iphone "$IOS_SCHEME"   "$OUT/dd-ios"   "$IPHONE"
[ "$run_ipad" = 1 ]  && run ipad   "$IOS_SCHEME"   "$OUT/dd-ios"   "$IPAD"
[ "$run_watch" = 1 ] && run watch  "$WATCH_SCHEME" "$OUT/dd-watch" "$WATCH"

failures=0
for entry in "${pids[@]}"; do
  pid="${entry%%:*}"; label="${entry##*:}"
  if wait "$pid"; then
    printf '%-8s %s\n' "$label" "$(grep -oE 'Executed [0-9]+ tests?, with [0-9]+ failures?' "$OUT/$label.log" | tail -1)"
  else
    printf '%-8s FAILED\n' "$label"
    grep -E 'error:|XCTAssert|failed \(' "$OUT/$label.log" | head -20
    failures=$((failures + 1))
  fi
done

echo
if [ "$failures" -gt 0 ]; then
  echo "$failures destination(s) red. Logs in $OUT/"
  exit 1
fi
echo "all green. Logs in $OUT/"
