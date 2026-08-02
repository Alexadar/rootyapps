#!/usr/bin/env bash
# Downloads oracle reference data into the gitignored Fixtures dir.
# Hard 1 GB per-app data cap (curl --max-filesize). If a source exceeds it, this aborts
# loudly — that app is a "for-later, big-machine" candidate.
set -euo pipefail
CAP=1073741824   # 1 GB
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FIX="$ROOT/CommaKit/Tests/CommaKitTests/Fixtures"
mkdir -p "$FIX"

URL="https://www.huygens-fokker.org/docs/scales.zip"   # Huygens-Fokker Scala scale archive (~5 MB)
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

echo "Fetching Scala archive (cap $CAP bytes)…"
if ! curl -fsSL --max-filesize "$CAP" "$URL" -o "$TMP/scales.zip"; then
  echo "ABORT: download failed or exceeds the 1 GB cap → mark as for-later. ($URL)"; exit 2
fi
unzip -oq "$TMP/scales.zip" -d "$FIX"
COUNT=$(find "$FIX" -name '*.scl' | wc -l | tr -d ' ')
echo "OK: $COUNT .scl files in $FIX"
[ "$COUNT" -ge 100 ] || { echo "WARN: unexpectedly few .scl files"; exit 3; }
