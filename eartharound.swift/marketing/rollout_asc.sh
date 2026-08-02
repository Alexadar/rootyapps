#!/usr/bin/env bash
# Stage every locale on the existing DRAFT versions: locale + subtitle + keywords, then media.
# Nothing is submitted and no version is created — both 1.0 versions already exist as
# PREPARE_FOR_SUBMISSION.
#
# Previews come from store_preview.py (full-bleed), never from the framed reel: guideline 2.3.4
# forbids frames, bezels and letterboxing in an app preview. Screenshots may be framed.
set -uo pipefail
cd /Users/oleksandr/Projects/rootyapps/eartharound.swift/marketing || exit 1
PY=/Users/oleksandr/miniconda3/envs/fantastic/bin/python
LOGIC=/Users/oleksandr/Projects/rootyapps/marketing/logic
SP=/Users/oleksandr/Projects/rootyapps/marketing/reels/store_preview.py
APP=6794748918
# Both 1.0 drafts, resolved once. Passing these skips /v1/apps entirely — that resource returned
# 500 for ~30 minutes on 2026-07-27 while every sub-resource kept working, which blocked the
# whole rollout at step one.
VID_IOS=4f9196d6-d98d-41d2-9b50-9f0c061cd426
VID_MAC=fca1df37-3a9e-439d-9ed8-48432b0e9a6d
vid_for() { [ "$1" = MAC_OS ] && echo $VID_MAC || echo $VID_IOS; }
export ASC_KEY_ID=55B6L3J65N ASC_ISSUER_ID=057ddafb-cb0e-4410-9e0a-00e24f6e1688 \
       ASC_KEY_PATH=/Users/oleksandr/Projects/rootyapps/keys/AuthKey_55B6L3J65N.p8.txt

# macOS ships bash 3.2, which has no associative arrays — a plain case mapping instead.
asc_locale() {
  case "$1" in
    en) echo en-US ;; de) echo de-DE ;; ja) echo ja ;;
    fr) echo fr-FR ;; es) echo es-ES ;;
  esac
}

echo "########## 1. build compliant full-bleed previews ##########"
for loc in en de ja fr es; do
  for plat in ios ipad mac; do
    sc="reels/scenes_${plat}_${loc}.json"
    [ "$plat" = ios ] && sc="reels/scenes_${loc}.json"
    [ "$loc" = en ] && { sc="reels/scenes.json"; [ "$plat" != ios ] && sc="reels/scenes_${plat}.json"; }
    vid="aso/$loc/$plat/video/full.mp4"
    [ -f "$vid" ] || { echo "skip $loc/$plat (no full.mp4)"; continue; }
    ls aso/$loc/$plat/video/store_preview_*_captions_music.mp4 >/dev/null 2>&1 && { echo "have $loc/$plat"; continue; }
    printf '%-10s ' "$loc/$plat"
    "$PY" "$SP" --scenes "$sc" --video "$vid" --out-dir "aso/$loc/$plat/video" \
        --audio audio/bed30_space_aurora.wav 2>&1 | grep -c 'store_preview' | xargs -I{} echo "built ({} lines)"
  done
done

echo "########## 2. locales + subtitle + keywords ##########"
for loc in en de ja fr es; do
  L=$(asc_locale "$loc")
  KW=$("$PY" -c "import json;print(json.load(open('aso/keywords.json'))['locales']['$loc']['keywords'])")
  SUB=$("$PY" -c "import json;print(json.load(open('aso/keywords.json'))['locales']['$loc']['subtitle'])")
  for plat in IOS MAC_OS; do
    echo "--- $L / $plat"
    "$PY" "$LOGIC/add_locale.py" --app-id $APP --platform $plat --locale "$L" \
        --version-id "$(vid_for $plat)" --keywords "$KW" --subtitle "$SUB" 2>&1 | tail -3
  done
done

echo "########## 3. screenshots ##########"
for loc in en de ja fr es; do
  L=$(asc_locale "$loc")
  "$PY" "$LOGIC/upload_screenshots.py" --app-id $APP --platform IOS --display APP_IPHONE_67 --version-id $VID_IOS \
      --locale "$L" --dir "aso/$loc/ios/1320x2868" --replace 2>&1 | tail -2
  # 13-inch (2064x2752 / APP_IPAD_PRO_3GEN_129) is what params.yaml now renders and what Apple
  # requires. This line used to upload aso/$loc/ipad/2048x2732 — a directory the generator no
  # longer writes, so every rollout re-uploaded the SAME frozen 12.9" images while the 13" set,
  # which the store also carries, was never refreshed by this script at all.
  "$PY" "$LOGIC/upload_screenshots.py" --app-id $APP --platform IOS --display APP_IPAD_PRO_3GEN_129 --version-id $VID_IOS \
      --locale "$L" --dir "aso/$loc/ipad/2064x2752" --replace 2>&1 | tail -2
  "$PY" "$LOGIC/upload_screenshots.py" --app-id $APP --platform MAC_OS --display APP_DESKTOP --version-id $VID_MAC \
      --locale "$L" --dir "aso/$loc/mac/2880x1800" --replace 2>&1 | tail -2
done

echo "########## 4. previews (full-bleed only) ##########"
for loc in en de ja fr es; do
  L=$(asc_locale "$loc")
  "$PY" "$LOGIC/upload_previews.py" --app-id $APP --platform IOS --display IPHONE_67 --version-id $VID_IOS --locale "$L" \
      --file "aso/$loc/ios/video/store_preview_886x1920_captions_music.mp4" --frame 00:00:06 --replace 2>&1 | tail -2
  "$PY" "$LOGIC/upload_previews.py" --app-id $APP --platform IOS --display IPAD_PRO_129 --version-id $VID_IOS --locale "$L" \
      --file "aso/$loc/ipad/video/store_preview_1200x1600_captions_music.mp4" --frame 00:00:06 --replace 2>&1 | tail -2
  "$PY" "$LOGIC/upload_previews.py" --app-id $APP --platform MAC_OS --display DESKTOP --version-id $VID_MAC --locale "$L" \
      --file "aso/$loc/mac/video/store_preview_1920x1080_captions_music.mp4" --frame 00:00:06 --replace 2>&1 | tail -2
done
echo "ROLLOUT DONE"
