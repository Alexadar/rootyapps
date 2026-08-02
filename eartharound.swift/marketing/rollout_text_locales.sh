#!/usr/bin/env bash
# Stage the remaining 14 locales: keywords + subtitle only. No media — screenshots and previews
# inherit the primary language by Apple's own default, which is the whole point of shipping
# localized TEXT broadly while localizing MEDIA for only a few markets.
#
# Apple's locale codes are not always the BCP-47 tag we use internally: Norwegian is "no",
# Dutch is "nl-NL".
set -uo pipefail
cd /Users/oleksandr/Projects/rootyapps/eartharound.swift/marketing || exit 1
PY=/Users/oleksandr/miniconda3/envs/fantastic/bin/python
LOGIC=/Users/oleksandr/Projects/rootyapps/marketing/logic
APP=6794748918
VID_IOS=4f9196d6-d98d-41d2-9b50-9f0c061cd426
VID_MAC=fca1df37-3a9e-439d-9ed8-48432b0e9a6d
export ASC_KEY_ID=55B6L3J65N ASC_ISSUER_ID=057ddafb-cb0e-4410-9e0a-00e24f6e1688 \
       ASC_KEY_PATH=/Users/oleksandr/Projects/rootyapps/keys/AuthKey_55B6L3J65N.p8.txt

asc_locale() {
  case "$1" in
    uk) echo uk ;; it) echo it ;; pt-BR) echo pt-BR ;; nl) echo nl-NL ;;
    sv) echo sv ;; nb) echo no ;; da) echo da ;; fi) echo fi ;;
    pl) echo pl ;; cs) echo cs ;; tr) echo tr ;; ko) echo ko ;;
    zh-Hans) echo zh-Hans ;; zh-Hant) echo zh-Hant ;;
  esac
}

for loc in uk it pt-BR nl sv nb da fi pl cs tr ko zh-Hans zh-Hant; do
  L=$(asc_locale "$loc")
  KW=$("$PY" -c "import json;print(json.load(open('aso/keywords.json'))['locales']['$loc']['keywords'])")
  SUB=$("$PY" -c "import json;print(json.load(open('aso/keywords.json'))['locales']['$loc']['subtitle'])")
  for plat in IOS MAC_OS; do
    vid=$VID_IOS; [ "$plat" = MAC_OS ] && vid=$VID_MAC
    echo "--- $loc -> $L / $plat"
    "$PY" "$LOGIC/add_locale.py" --app-id $APP --platform $plat --locale "$L" \
        --version-id "$vid" --keywords "$KW" --subtitle "$SUB" 2>&1 | tail -3
  done
done
echo "TEXT LOCALES DONE"
