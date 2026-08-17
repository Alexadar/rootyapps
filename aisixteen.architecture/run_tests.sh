#!/bin/bash
# AISixteen Architecture — Kits, then iPhone + iPad in parallel. macOS is NOT run here.
#
# Usage:
#   ./run_tests.sh                 # Kit suites, then the unit tests on both simulators
#   ./run_tests.sh --dry-run       # print the plan, boot nothing
#   ./run_tests.sh --kits-only     # just the SPM suites (fast, no simulator)
#   ./run_tests.sh --keep-sims     # leave the throwaway sims behind
#   ./run_tests.sh --only iphone   # one destination (iphone | ipad)
#   ./run_tests.sh --ui            # ALSO execute architectureUITests — opt in, never the default
#
# Why it is shaped this way
#
#   • The Kit suites run first and run alone. They are the state space — if the queue reducer is
#     red there is no point booting a simulator to find out the UI still draws.
#   • One `build-for-testing`, then `test-without-building` per sim. Two concurrent
#     `xcodebuild test` runs against one -derivedDataPath fight over the same products.
#   • A distinct -resultBundlePath per run, or the last writer wins and a failure disappears.
#   • Destinations by UDID, never by name. Other sessions run their own simulators, and a name
#     lookup can land in one of theirs.
#   • Throwaway ARCH-* sims, deleted at the end. No other app's simulator is touched.
#   • Locale pinned to en_US at creation. A fresh sim can boot into a comma-decimal region, and
#     then every formatted duration fails on its separator rather than on the arithmetic.
#   • macOS is excluded on purpose: it seizes the screen, it is single-instance, and parallel runs
#     put several copies of one app in a focus fight. Run it deliberately, not by default — and
#     when you do, run the unit target and the UI target as SEPARATE invocations (uitests.md §9).
#
#     ⚠️ EVERY macOS build of this app needs `-allowProvisioningUpdates`:
#         xcodebuild build -scheme architecture -destination 'platform=macOS' -allowProvisioningUpdates
#     The Mac entitlements declare iCloud Drive, iCloud is a capability, and a capability forces a
#     Mac App Development provisioning profile that automatic signing will not create on its own.
#     Without the flag it fails as "No profiles for 'oleksandr.aisixteen.architecture' were found",
#     which reads like a certificate problem and is not. (This is also why the app group is NOT in
#     the macOS entitlements — see architecture-macOS.entitlements. iCloud is load-bearing and has
#     to be paid for; the app group would have been a second capability for nothing.)
#   • UI tests are BUILT on every run (so they cannot rot) but only EXECUTED behind --ui. The
#     owner runs them; this script's default is the unit suite.
set -euo pipefail
cd "$(dirname "$0")"

DRY=0; KEEP=0; ONLY=""; KITS_ONLY=0; WITH_UI=0
while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run)   DRY=1 ;;
    --keep-sims) KEEP=1 ;;
    --kits-only) KITS_ONLY=1 ;;
    --ui)        WITH_UI=1 ;;
    --only)      ONLY="${2:-}"; shift ;;
    *) echo "unknown flag: $1" >&2; exit 2 ;;
  esac
  shift
done

PROJECT=architecture.xcodeproj
SCHEME=architecture
OUT=build/testrun

KITS=(
  Kits/Redesign/RedesignKit
  Kits/Project/ProjectKit
  Kits/Direction/DirectionKit
  Kits/Format/FormatKit
)

# ── the Kit suites ────────────────────────────────────────────────────────────
echo "── Kit suites ────────────────────────────────────────────────────"
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

IPHONE=$(first_creatable ARCH-iPhone "$IOS_RUNTIME" \
  com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro \
  com.apple.CoreSimulator.SimDeviceType.iPhone-16-Pro \
  com.apple.CoreSimulator.SimDeviceType.iPhone-15-Pro)
IPAD=$(first_creatable ARCH-iPad "$IOS_RUNTIME" \
  com.apple.CoreSimulator.SimDeviceType.iPad-Pro-13-inch-M4-8GB \
  com.apple.CoreSimulator.SimDeviceType.iPad-Pro-11-inch-M4-8GB \
  com.apple.CoreSimulator.SimDeviceType.iPad-Air-11-inch-M2 \
  com.apple.CoreSimulator.SimDeviceType.iPad-Pro--12-9-inch---6th-generation-)

