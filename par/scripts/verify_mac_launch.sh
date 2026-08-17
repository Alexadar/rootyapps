#!/usr/bin/env bash
#
# verify_mac_launch.sh — assert the Mac app opens a usable window on a clean machine.
#
#   ./scripts/verify_mac_launch.sh /path/to/Par.app
#
# ## Why this is a script and not an XCUITest
#
# App Review rejected 1.0.1 build 5 under 2.1(a): "the app failed to launch any main window".
# SwiftUI's `DocumentGroup` opens a Mac app on an Open panel rather than a document, so a reviewer
# with no .partape files saw an empty file chooser and, once dismissed, nothing at all.
#
# XCUITest cannot guard this. Measured while fixing it: under XCUITest the app reports *no window*
# whether the bug is present or not — the framework's launch path does not reproduce a user launch
# for a sandboxed DocumentGroup app, so the test fails identically on a good build and a bad one. A
# guard that cannot tell the two apart is worse than none. The UI suite only ever passed here
# because it runs in the Capture configuration, which compiles `WindowGroup` instead and therefore
# tests a scene the store build does not contain.
#
# Two further traps this encodes, both of which produced a confidently wrong answer first time:
#
#   1. TEST A SIGNED BUILD. Built with CODE_SIGNING_ALLOWED=NO the sandbox is not enforced and the
#      launch behaves differently.
#   2. LAUNCH VIA LaunchServices (`open`), NOT by exec'ing the binary. Running
#      `Par.app/Contents/MacOS/Par` directly reports ZERO windows for a sandboxed app even when it
#      is perfectly healthy. `open -n` is what a user and a reviewer do.
#
# Measured A/B under those conditions: rejected build -> 917x448 "Open"; fixed build -> 1280x800
# "Untitled".
set -euo pipefail

APP="${1:?usage: verify_mac_launch.sh <Par.app>}"
BUNDLE_ID="oleksandr.aisixteen.fincalc"
REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
LIST_BIN="$REPO_ROOT/marketing/tools/capturewindow"

# Called in place — never forked into this app. Built on demand exactly as capture_mac_window.sh does.
[ -x "$LIST_BIN" ] || swiftc -O "$REPO_ROOT/marketing/tools/CaptureWindow.swift" -o "$LIST_BIN"

# A clean machine is the whole point: a saved window frame or a remembered document would mask the
# defect, and the reviewer has neither.
pkill -f "Par.app/Contents/MacOS/Par" 2>/dev/null || true
sleep 1
defaults delete "$BUNDLE_ID" 2>/dev/null || true
rm -rf "$HOME/Library/Saved Application State/$BUNDLE_ID.savedState" 2>/dev/null || true

open -n "$APP"
trap 'pkill -f "$APP/Contents/MacOS/Par" 2>/dev/null || true' EXIT

for _ in $(seq 1 30); do
  sleep 1
  if "$LIST_BIN" --list 2>/dev/null | grep -q "\"bundle\":\"$BUNDLE_ID\""; then break; fi
done

# Note the quoting: this block is single-quoted for the shell, so the Python inside must not need
# any escaped quotes of its own — %-formatting, not f-strings with backslashes. A first version used
# f-strings and died with a SyntaxError, which the shell reported as a non-zero exit and therefore
# looked exactly like the guard correctly catching a bad build. It "passed" its negative test while
# testing nothing.
"$LIST_BIN" --list 2>/dev/null | BUNDLE_ID="$BUNDLE_ID" python3 -c '
import json, os, sys
bundle = os.environ["BUNDLE_ID"]
wins = [w for w in json.load(sys.stdin) if w.get("bundle") == bundle and w.get("h", 0) > 0]
if not wins:
    sys.exit("FAIL: no window at all after launch - this is the 2.1(a) rejection")
main = max(wins, key=lambda w: w["w"] * w["h"])
print("main window: %dx%d %r" % (main["w"], main["h"], main["title"]))
if main["title"] == "Open":
    sys.exit("FAIL: launched on an Open panel, not a document - the 2.1(a) rejection")
if main["w"] < 1000:
    sys.exit("FAIL: window only %dpt wide - the sidebar overlays the calculator" % main["w"])
print("PASS: opens a usable document window")
'
