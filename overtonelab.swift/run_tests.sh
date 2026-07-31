#!/bin/bash
# Overtone Lab — iPhone + iPad + watch test run, in parallel. macOS is NOT run here.
#
# Usage:
#   ./run_tests.sh                 # build once, fan out three runs, summarise
#   ./run_tests.sh --dry-run       # print the plan, boot nothing
#   ./run_tests.sh --keep-sims     # leave the throwaway sims behind
#   ./run_tests.sh --only iphone   # one destination (iphone | ipad | watch)
#
# Why it is shaped this way
#
#   • One `build-for-testing` per platform family, then `test-without-building` per sim. Two
#     concurrent `xcodebuild test` invocations against one -derivedDataPath fight over the same
#     build products.
#   • A separate -derivedDataPath for iOS and for watchOS: different products entirely.
#   • A distinct -resultBundlePath per run, or the last writer wins and a failure disappears.
#   • Destinations by UDID, never by name. Other sessions run their own simulators; a name lookup
#     can land in one of theirs, and three screenshots once came back showing another app.
#   • Throwaway OTLT-* sims, deleted at the end. The long-lived OTL-* media sims are never touched:
#     the favourites test writes persistent state that would then show up in a capture.
#   • macOS is excluded on purpose. It seizes the screen, it is single-instance, and parallel runs
#     put several copies of one app in a focus fight.
set -euo pipefail
cd "$(dirname "$0")"

DRY=0; KEEP=0; ONLY=""
while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run)   DRY=1 ;;
    --keep-sims) KEEP=1 ;;
    --only)      ONLY="${2:-}"; shift ;;
    *) echo "unknown flag: $1" >&2; exit 2 ;;
  esac
  shift
done

PROJECT=overtonelab.swift.xcodeproj
IOS_SCHEME=overtonelab.swift
WATCH_SCHEME=OverToneLabWatch
OUT=build/testrun
IOS_RUNTIME=$(xcrun simctl list runtimes | awk '/^iOS/ {print $NF}' | tail -1)
WATCH_RUNTIME=$(xcrun simctl list runtimes | awk '/^watchOS/ {print $NF}' | tail -1)

# ── sims ──────────────────────────────────────────────────────────────────────
# Reuse an OTLT-* sim if this script already made one, else create it. Never reuse an OTL-* sim.
udid_for() {   # udid_for <name> <devicetype> <runtime>
  local existing
  existing=$(xcrun simctl list devices -j | python3 -c "
import json,sys
d = json.load(sys.stdin)['devices']
print(next((x['udid'] for ds in d.values() for x in ds if x['name'] == '$1'), ''))")
  if [ -n "$existing" ]; then echo "$existing"; return; fi
  local new; new=$(xcrun simctl create "$1" "$2" "$3")
  # Plain en_US, pinned at creation. A fresh sim can boot into a comma-decimal region, and then
  # every formatted number fails the test on its separator rather than on the arithmetic.
  local plist="$HOME/Library/Developer/CoreSimulator/Devices/$new/data/Library/Preferences/.GlobalPreferences.plist"
  mkdir -p "$(dirname "$plist")"
  /usr/libexec/PlistBuddy -c "Add :AppleLocale string en_US" "$plist" 2>/dev/null \
    || /usr/libexec/PlistBuddy -c "Set :AppleLocale en_US" "$plist"
  /usr/libexec/PlistBuddy -c "Add :AppleLanguages array" "$plist" 2>/dev/null || true
  /usr/libexec/PlistBuddy -c "Add :AppleLanguages:0 string en" "$plist" 2>/dev/null || true
  echo "$new"
}

IPHONE=$(udid_for OTLT-iPhone com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro-Max "$IOS_RUNTIME")
IPAD=$(udid_for OTLT-iPad "$(xcrun simctl list devicetypes | grep -i 'iPad Pro' | tail -1 | sed -E 's/.*\((com\.apple[^)]*)\)/\1/')" "$IOS_RUNTIME")
WATCH=$(udid_for OTLT-Watch41 com.apple.CoreSimulator.SimDeviceType.Apple-Watch-Series-9-41mm "$WATCH_RUNTIME")

echo "iPhone $IPHONE"
echo "iPad   $IPAD"
echo "watch  $WATCH"
[ "$DRY" = 1 ] && { echo "(dry run — nothing booted, nothing built)"; exit 0; }

cleanup() {
  [ "$KEEP" = 1 ] && { echo "sims kept: OTLT-iPhone OTLT-iPad OTLT-Watch41"; return; }
  for u in "$IPHONE" "$IPAD" "$WATCH"; do
    xcrun simctl shutdown "$u" >/dev/null 2>&1 || true
    xcrun simctl delete "$u"   >/dev/null 2>&1 || true
  done
  echo "throwaway sims deleted"
}
trap cleanup EXIT

rm -rf "$OUT"          # xcodebuild refuses to overwrite an existing .xcresult bundle
mkdir -p "$OUT"
xcodegen generate >/dev/null      # a test file added without this gives "Executed 0 tests"

# ── build once per platform family ────────────────────────────────────────────
echo "── building"
run_ios=0; run_ipad=0; run_watch=0
case "$ONLY" in
  "")       run_ios=1; run_ipad=1; run_watch=1 ;;
  iphone)   run_ios=1 ;;
  ipad)     run_ipad=1 ;;
  watch)    run_watch=1 ;;
  *) echo "--only takes iphone | ipad | watch" >&2; exit 2 ;;