echo
echo "iPhone $IPHONE"
echo "iPad   $IPAD"
[ "$DRY" = 1 ] && { echo "(dry run — nothing booted, nothing built)"; exit 0; }

cleanup() {
  [ "$KEEP" = 1 ] && { echo "sims kept: ARCH-iPhone ARCH-iPad"; return; }
  for udid in "$IPHONE" "$IPAD"; do
    xcrun simctl shutdown "$udid" >/dev/null 2>&1 || true
    xcrun simctl delete   "$udid" >/dev/null 2>&1 || true
  done
  echo "throwaway sims deleted"
}
trap cleanup EXIT

rm -rf "$OUT"; mkdir -p "$OUT"

run_iphone=1; run_ipad=1
case "$ONLY" in
  iphone) run_ipad=0 ;;
  ipad)   run_iphone=0 ;;
  "")     ;;
  *) echo "unknown --only value: $ONLY" >&2; exit 2 ;;
esac

# Boot each simulator and *wait* for it, rather than letting xcodebuild race it. A freshly created
# device is not ready the moment `simctl create` returns, and installing onto one that is still
# coming up fails as "Application failed preflight checks (Busy)". `bootstatus -b` is the wait.
boot() {
  xcrun simctl boot "$1" >/dev/null 2>&1 || true
  xcrun simctl bootstatus "$1" -b >/dev/null 2>&1 || true
}
[ "$run_iphone" = 1 ] && boot "$IPHONE"
[ "$run_ipad" = 1 ]   && boot "$IPAD"

echo
echo "── building for testing ──────────────────────────────────────────"
xcodebuild -project "$PROJECT" -scheme "$SCHEME" \
  -destination "generic/platform=iOS Simulator" \
  -derivedDataPath "$OUT/dd-ios" build-for-testing >"$OUT/build-ios.log" 2>&1 \
  || { echo "iOS build failed:"; grep -E 'error:' "$OUT/build-ios.log" | head -30; exit 1; }

# The default run executes ONLY the unit tests. --ui adds the UI suite; the UI target is compiled
# either way by build-for-testing above, so it can never silently rot.
ONLY_TESTING=(-only-testing:architectureUnitTests)
if [ "$WITH_UI" = 1 ]; then
  ONLY_TESTING+=(-only-testing:architectureUITests)
  echo "(--ui: UI tests WILL execute)"
fi

echo "── running ───────────────────────────────────────────────────────"
pids=()
run() {  # run <label> <udid>
  xcodebuild -project "$PROJECT" -scheme "$SCHEME" -derivedDataPath "$OUT/dd-ios" \
    -destination "id=$2" -resultBundlePath "$OUT/$1.xcresult" \
    "${ONLY_TESTING[@]}" \
    test-without-building >"$OUT/$1.log" 2>&1 &
  pids+=("$!:$1")
}
[ "$run_iphone" = 1 ] && run iphone "$IPHONE"
[ "$run_ipad" = 1 ]   && run ipad   "$IPAD"

failures=0
for entry in "${pids[@]}"; do
  pid="${entry%%:*}"; label="${entry##*:}"
  if wait "$pid"; then
    printf '%-8s %s\n' "$label" "$(grep -oE 'Executed [0-9]+ tests?, with [0-9]+ failures?' "$OUT/$label.log" | tail -1)"
  else
    printf '%-8s FAILED\n' "$label"
    grep -E 'error:|XCTAssert|failed \(' "$OUT/$label.log" | head -20
    echo "  re-run just the failures with:"
    grep -oE '\-only-testing:[A-Za-z]+/[A-Za-z]+/[A-Za-z]+' "$OUT/$label.log" | sort -u | head -10 | sed 's/^/    /'
    failures=$((failures + 1))
  fi
done

echo
if [ "$failures" -gt 0 ]; then
  echo "$failures destination(s) red. Logs in $OUT/"
  exit 1
fi
echo "all green. Logs in $OUT/"
