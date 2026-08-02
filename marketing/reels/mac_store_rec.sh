#!/usr/bin/env bash
#
# mac_store_rec.sh — record a macOS app window scene-by-scene and concatenate the clips into ONE
# 16:9 walkthrough that `store_preview.py` can cut with `src` windows.
#
# This is the App-Store path. `make_mac_reel.sh` is the site/social path — its output wraps the
# window in a caption column and a decorative frame, which is exactly what Guideline 2.3.4 rejects
# in an app preview ("framing around the video screen capture"). Here the window fills every pixel.
#
# Aspect: Mac previews must be 1920×1080 (or 3840×2160) — 16:9. App windows rarely are, so each
# clip is scaled to the canvas width and centre-cropped to height. Nothing is padded: letterbox
# bars would themselves read as framing. Keep the app's window as close to 16:9 as practical so the
# crop stays shallow.
#
# Needs Screen Recording permission for your terminal. Recording takes over the screen — the app is
# launched and raised per scene, so don't use the machine while it runs.
#
#   APP_DIR=/path/to/<app>.swift  APP_NAME="Overtone Lab"  SCHEME=<scheme> \
#   TOOL_ENV=OVERTONELAB_TOOL  SCENES="tempo sabine benchmark"  SECS=6 \
#   marketing/reels/mac_store_rec.sh
#
set -euo pipefail
ROOT=/Users/oleksandr/Projects/rootyapps
PY=/Users/oleksandr/miniconda3/envs/fantastic/bin/python
APP_DIR="${APP_DIR:?set APP_DIR}"
APP_NAME="${APP_NAME:?set APP_NAME (the product name / window owner)}"
SCHEME="${SCHEME:?set SCHEME}"
# Scene selection: an app exposes its opening screen EITHER as an env var (TOOL_ENV, e.g.
# OVERTONELAB_TOOL) OR as a launch argument (TOOL_ARG, e.g. `-tool`, which is what Marine Nav's
# ContentView.initialTool reads). Set exactly one.
TOOL_ENV="${TOOL_ENV:-}"
TOOL_ARG="${TOOL_ARG:-}"
[ -n "$TOOL_ENV" ] || [ -n "$TOOL_ARG" ] || { echo "set TOOL_ENV (e.g. OVERTONELAB_TOOL) or TOOL_ARG (e.g. -tool)"; exit 2; }
SCENES="${SCENES:?set SCENES, e.g. \"tempo sabine benchmark\"}"
SECS="${SECS:-6}"
CANVAS_W="${CANVAS_W:-1920}"; CANVAS_H="${CANVAS_H:-1080}"
DEMO_SCENE="${DEMO_SCENE:-}"          # optional: scene key that also gets <APP>_DEMO=1
# Optional exact source region, "W:H:X:Y", applied BEFORE the scale. Use it when the app window's
# aspect is far from the canvas: the default width-scale + top-crop then eats real content (on
# Marine Nav's 1100x760 window it sliced the tide chart in half). Pick a region that is already
# CANVAS_W:CANVAS_H so the scale is pure resampling, and inset x by ~12px to clear the window's
# rounded corners and shadow — those leave dark bands that read as "framing" under 2.3.4.
CROP="${CROP:-}"
PRE_LAUNCH="${PRE_LAUNCH:-}"          # optional shell snippet run once before recording (e.g. defaults write)

MACBIN="$APP_DIR/build/dd-mac/Build/Products/Debug/$APP_NAME.app/Contents/MacOS/$APP_NAME"
REC="$ROOT/marketing/reels/recordwindow"
CLIPS=/tmp/macstore_clips; rm -rf "$CLIPS"; mkdir -p "$CLIPS"
OUT="$APP_DIR/marketing/aso/mac/video"; mkdir -p "$OUT"
WALK="$OUT/mac_walkthrough.mp4"

[ -x "$MACBIN" ] || ( cd "$APP_DIR" && xcodegen generate >/dev/null && \
  xcodebuild -scheme "$SCHEME" -destination 'platform=macOS' -derivedDataPath build/dd-mac build >/dev/null )
[ -x "$REC" ] || ( cd "$ROOT/marketing/reels" && swiftc -O RecordWindow.swift -o recordwindow )

kill_app(){ pkill -9 -f "MacOS/$APP_NAME" 2>/dev/null || true
  for _ in 1 2 3 4 5; do pgrep -f "MacOS/$APP_NAME" >/dev/null || break; sleep 0.4; done; }
