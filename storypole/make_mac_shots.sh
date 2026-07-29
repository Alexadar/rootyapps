#!/usr/bin/env bash
#
# make_mac_shots.sh — capture Mac window screenshots of Storypole and frame them for the
# Mac App Store (→ marketing/aso/en/mac/<WxH>/).
#
# Needs, once, in System Settings › Privacy & Security:
#   • Screen Recording — for `screencapture`
#
# Window geometry comes from Quartz, not AppleScript, so this works from a plain shell with no
# Automation/Accessibility grant. Each tool is a fresh launch, force-killed in between, because
# SwiftUI apps are single-instance: relaunching an already-running app just foregrounds the old
# window and silently DROPS the new STORYPOLE_TOOL env.
#
# `open -n -g` launches in the BACKGROUND. `screencapture -l<winID>` is window-specific and
# occlusion-proof, so the app never needs to be frontmost — and a capture run is a dozen relaunches,
# every one of which would otherwise yank focus off whatever you are doing.
#
set -euo pipefail
ROOT=/Users/oleksandr/Projects/rootyapps
APP_DIR="$ROOT/storypole"
PY=/Users/oleksandr/miniconda3/envs/fantastic/bin/python
APPBUNDLE="$APP_DIR/build/dd-mac/Build/Products/Debug/Storypole.app"
RAW="$APP_DIR/marketing/raw/en/mac"; mkdir -p "$RAW"; rm -f "$RAW"/*.png

[ -d "$APPBUNDLE" ] || ( cd "$APP_DIR" && xcodegen generate >/dev/null && \
  xcodebuild -scheme storypole -destination 'platform=macOS' -derivedDataPath build/dd-mac build >/dev/null )

kill_app(){ pkill -9 -f "MacOS/Storypole" 2>/dev/null || true
  for _ in 1 2 3 4 5 6; do pgrep -f "MacOS/Storypole" >/dev/null || break; sleep 0.5; done; }

winid(){ "$PY" -c "
import Quartz
wl = Quartz.CGWindowListCopyWindowInfo(
        Quartz.kCGWindowListOptionOnScreenOnly | Quartz.kCGWindowListExcludeDesktopElements,
        Quartz.kCGNullWindowID)
# layer 0 skips phantom/utility windows; a named window skips the invisible placeholder.
print(next((int(w['kCGWindowNumber']) for w in wl
            if w.get('kCGWindowOwnerName','') == 'Storypole'
            and w.get('kCGWindowName','') and w.get('kCGWindowLayer', 1) == 0), ''))"; }

# Reject a frame that is blank or is not Storypole's light UI, rather than shipping it unseen.
valid(){ "$PY" - "$1" <<'PYEOF'
import sys
from PIL import Image
import numpy as np
a = np.asarray(Image.open(sys.argv[1]).convert("RGB")).astype(float)
mean, std = a.mean(), a.std()
ok = mean > 140 and std > 10
print(f"    mean={mean:.1f} std={std:.1f} -> {'ok' if ok else 'REJECT'}", file=sys.stderr)
sys.exit(0 if ok else 1)
PYEOF
}

capture(){  # 01_name  tool  tab  demo
  local name="$1" tool="${2:-}" tab="${3:-}" demo="${4:-}" try wid
  for try in 1 2 3; do
    kill_app; sleep 0.8
    open -n -g "$APPBUNDLE" --env STORYPOLE_TOOL="$tool" --env STORYPOLE_TAB="$tab" \
                            --env STORYPOLE_DEMO="$([ "$demo" = demo ] && echo 1 || echo 0)"
    sleep $((3 + try))
    wid=$(winid)
    if [ -n "$wid" ] && screencapture -o -x -l "$wid" "$RAW/$name.png" 2>/dev/null && valid "$RAW/$name.png"; then
      echo "  ✓ $name"; return 0
    fi
    echo "  … $name looked wrong (win='$wid'), retry $try"
  done
  echo "  ✗ $name FAILED validation"; return 1
}

echo "▶ capturing Mac windows (backgrounded, window-specific)"
capture 01_calc      ""            0   demo
capture 02_spacing   equalSpacing  ""
capture 03_oncenter  onCenter      ""
capture 04_dressed   dressedSize   ""
capture 05_reference ""            2
kill_app

PARAMS="$APP_DIR/marketing/aso/en/mac/params.yaml"
if [ -f "$PARAMS" ]; then
  echo "▶ framing"
  ( cd "$ROOT/marketing" && "$PY" generate_screenshots.py "$PARAMS" )
  echo "done → $APP_DIR/marketing/aso/en/mac/"
else
  echo "⚠ no params at $PARAMS — raws are in $RAW"
fi
