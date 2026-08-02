#!/bin/bash
# TrueCourse — build all app-preview reels (iPhone + iPad here; Mac via make_mac_reel.sh).
# Records the ReelTour XCUITest, conforms, frames (captions + outro). Silent output is the
# App Store upload; a *_music.mp4 is muxed separately for social use.
set -euo pipefail

ROOT=/Users/oleksandr/Projects/rootyapps
APP=$ROOT/truecourse.swift
MK=$ROOT/marketing/reels/make_reel.sh

run(){  # SIM_NAME  SCENES  PLATFORM
  APP_DIR="$APP" PROJECT="$APP/truecourse.swift.xcodeproj" SCHEME=truecourseReel \
    APP_BUNDLE=oleksandr.aisixteen.truecourse ONLY_TESTING=truecourseUITests/ReelTour \
    SIM_NAME="$1" SCENES="$2" PLATFORM="$3" \
    bash "$MK"
}

run Calc-iPhone17ProMax "$APP/marketing/reels/scenes.json"      ios
run Calc-iPadPro13      "$APP/marketing/reels/scenes_ipad.json" ipad

echo "Reels → $APP/marketing/aso/{ios,ipad}/video/framed_preview_*.mp4"