trap kill_app EXIT

[ -n "$PRE_LAUNCH" ] && eval "$PRE_LAUNCH"

# Fill the frame: scale to canvas width, then crop height from the TOP (y=0). Never pad — bars
# would read as framing. Top-aligned rather than centred so the toolbar/title survives; what gets
# dropped is the bottom of the window, which is usually the emptiest part of a detail pane.
# With CROP set, take that exact region instead and scale it straight to the canvas.
if [ -n "$CROP" ]; then
  FIT="crop=${CROP},scale=${CANVAS_W}:${CANVAS_H}:flags=lanczos,fps=30,format=yuv420p"
else
  FIT="scale=${CANVAS_W}:-2:flags=lanczos,crop=${CANVAS_W}:${CANVAS_H}:0:0,fps=30,format=yuv420p"
fi
ENC=(-c:v libx264 -profile:v high -crf 20 -preset medium -pix_fmt yuv420p -an)

echo "▶ recording ${SECS}s per scene — do not touch the machine"
i=0; : > "$CLIPS/list.txt"
for key in $SCENES; do
  i=$((i+1))
  kill_app; sleep 0.7
  demo=""; [ "$key" = "$DEMO_SCENE" ] && demo=1
  # Launch through LaunchServices, NOT by exec'ing the binary: a process started from a headless
  # / agent shell has no GUI session, so AppKit comes up windowless and the Quartz lookup below
  # finds nothing. `open --env` hands off to the user's session, where the window really appears.
  if [ -n "$TOOL_ENV" ]; then
    open "$APP_DIR/build/dd-mac/Build/Products/Debug/$APP_NAME.app" \
      --env "$TOOL_ENV=$key" --env "${TOOL_ENV%_TOOL}_DEMO=$demo" >/dev/null 2>&1
  else
    open "$APP_DIR/build/dd-mac/Build/Products/Debug/$APP_NAME.app" \
      --args "$TOOL_ARG" "$key" >/dev/null 2>&1
  fi
  sleep 3.3
  # Record by PID, which RecordWindow.swift documents as the preferred key: a windowID has to be
  # looked up first, and every lookup key that isn't a pid is ambiguous the moment a second copy
  # of the app is running. It also needs no pyobjc — the system python has no Quartz module, so
  # the lookup below only runs as a fallback when $PY (conda `fantastic`) is present.
  pid=$(pgrep -f "MacOS/$APP_NAME" | head -1)
  if [ -n "$pid" ]; then
    "$REC" --pid "$pid" "$SECS" "$CLIPS/raw_$i.mov" >/dev/null 2>&1
  else
    wid=$("$PY" -c "
import Quartz
wl=Quartz.CGWindowListCopyWindowInfo(Quartz.kCGWindowListOptionOnScreenOnly|Quartz.kCGWindowListExcludeDesktopElements,Quartz.kCGNullWindowID)
print(next((int(w['kCGWindowNumber']) for w in wl if w.get('kCGWindowOwnerName','')=='$APP_NAME' and w.get('kCGWindowName','')),''))" 2>/dev/null)
    [ -n "$wid" ] || { echo "  ✗ $key — app not running / no window found"; continue; }
    "$REC" "$wid" "$SECS" "$CLIPS/raw_$i.mov" >/dev/null 2>&1
  fi
  ffmpeg -y -loglevel error -i "$CLIPS/raw_$i.mov" -vf "$FIT" "${ENC[@]}" "$CLIPS/seg_$i.mp4"
  echo "file 'seg_$i.mp4'" >> "$CLIPS/list.txt"
  echo "  ✓ $key"
done
kill_app

echo "▶ concatenating -> $WALK"
ffmpeg -y -loglevel error -f concat -safe 0 -i "$CLIPS/list.txt" -c copy "$WALK"

echo
echo "walkthrough: $(ffprobe -v error -select_streams v:0 -show_entries stream=width,height -of csv=p=0:s=x "$WALK") \
$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$WALK")s"
echo "scene boundaries for scenes_mac_store.json \"src\" windows (each scene is ${SECS}s):"
i=0; for key in $SCENES; do echo "   $key: [$(echo "$i*$SECS+0.4"|bc), $(echo "($i+1)*$SECS-0.3"|bc)]"; i=$((i+1)); done
echo
echo "next: store_preview.py --scenes <app>/marketing/reels/scenes_mac_store.json --video $WALK ..."
