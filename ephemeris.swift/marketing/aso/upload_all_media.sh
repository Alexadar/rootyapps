#!/usr/bin/env bash
#
# upload_all_media.sh [--dry-run] — push every localized screenshot set and app preview to the
# editable App Store version.
#
# Slot names are the fiddly part and are wrong in two different ways if you guess:
#   • screenshot display types carry an APP_ prefix, preview types do NOT (IPHONE_65, not
#     APP_IPHONE_65) — a mismatched preview type returns a 500, not a helpful error;
#   • the iPad slot in use on this listing is APP_IPAD_PRO_3GEN_129. Uploading to
#     APP_IPAD_PRO_129 silently creates a second, unused set and the shots never appear.
# Both were learned by getting them wrong.
#
# Only the *_captions_music.mp4 cut is uploaded: App Store Connect rejects a preview with no
# AAC track as "unsupported or corrupted audio", so the video-only variants are never valid.
set -uo pipefail

LOGIC=/Users/oleksandr/Projects/rootyapps/marketing/logic
ASO=/Users/oleksandr/Projects/rootyapps/ephemeris.swift/marketing/aso
APP_ID=6782659268
DRY="${1:-}"

# local dir : ASC locale
LOCALES=("en:en-US" "de:de-DE" "fr:fr-FR" "ja:ja")
# platform : local platform dir : screenshot slot : preview slot : screenshot px dir
SLOTS=(
  "IOS:ios:APP_IPHONE_65:IPHONE_65:1242x2688"
  "IOS:ipad:APP_IPAD_PRO_3GEN_129:IPAD_PRO_3GEN_129:2048x2732"
  "MAC_OS:mac:APP_DESKTOP:DESKTOP:2880x1800"
)

for pair in "${LOCALES[@]}"; do
  DIR="${pair%%:*}"; LOC="${pair#*:}"
  for slot in "${SLOTS[@]}"; do
    IFS=':' read -r PLAT PDIR SHOT_T PREV_T PX <<<"$slot"
    SRC="$ASO/$DIR/$PDIR"
    echo "── $LOC / $PLAT / $PDIR"

    if [ -d "$SRC/$PX" ]; then
      python3 "$LOGIC/upload_screenshots.py" --app-id "$APP_ID" --platform "$PLAT" \
        --display "$SHOT_T" --locale "$LOC" --dir "$SRC/$PX" --replace $DRY 2>&1 | tail -3
    else
      echo "   ⚠ no screenshots at $SRC/$PX"
    fi

    PREVIEW=$(ls "$SRC"/video/store_preview_*_captions_music.mp4 2>/dev/null | head -1)
    if [ -n "$PREVIEW" ]; then
      python3 "$LOGIC/upload_previews.py" --app-id "$APP_ID" --platform "$PLAT" \
        --display "$PREV_T" --locale "$LOC" --file "$PREVIEW" --replace $DRY 2>&1 | tail -3
    else
      echo "   ⚠ no preview for $DIR/$PDIR"
    fi
  done
done
echo "UPLOAD DONE"
