#!/usr/bin/env bash
# Recreate all three app-preview reels (iOS/iPad/Mac) with the updated "26 tools" captions.
# iOS/iPad via the simulator reel pipeline; Mac via ScreenCaptureKit. Then mux the jazz bed.
set -euo pipefail
ROOT=/Users/oleksandr/Projects/rootyapps
APP=$ROOT/overtonelab.swift
BED=$APP/marketing/audio/jazz_groove.wav

mux(){  # $1 = silent framed_preview .mp4 → *_music.mp4
  local V="$1"; local DUR; DUR=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$V")
  ffmpeg -y -loglevel error -i "$V" -i "$BED" -filter_complex \
    "[1:a]atrim=0:${DUR},asetpts=PTS-STARTPTS,afade=t=in:st=0:d=0.6,afade=t=out:st=$(echo "$DUR-1.5"|bc):d=1.5,volume=0.85[a]" \
    -map 0:v -map "[a]" -c:v copy -c:a aac -b:a 256k -ar 44100 -movflags +faststart "${V%.mp4}_music.mp4"
  echo "  ✓ muxed ${V%.mp4}_music.mp4"
}

echo "===== iOS reel ====="
APP_DIR=$APP PROJECT=$APP/overtonelab.swift.xcodeproj SCHEME=overtonelabReel \
  APP_BUNDLE=oleksandr.aisixteen.overtonelab SIM_NAME=Calc-iPhone17ProMax \
  SCENES=$ROOT/marketing/reels/overtonelab_scenes.json PLATFORM=ios \
  bash $ROOT/marketing/reels/make_reel.sh
mux $APP/marketing/aso/ios/video/framed_preview_886x1920.mp4

echo "===== iPad reel ====="
APP_DIR=$APP PROJECT=$APP/overtonelab.swift.xcodeproj SCHEME=overtonelabReel \
  APP_BUNDLE=oleksandr.aisixteen.overtonelab SIM_NAME=Calc-iPadPro13 \
  SCENES=$ROOT/marketing/reels/overtonelab_scenes_ipad.json PLATFORM=ipad \
  bash $ROOT/marketing/reels/make_reel.sh
mux $APP/marketing/aso/ipad/video/framed_preview_1200x1600.mp4

echo "===== Mac reel ====="
bash $APP/make_mac_reel.sh

echo "ALL REELS DONE"