esac

if [ "$run_ios" = 1 ] || [ "$run_ipad" = 1 ]; then
  xcodebuild build-for-testing -project "$PROJECT" -scheme "$IOS_SCHEME" \
    -destination "id=$IPHONE" -derivedDataPath build/dd-ios > "$OUT/build-ios.log" 2>&1 \
    || { echo "iOS test build FAILED — see $OUT/build-ios.log"; grep -E "error:" "$OUT/build-ios.log" | head; exit 1; }
fi
if [ "$run_watch" = 1 ]; then
  xcodebuild build-for-testing -project "$PROJECT" -scheme "$WATCH_SCHEME" \
    -destination "id=$WATCH" -derivedDataPath build/dd-watch > "$OUT/build-watch.log" 2>&1 \
    || { echo "watch test build FAILED — see $OUT/build-watch.log"; grep -E "error:" "$OUT/build-watch.log" | head; exit 1; }
fi

# ── fan out ──────────────────────────────────────────────────────────────────
echo "── running in parallel"
START=$SECONDS
pids=()
launch() {  # launch <label> <scheme> <udid> <derivedData>
  # `rc=0; ... || rc=$?` and not a bare command: `set -e` is inherited by the subshell, so a failing
  # xcodebuild aborted it before the status file was ever written — losing the summary in exactly
  # the case the summary exists for. The first run of this script reported nothing at all while
  # five tests were failing.
  ( rc=0
    xcodebuild test-without-building -project "$PROJECT" -scheme "$2" \
      -destination "id=$3" -derivedDataPath "$4" \
      -resultBundlePath "$OUT/$1.xcresult" > "$OUT/$1.log" 2>&1 || rc=$?
    echo "$rc" > "$OUT/$1.status" ) &
  pids+=("$!")
  echo "   started $1"
}
[ "$run_ios"   = 1 ] && launch iphone "$IOS_SCHEME"   "$IPHONE" build/dd-ios
[ "$run_ipad"  = 1 ] && launch ipad   "$IOS_SCHEME"   "$IPAD"   build/dd-ios
[ "$run_watch" = 1 ] && launch watch  "$WATCH_SCHEME" "$WATCH"  build/dd-watch
for p in "${pids[@]}"; do wait "$p" || true; done
ELAPSED=$((SECONDS - START))

# ── report ───────────────────────────────────────────────────────────────────
echo
echo "── results (${ELAPSED}s wall clock, parallel)"
fails=0
for label in iphone ipad watch; do
  [ -f "$OUT/$label.status" ] || continue
  status=$(cat "$OUT/$label.status")
  executed=$(grep -oE "Executed [0-9]+ test" "$OUT/$label.log" | tail -1 | grep -oE "[0-9]+" || echo "?")
  if [ "$status" = 0 ]; then
    printf "  ✓ %-8s %s tests\n" "$label" "$executed"
  else
    fails=$((fails + 1))
    printf "  ✗ %-8s %s tests\n" "$label" "$executed"
    grep -E "^Test Case .* failed|error:" "$OUT/$label.log" | head -12 | sed 's/^/      /'
    # The -only-testing: lines to re-run just the failures, per the fix-loop rule.
    echo "      re-run only these:"
    grep -E "^Test Case .* failed" "$OUT/$label.log" \
      | sed -E 's/.*-\[[A-Za-z_]+\.([A-Za-z]+) ([A-Za-z]+)\].*/        -only-testing:\1\/\2/' | sort -u
  fi
done
echo
echo "logs and .xcresult bundles: $OUT/"
[ "$fails" = 0 ] || echo "NOTE: a timeout that only fires under parallelism is contention, not a bug — re-run that test alone with --only before believing it."
exit "$fails"
