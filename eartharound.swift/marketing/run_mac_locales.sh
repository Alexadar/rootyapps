#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")"
for loc in de ja fr es; do
  echo "=== macOS $loc"; ./make_mac_shots.sh "$loc" 2>&1 | tail -1
done
echo "MAC LOCALES DONE"
