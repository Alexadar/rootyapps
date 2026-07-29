# Par — release checklist

Required by `calculators/VALIDATION.md`: *"non-scriptable incumbent cross-checks live in each app's
`RELEASE_CHECKLIST.md` as required manual sign-offs before the user green-lights a release. Nothing
uploads; the user is the final human checkpoint."*

Green tests are necessary, not sufficient. Everything below needs a human.

---

## 1. The two things the automated suite cannot settle

### 1.1 The IRS table anomalies — **must be re-read from a fresh copy of Publication 946**

`DepKit` reproduces 28 of the 30 published MACRS columns digit for digit. Two disagree by one unit in
the last published place, with the difference shifted to a later year so the column still totals
100.00%:

| table | column | year | published | Par computes |
|---|---|---|---|---|
| A-2 (mid-quarter, Q1) | 20-year | 2 | 7.000 | 7.008 |
| A-2 (mid-quarter, Q1) | 20-year | 21 | 0.565 | 0.557 |
| A-3 (mid-quarter, Q2) | 7-year | 1 | 17.85 | 17.86 |
| A-3 (mid-quarter, Q2) | 7-year | 8 | 3.34 | 3.33 |

Both were verified against 200-dpi renders of pages 71–72 of the 2025 edition. The A-3 case is the
clearer one: 2/7 × 0.625 = 17.857142…, which rounds to 17.86 by any ordinary rule, and the same
table's 3-year column (41.666… → 41.67) shows the IRS is rounding rather than truncating.

- [ ] Open the current Publication 946, Appendix A, and re-read those four cells.
- [ ] If the published values have changed, update `par/scratch/irs946_2025_table*.csv`, re-run
      `python3 par/scratch/macrs.py`, and remove the entries from
      `Oracles.knownPublishedAnomalies` in `DepKit`.
- [ ] If they have not, confirm the app's behaviour is acceptable: Par shows the **computed**
      percentage and flags the column in the provenance strip. Decide whether shipping the published
      figure instead is the right call for a tax tool.

### 1.2 RealEstateKit has no published oracle

`maxLoanByDSCR` and the ratios around it are definitions, cross-checked against the coverage they
reproduce rather than against a citation. An attempt to obtain a worked example from HUD's MAP guide
and an agency multifamily term sheet failed on 2026-07-27.

- [ ] Try once more for a citable underwriting example before release.
- [ ] If none is found, confirm the provenance strip's wording is honest: it currently reads
      *"definition · no published worked example obtained"*.

## 2. Incumbent cross-checks (pick a real device, do these by hand)

Run the same problem through Par and through an incumbent, and record both numbers.

- [ ] **TVM** — a 30-year mortgage: n 360, i 6.25%, PV 420,000, FV 0 → PMT. Compare against a
      published amortisation calculator, not another app of ours.
- [ ] **Bond** — 31 CFR 356 App B §II.A: C 8.75, i 8.84%, n 59, r = s = 184 → **99.057893**. This is
      in the test suite; do it once through the *interface* to prove the screen wires the same inputs.
- [ ] **APR** — Reg Z App J (c)(1)(i): 5,000 advanced, 24 × 230 → **9.69%**.
- [ ] **MACRS** — 10,000 of 7-year property, half-year → 1,429 / 2,449 / 1,749 / 1,249 / 893 / 892 /
      893 / 446.
- [ ] **Day count** — 2007-02-28 → 2007-08-31 under 30/360 = 183, 30E/360 = 182, 30E/360 (ISDA) = 180.
      The three disagreeing on screen is the feature.

## 3. The tape (this is what the app is bought for)

- [ ] Append a solve from **every one of the ten screens**; confirm each row shows a real result, not
      an em dash.
- [ ] Close the document, reopen it, and confirm every row still reads identically.
- [ ] Edit line 2's label; confirm lines 1 and 3 do not move.
- [ ] Force-quit mid-edit and reopen. Nothing may be lost — this is the incumbent's fatal bug
      (*"stored registers will 0 out for no reason whatsoever"*).
- [ ] Print the tape. Confirm the printed figures match the screen exactly.
- [ ] Export text and CSV; open the CSV in Numbers and confirm a label containing a comma survives.

## 4. Layout — the wedge

The incumbents' fatal reviews are about layout, not arithmetic. Every one of these is a customer.

- [ ] iPhone **portrait and landscape**, on a real device.
- [ ] iPad **Split View at every width**, and Slide Over. Nothing clipped, nothing unreachable.
- [ ] Mac window **dragged as small as it goes**, then full screen.
- [ ] **Dynamic Type at AX5** on every screen: numbers wrap, nothing truncates, no control is lost.
- [ ] VoiceOver reads a hero result as meaning, not glyphs ("present value, 420,000 dollars").
- [ ] Every tap target is at least 44 pt.

## 5. Store submission

