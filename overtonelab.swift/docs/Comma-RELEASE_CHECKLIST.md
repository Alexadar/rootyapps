# Comma — Release checklist

Status: **built, tested, runs on simulator, screenshots generated. NOT uploaded.**

## Automated (done)
- [x] `swift test` in CommaKit — 6 tests green: identities (EDO, named intervals, SCL parse) + **Scala-archive oracle** (parser validated against 5401 independent reference tunings; ¼-comma meantone cross-check). Fetch via `tools/fetch-oracles.sh` (fail-loud if absent).
- [x] Builds for iOS Simulator; 3 tabs render; values verified (700¢↔1.4983, commas 21.506/23.460¢).
- [x] Offline audit clean (app bundles no data — pure computation); no network entitlement.
- [x] iOS marketing screenshots; icon in place.

## Human checkpoints (before release)
- [ ] Spot-check a few generated scales against named Scala entries (beyond meantone).
- [ ] (Optional) add scale import/export (.scl), more historical temperaments, and a keyboard/pitch playback.

## Manual release steps (deliberately NOT performed)
- [ ] Create ASC app record; metadata; archive/sign/upload; screenshots; submit.
