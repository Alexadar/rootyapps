# Overtone Lab — App Store metadata (live record)

_Source of truth is App Store Connect; this file mirrors it. Last synced from ASC **2026-07-26**._

- **App id** `6787524729` · **bundle** `oleksandr.aisixteen.overtonelab` · **SKU** 0000013
- **Category** Music · **Age** 4+ · **Price** **$9.99** one-time (no ads, no subscription, no IAP)
- **Support / Marketing URL** https://aisixteen.com · **Privacy** Data Not Collected
- **Store page** https://apps.apple.com/us/app/overtone-lab/id6787524729
- **Min OS** 26.0 (iOS + macOS) · universal iPhone / iPad / Mac · seller Koreniuk Oleksandr

### Name & subtitle (shared `appInfo` — app-level, NOT per-version, and it ships with a release)
| Locale | Name | Subtitle |
|---|---|---|
| en-US (live) | Overtone Lab (12/30) | Audio & acoustics calculator (28/30) |
| en-US (**in review**) | **Overtone Lab Audio Calculator** (29/30) | **Room acoustics, loudness meter** (30/30) |
| es-MX (**in review**) | Overtone Lab Sound Toolkit (26/30) | Filter & compressor calculator (30/30) |

## Status (2026-07-26)
| Platform | Version | State | Build |
|---|---|---|---|
| macOS | 1.0 | **READY_FOR_SALE** (live since 2026-07-09) | 2 |
| macOS | 1.0.1 | **WAITING_FOR_REVIEW** (submitted 19:07 UTC) | 4 |
| iOS | 1.0 | **WAITING_FOR_REVIEW** (submitted 19:06 UTC) | 3 |

1.0.1 carries the `PRODUCT_NAME` fix (5.2.5) and the full-bleed Mac preview (2.3.4); iOS 1.0 carries
the full-bleed iPhone/iPad previews. Both also carry the ASO rework below.

**Rejection history — iOS 1.0 build 2, rejected 2026-07-09, Guideline 2.3.4 (Accurate Metadata):** the
app preview carried framing around the screen capture and a device frame. Fixed by re-rendering both
previews full-bleed with `marketing/reels/store_preview.py`; build 3 additionally corrects
`PRODUCT_NAME` (see below). Resubmitted 2026-07-26.

## Keywords (100-char field, per version + per locale)

**In review** on both iOS 1.0 and macOS 1.0.1 — see `ASO_AUDIT_2026-07-26.md` for how these were chosen:
```
en-US (99/100)  speaker,box,subwoofer,crossover,rt60,reverb,delay,time,string,tension,spl,decibel,lufs,tuning,cents
es-MX (98/100)  biquad,eq,stereo,ortf,mic,harmonic,frequency,wavelength,timecode,bpm,tempo,pipe,horn,thiele,sabine
```
Previously live (macOS 1.0): `lufs,crossover,reverb,delay,compressor,biquad,filter,stereo,ortf,fletcher,sabine,partch,tuning,cents`

Rules this set obeys: zero word overlap with name/subtitle (Apple combines across those three fields
within a locale, so repeating any word wastes budget) · **es-MX is self-sufficient** — combination
never crosses locales, so that locale carries its own head noun ("calculator" in its subtitle) ·
the atoms that unlock a phrase are the *specific* ones (`rt60`, `subwoofer`, `tension`), since the
bare head noun is owned by generic calculators with millions of ratings.

**es-MX is indexed on the US storefront** — it is ~160 extra indexed characters, not a translation.
Its media is inherited from en-US (no separate screenshots), which Apple accepted at submission.

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
- **App previews** 1× iPhone 6.5", 1× iPad 12.9", 1× Mac — **all three are now the compliant
  full-bleed cuts** from `marketing/reels/store_preview.py`, uploaded and transcoded. **Framing is NOT
  allowed here** — see `marketing/reels/README.md`. The framed `framed_preview_*` renders stay on disk
  for the site/socials and must never be uploaded.
  - iPhone/iPad cut from `full.mp4` via `src` windows in `reels/scenes*.json` (Tempo → Sabine →
    Benchmark, 28 s).
  - Mac cut from `mac_walkthrough.mp4`, recorded by `marketing/reels/mac_store_rec.sh` and configured
    by `reels/scenes_mac_store.json` (16.2 s). Re-record with that script — the old per-scene window
    clips are not kept.

## Provenance
Consolidates what were 10 separate calculator apps into one product (Guideline 4.3 — one substantial
app rather than many thin ones), and has since grown to 26 tools. Each tool's math is its own
validated `*Kit` SPM package with oracle tests (`docs/VALIDATION.md`). CommaKit's Scala archive stays
gitignored and is fetched by `Kits/Tuning/CommaKit-tools/fetch-oracles.sh`.

## Known follow-ups
- **Re-run the positional diagnostic 2–3 weeks after these land** (`ASO_AUDIT_2026-07-26.md` §2) and
  diff the positions. That is the only way to learn whether the keyword rework worked.
- **es-MX has no screenshots of its own.** Accepted at submission via the en-US fallback; if a
  reviewer objects it is a media-only fix, no new build.
- **Featuring Nomination** is unused — free, story-judged, no traffic prerequisite, ≥2 weeks lead.
- **No `SKStoreReviewController`** yet, and the app sits at 0 ratings. Apple confirms ratings feed
  both rank and click-through; the unincentivized native prompt is the only legal route.
- Name "Overtone Lab" is registered; bare "Overtone" was avoided as a likely collision. The store
  name becomes "Overtone Lab Audio Calculator" when the in-review `appInfo` is approved.