- [ ] Bundle id is `oleksandr.aisixteen.fincalc` — registered, permanent, must not change.
- [ ] `PRODUCT_NAME` is `Par`; the macOS menu bar must not read "par.swift" or anything else.
- [ ] **No trademark anywhere** — app name, subtitle, keywords, description, screenshots, UI text,
      code identifiers: HP · 12C · BA II Plus · TI · Texas Instruments · 10bII.
- [ ] No trade dress: no gold-on-brown key grid, no borrowed key legends.
- [ ] Price set as a one-time purchase. **No StoreKit code, no IAP, no subscription, no ads.**
- [ ] `ITSAppUsesNonExemptEncryption` is NO and still true.
- [ ] Nothing in the app phones home. Confirm with a network monitor, not by reading the code.

## 6. Final gate

- [ ] `swift test` green in all ten Kits and in `Chains/ChainTests` (252 tests).
- [ ] `xcodebuild` green for iOS and macOS.
- [ ] `xcodebuild test -scheme Par -destination 'platform=macOS' -only-testing:ParTests` green.
- [ ] No `TODO(oracle):` remains unaccounted for — there is currently **one**, in RealEstateKit.
- [ ] The human has looked at the running app on a real device and said so.


## Marketing media — produced 2026-07-28, not uploaded

Captured from the Capture configuration on Calc-iPhone17ProMax and Calc-iPadPro13, `en_US`, 9:41
status bar. Nothing has been sent to App Store Connect and no version has been created.

| deliverable | iPhone 6.9" | iPad 13" |
|---|---|---|
| framed screenshots (6) | `aso/ios/1320x2868/` | `aso/ipad/2048x2732/` |
| store preview, **unframed** (2.3.4) | `aso/ios/video/store_preview_886x1920_*_music.mp4` | `aso/ipad/video/store_preview_1200x1600_*_music.mp4` |
| natural-speed reference (internal only) | `aso/ios/video/full.mp4` 49.3 s | `aso/ipad/video/full.mp4` 46.9 s |

Both previews are 28.5 s (cap 30 s), H.264, 30 fps, AAC 256k, no device frame, no bezel, no outro
card. The framed `framed_*.mp4` cuts are **not** for the App Store — captions and a border make them
social-only. The walkthrough is speed-fit ×1.73 (iPhone) / ×1.65 (iPad) to fit the cap.

Sign-offs still outstanding:

- [ ] **Listen to `marketing/audio/par_nyc60_a.wav`** and approve it before either preview is
      uploaded. Selection so far is by measurement only (see `marketing/audio/par_nyc60.txt`).
- [ ] Read all twelve screenshot captions against the shipped screens once more — the captions are
      claims, and `aso/*/params.yaml` is edited independently of the app.
- [ ] Confirm no screenshot or preview frame shows a competitor's marks. The tour never types one,
      but this is the check that catches a seeded tape label drifting.


## Pushed to App Store Connect — 2026-07-28

App `6795570043` · SKU `0000017`. **Nothing submitted; no price set.** Both platforms sit in
PREPARE_FOR_SUBMISSION.

| | iOS 1.0.0 | macOS 1.0.0 |
|---|---|---|
| build 1 | uploaded, VALID, attached | uploaded, VALID, attached |
| description / keywords / promo | 3039 / 93 / 160 chars | same |
| support + marketing URL | aisixteen.com | aisixteen.com |
| screenshots | iPhone 6.9" ×6, iPad 13" ×6 | **none — outstanding** |
| app previews | iPhone + iPad, processed COMPLETE | n/a |

Shared App Information: subtitle `Mortgage, TVM, bonds, IRR/NPV`, privacy `aisixteen.com/#privacy`,
categories Finance / Utilities, age rating 4+ (every descriptor declared none), content rights
declared as using no third-party content. Copy lives in `marketing/aso/metadata.yaml` — edit there,
not in the web UI, or the next push will overwrite it.

**The app had no icon.** The asset catalog listed sizes but contained no image files, which is what
altool rejected (90022/90023). `Par/Assets.xcassets/AppIcon.appiconset/icon_1024.png` is now a real
mark — right-aligned tape figures, the last one amber — generated from the app's own palette.

Still blocking submission:

- [ ] **macOS screenshots** (APP_DESKTOP, 2880×1800). Not captured: shooting them drives the Mac app
      on the real screen, which needs an explicit go-ahead.
- [x] **Price — $9.99** (USD), base territory USA, every other storefront derived by Apple's
      conversion table. Proceeds $8.49. One-time purchase; no IAP, no subscription, no StoreKit.
- [ ] **Listen to the music bed** before this goes to review — the previews are already uploaded with
      `par_nyc60_a.wav` on them and can be replaced until submission.
- [ ] Confirm `aisixteen.com` carries something a reviewer will accept as support, and that
      `#privacy` resolves.
