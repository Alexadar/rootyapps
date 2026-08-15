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
#
# TWO PREVIEWS, IN ORDER. The store takes three per device size per locale, and this app now ships
# two reels — natal and sky. `REELS` below is the UPLOAD order and therefore the LISTING order:
# whichever goes first is the one that autoplays on the product page. Natal leads because it is
# what the name, the subtitle and the first three screenshots now promise.
#
# This used to glob "$SRC/video/store_preview_*_captions_music.mp4 | head -1", which is now wrong
# twice over: the reels live in video/<reel>/ since the two-reel reorganisation, so that pattern
# matches only the pre-natal July renders left behind one directory up — and `head -1` would have
# uploaded one of them and silently ignored the other reel entirely.
set -uo pipefail

LOGIC=/Users/oleksandr/Projects/rootyapps/marketing/logic
ASO=/Users/oleksandr/Projects/rootyapps/ephemeris.swift/marketing/aso
RAW=/Users/oleksandr/Projects/rootyapps/ephemeris.swift/marketing/raw
APP_ID=6782659268
DRY="${1:-}"

# Upload order IS listing order — the first one uploaded autoplays. Natal leads.
REELS=(natal sky)
# local dir : ASC locale
LOCALES=("en:en-US" "de:de-DE" "fr:fr-FR" "ja:ja")
# platform : local platform dir : screenshot slot : preview slot : screenshot source dir
#
# The source dir is spelled out per slot rather than derived, because the watch does not follow the
# aso/<loc>/<plat>/<WxH>/ convention: iPhone, iPad and Mac shots are FRAMED (caption band over a
# zoomed capture, rendered by generate_screenshots.py from params.yaml), and the watch has no
# params.yaml and no entry in captions.json — it never had a framing step. Its captures are already
# exactly 416×496, the APP_WATCH_SERIES_10 slot size, so they upload straight from raw/.
#
# `-` in the preview column means the slot takes no app preview. There is no watch reel.
SLOTS=(
  "IOS:ios:APP_IPHONE_65:IPHONE_65:$ASO/@LOC@/ios/1242x2688"
  "IOS:ipad:APP_IPAD_PRO_3GEN_129:IPAD_PRO_3GEN_129:$ASO/@LOC@/ipad/2048x2732"
  "MAC_OS:mac:APP_DESKTOP:DESKTOP:$ASO/@LOC@/mac/2880x1800"
  "IOS:watch:APP_WATCH_SERIES_10:-:$RAW/@LOC@/watch"
)

for pair in "${LOCALES[@]}"; do
  DIR="${pair%%:*}"; LOC="${pair#*:}"
  for slot in "${SLOTS[@]}"; do
    IFS=':' read -r PLAT PDIR SHOT_T PREV_T SHOTDIR <<<"$slot"
    SHOTDIR="${SHOTDIR//@LOC@/$DIR}"        # @LOC@ rather than a path fragment: no slashes to escape
    SRC="$ASO/$DIR/$PDIR"
    echo "── $LOC / $PLAT / $PDIR"

    if [ -d "$SHOTDIR" ] && [ -n "$(ls "$SHOTDIR"/*.png 2>/dev/null)" ]; then
      ~/miniconda3/envs/fantastic/bin/python "$LOGIC/upload_screenshots.py" --app-id "$APP_ID" --platform "$PLAT" \
        --display "$SHOT_T" --locale "$LOC" --dir "$SHOTDIR" --replace $DRY 2>&1 | tail -3
    else
      echo "   ⚠ no screenshots at $SHOTDIR"
    fi

    # The watch has no reel; skip the preview block entirely rather than warning about it 16 times.
    [ "$PREV_T" = "-" ] && continue

    # --replace only on the FIRST reel: it clears the locale's existing preview set, so passing it
    # again for the second reel would delete the first one that was just uploaded.
    REPLACE="--replace"
    for REEL in "${REELS[@]}"; do
      PREVIEW=$(ls "$SRC"/video/"$REEL"/store_preview_*_captions_music.mp4 2>/dev/null | head -1)
      if [ -z "$PREVIEW" ]; then
        echo "   ⚠ no $REEL preview for $DIR/$PDIR"
        continue
      fi
      echo "   ▶ preview: $REEL"
      ~/miniconda3/envs/fantastic/bin/python "$LOGIC/upload_previews.py" --app-id "$APP_ID" --platform "$PLAT" \
        --display "$PREV_T" --locale "$LOC" --file "$PREVIEW" $REPLACE $DRY 2>&1 | tail -3
      REPLACE=""
    done
  done
done
echo "UPLOAD DONE"
