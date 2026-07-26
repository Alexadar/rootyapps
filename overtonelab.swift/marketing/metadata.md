# Overtone Lab — App Store metadata (live record)

_Source of truth is App Store Connect; this file mirrors it. Last synced from ASC **2026-07-26**._

- **App id** `6787524729` · **bundle** `oleksandr.aisixteen.overtonelab` · **SKU** 0000013
- **Name** Overtone Lab · **Subtitle** Audio & acoustics calculator · **Category** Music · **Age** 4+
- **Price** **$9.99** one-time (no ads, no subscription, no IAP) · seller Koreniuk Oleksandr
- **Support / Marketing URL** https://aisixteen.com · **Privacy** Data Not Collected
- **Store page** https://apps.apple.com/us/app/overtone-lab/id6787524729
- **Min OS** 26.0 (iOS + macOS) · universal iPhone / iPad / Mac

## Status (2026-07-26)
| Platform | Version | State | Build |
|---|---|---|---|
| macOS | 1.0 | **READY_FOR_SALE** (live since 2026-07-09) | 2 |
| iOS | 1.0 | **WAITING_FOR_REVIEW** | 3 |

**Rejection history — iOS 1.0 build 2, rejected 2026-07-09, Guideline 2.3.4 (Accurate Metadata):** the
app preview carried framing around the screen capture and a device frame. Fixed by re-rendering both
previews full-bleed with `marketing/reels/store_preview.py`; build 3 additionally corrects
`PRODUCT_NAME` (see below). Resubmitted 2026-07-26.

## Keywords (100 char field, live)
```
lufs,crossover,reverb,delay,compressor,biquad,filter,stereo,ortf,fletcher,sabine,partch,tuning,cents
```
Deliberately **excludes** words already in the name/subtitle (overtone, lab, audio, acoustics,
calculator) — those are indexed from those fields and repeating them wastes the budget.

## Promotional text (170)
> 26 precision audio tools — tuning, acoustics, filters, stereo imaging, loudspeaker design & real
> BS.1770 loudness. Fully offline, exact, buy once. No subscription.

## Description
Opens on the positioning line, then all **26 tools in seven sections** (Tuning · Timing · Acoustics ·
Signal · Stereo · Utility · Design), then the offline/buy-once close and the estimate caveat. The full
text lives in ASC; pull it with `marketing/logic/fetch_app_localizations.py` rather than duplicating
it here, so this file can't drift.

## Media
- **Screenshots** 6× iPhone 6.5" (`APP_IPHONE_65`), 4× iPad Pro 12.9" (`APP_IPAD_PRO_3GEN_129`),
  4× Mac (`APP_DESKTOP`) — framed by `marketing/generate_screenshots.py`. **Framing is allowed here.**
- **App previews** 1× iPhone 6.5", 1× iPad 12.9", 1× Mac. **Framing is NOT allowed here** — see
  `marketing/reels/README.md`. iOS/iPad are the compliant full-bleed cuts; **the Mac preview is still
  the old framed render** and must be replaced on the next macOS version.

## Provenance
Consolidates what were 10 separate calculator apps into one product (Guideline 4.3 — one substantial
app rather than many thin ones), and has since grown to 26 tools. Each tool's math is its own
validated `*Kit` SPM package with oracle tests (`docs/VALIDATION.md`). CommaKit's Scala archive stays
gitignored and is fetched by `Kits/Tuning/CommaKit-tools/fetch-oracles.sh`.

## Known follow-ups
- **macOS 1.0.1** owes two fixes: the corrected `PRODUCT_NAME` (1.0 shipped with a menu bar reading
  `overtonelab.swift` — Guideline 5.2.5 risk) and a full-bleed replacement for the framed Mac preview.
- Name "Overtone Lab" is registered; bare "Overtone" was avoided as a likely collision.
