#!/usr/bin/env bash
#
# make_mac_shots.sh — capture Mac window screenshots of AirCore and frame them for the
# Mac App Store (2880×1800 → marketing/aso/en/mac/2880x1800/).
#
# Needs, once, in System Settings › Privacy & Security:
#   • Screen Recording — for `screencapture`
# Window geometry is read via Quartz, so no Accessibility or Automation permission is needed and
# this runs from a plain shell.
#
# Each shot is a fresh launch, force-killed between, so the deep-link env (AIRCORE_TOOL) actually
# takes effect — a running app ignores it.
#
set -euo pipefail
ROOT=/Users/oleksandr/Projects/rootyapps
APP_DIR="$ROOT/aircore"
PY=/Users/oleksandr/miniconda3/envs/fantastic/bin/python
APP_BUNDLE="$APP_DIR/build/dd-mac/Build/Products/Debug/AirCore.app"
MACBIN="$APP_BUNDLE/Contents/MacOS/AirCore"
RAW="$APP_DIR/marketing/raw/en/mac"; mkdir -p "$RAW"; rm -f "$RAW"/*.png

[ -x "$MACBIN" ] || ( cd "$APP_DIR" && xcodegen generate >/dev/null && \
  xcodebuild -project aircore.xcodeproj -scheme aircore -destination 'platform=macOS' \
    -derivedDataPath build/dd-mac build >/dev/null )

kill_app(){ pkill -9 -f "MacOS/AirCore" 2>/dev/null || true
  for _ in 1 2 3 4 5; do pgrep -f "MacOS/AirCore" >/dev/null || break; sleep 0.5; done; }

capture(){  # 01_name  toolRawValue
  kill_app; sleep 0.8
  # Window state restoration would bring back whatever size the last run left, so it is disabled
  # here for the same reason the UI suite disables it: the capture must show the layout a new user
  # gets, not one a previous session happened to drag to.
  # `open -n -g`, never the binary directly: -g launches in the BACKGROUND so a capture run of
  # five relaunches does not yank focus off whatever you are doing five times. It costs nothing,
  # because `screencapture -l<windowID>` is window-specific and occlusion-proof — the app never
  # has to be frontmost or even visible (marketing/reels/README.md §"Run (macOS)").
  # -AppleLocale pins the FORMATTING, and it is not optional for a US store listing. The
  # simulators are pinned at creation, but a Mac capture runs on this actual machine and inherits
  # its region — the first run of this script produced frames reading "75,0 °F" and "0,0738 lb/ft³"
  # for a US-only listing. There is no device to pin here, so the app is pinned instead.
  # AIRCORE_APPEARANCE for the same reason as -AppleLocale: these frames must not change with the
  # machine's state. This Mac is on Auto appearance, so without it a capture run after sunset comes
  # back dark while the ones already uploaded are light.
  open -n -g "$APP_BUNDLE" --env AIRCORE_TOOL="$2" --env AIRCORE_RESET=1 --env AIRCORE_APPEARANCE=light \
    --args -AppleLocale en_US -AppleLanguages '(en-US)' -ApplePersistenceIgnoreState YES
  sleep 3.5
  local wid
  wid=$("$PY" -c "
import Quartz
wl = Quartz.CGWindowListCopyWindowInfo(
    Quartz.kCGWindowListOptionOnScreenOnly | Quartz.kCGWindowListExcludeDesktopElements,
    Quartz.kCGNullWindowID)
print(next((int(w['kCGWindowNumber']) for w in wl
            if w.get('kCGWindowOwnerName', '') == 'AirCore' and w.get('kCGWindowName', '')), ''))")
  if [ -z "$wid" ]; then echo "  ✗ $1 — no AirCore window found"; return 1; fi
  # -o: no window shadow.  -x: no shutter sound — this runs five times in a row.
  screencapture -o -x -l "$wid" "$RAW/$1.png"
  # Verify the pixels rather than trusting the sleep: AirCore's ground is light, but a window that
  # has not drawn yet is flat, and flat is what the standard deviation catches.
  "$PY" - "$RAW/$1.png" <<'PYEOF' || { echo "  ✗ $1 — frame looks blank"; return 1; }
import sys
from PIL import Image
import numpy as np
a = np.asarray(Image.open(sys.argv[1]).convert("RGB")).astype(float)
sys.exit(0 if (a.mean() > 120 and a.std() > 12) else 1)
PYEOF
  echo "  ✓ $1"
}

echo "▶ capturing Mac windows"
capture 01_psychrometrics psychrometrics
capture 02_duct           duct
capture 03_mixing         mixing
capture 04_pipe           pipe
kill_app

PARAMS="$APP_DIR/marketing/aso/en/mac/params.yaml"
if [ -f "$PARAMS" ]; then
  echo "▶ framing (2880×1800)"
  ( cd "$ROOT/marketing" && "$PY" generate_screenshots.py "$PARAMS" )
  echo "done → $APP_DIR/marketing/aso/en/mac/"
else
  echo "⚠ no params at $PARAMS — raws are in $RAW"
fi
