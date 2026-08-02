#!/usr/bin/env bash
# Shared simulator helper for capture scripts. Source it: . "$ROOT/marketing/simlib.sh"
#
# ## Why this exists
#
# Every app's capture script used to open with the same six lines: grep `simctl list` for a
# hard-coded device name, and abort if it was missing. That has bitten twice.
#
#   1. The name was a copy-paste from whichever app the script was cloned from. eartharound's
#      shots and reels asked for `Calc-iPhone17ProMax` and `Calc-iPadPro13` — kerfcalc's devices —
#      and its watch reel asked for `SW-Watch-S11`. When those were deleted the whole media sweep
#      died on the first leg with "simulator not found"; while they existed, it was worse, because
#      a concurrent session capturing kerfcalc in the same device would have had its recording
#      trampled.
#   2. A device that exists but was created by hand carries whatever locale it was made with.
#      Every simulator on this machine except one is `en_US@rg=uazzzz` — a comma-decimal region
#      that renders "3,7" into a US App Store listing.
#
# So: machine up the device on demand, named after the app, with the locale pinned. A capture run
# should not depend on the state a previous run happened to leave behind.
#
# ## Contract
#
#   ensure_sim <name> <devicetype-substring> <platform>   -> echoes the UDID
#
# `platform` is iOS or watchOS; the newest installed runtime for it is chosen, so this does not
# need editing every time Xcode ships a new SDK. Creation is idempotent: an existing device of
# that exact name is reused, never recreated, so repeated legs of one sweep share it.
#
# Teardown is the CALLER's job and must be by UDID, never by name match — a loose pattern can
# catch another session's device. Use `release_sim "$udid"`.

# Newest installed runtime id for a platform ("iOS" / "watchOS").
_newest_runtime() {
  xcrun simctl list runtimes | grep -E "^$1 " | grep -v unavailable | tail -1 |
    grep -oE "com\.apple\.CoreSimulator\.SimRuntime\.[A-Za-z0-9.-]+"
}

# First device type whose NAME contains the substring, e.g. "iPhone 17 Pro Max".
_devicetype_id() {
  xcrun simctl list devicetypes | grep -F "$1" | head -1 |
    grep -oE "com\.apple\.CoreSimulator\.SimDeviceType\.[A-Za-z0-9.-]+"
}

ensure_sim() {
  local name="$1" dt_match="$2" platform="$3" udid dt rt prefs
  udid=$(xcrun simctl list devices | grep -F "$name (" | grep -oE "[0-9A-Fa-f-]{36}" | head -1)
  if [ -n "$udid" ]; then
    echo "$udid"; return 0
  fi

  dt=$(_devicetype_id "$dt_match")
  rt=$(_newest_runtime "$platform")
  [ -n "$dt" ] || { echo "❌ no device type matching '$dt_match'" >&2; return 1; }
  [ -n "$rt" ] || { echo "❌ no installed $platform runtime" >&2; return 1; }

  udid=$(xcrun simctl create "$name" "$dt" "$rt") || return 1

  # Plain en_US, not the machine default. A screenshot is a US-storefront asset and a
  # comma-decimal region silently corrupts every number in it.
  prefs="$HOME/Library/Developer/CoreSimulator/Devices/$udid/data/Library/Preferences/.GlobalPreferences.plist"
  mkdir -p "$(dirname "$prefs")"
  /usr/libexec/PlistBuddy -c "Add :AppleLocale string en_US" "$prefs" 2>/dev/null ||
    /usr/libexec/PlistBuddy -c "Set :AppleLocale en_US" "$prefs" 2>/dev/null || true

  echo "$udid"
}

# Shut down and delete BY UDID. Never takes a name: matching by name is how a sweep deletes a
# device belonging to somebody else's session.
release_sim() {
  local udid="$1"
  [ -n "$udid" ] || return 0
  xcrun simctl shutdown "$udid" >/dev/null 2>&1 || true
  xcrun simctl delete "$udid" >/dev/null 2>&1 || true
}
