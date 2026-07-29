# DESIGN BRIEF — Storypole

> **Paste this whole file into a fresh Claude Code session.** It is self-contained; assume no
> memory of prior chats. Working dir = the `rootyapps` repo root; the app is `storypole/`.
>
> Written 2026-07-29, after the oracle gate and the Kits. Provenance:
> `docs/storypole_oracle_gate_2026-07-29.md` (the gate) · `docs/HANDOFF_storypole.md` (the brief).

---

## 0. What exists, and what your job is

`storypole/` is a feet-inch-fraction tape-measure calculator for iOS, macOS and watchOS. **Seven
Kits are green (138 tests) and all three platforms build.** A working native UI exists — 3 tabs,
16 calculators, a watch app with 7. It is deliberately plain: native components, no invented
design system.

**Your job is the visual design.** Absorb design files into the existing structure without
restructuring it. `DesignShared/` exists precisely so tokens have somewhere to land.

**Hard non-goals:**
- ❌ **Never boot a simulator.** No `simctl`, no screenshots, no XCUITest runs. Verify with
  `xcodebuild build` on each platform plus authored `#Preview`s. The human does the visual review.
- ❌ Do not invent a calculator that is not in §1. Do not remove one.
- ❌ Do not change number formatting, rounding, or unit display. §3 is correctness, not taste.
- ❌ No StoreKit, ads, subscriptions, IAP, network, or analytics. Paid-upfront, offline, buy-once.
- ❌ No App Store version, submission, price, or TestFlight. Those are the owner's decisions.

---

## 1. The oracle list — the contract

Every shipping calculator, with the authority behind it. **Design must not invent a function that
is not on this list.** Class per the house taxonomy: **PUBLISHED** (an external published number) ·
**IDENTITY** (a definition, cross-checked numerically) · **INVARIANT** (bounds, round-trips).

| # | Calculator | Kit | Class | Authority · worked example | In → out |
|---|---|---|---|---|---|
| 1 | Tape calculator | `DimensionKit` | PUBLISHED | NIST SP 811 §B.7.1 · `6.9749505` → 7 digits = `6.974950` | `FeetInch` → `FeetInch` |
| 2 | Dimensional × ÷ | `DimensionKit` | IDENTITY | linear×linear=square · `12'4" × 12'4" = 152.11 sq ft` | `FeetInch`,`Dim` → `FeetInch`,`Dim` |
| 3 | Fraction round | `DimensionKit` | PUBLISHED | NIST PS 20-20 App.B §B1 · `7½" × 25.4 = 190.5 → 190 mm` | `FeetInch`,`Int64` → `FeetInch` |
| 4 | Length conversion | `DimensionKit` | PUBLISHED | Fed. Reg. 59-5442 (1959) · 1 in ≡ 25.4 mm **exact** | `Rational`,`LengthUnit` → `Rational` |
| 5 | Equal spacing | `LayoutKit` | **IDENTITY** | *No published authority — see §2.* 7 balusters in 62¼" → gap exactly `207/32"` | `FeetInch`,`Int` → `[FeetInch]` |
| 6 | On center | `LayoutKit` | PUBLISHED (values) + IDENTITY | USDA Ag. Handbook 73 · *"studs spaced 16 inches on center"* · 20'7½" at 16" o.c. → 16 studs, 7½" last bay | `FeetInch`,`Spacing` → `Layout` |
| 7 | Area | `VolumeKit` | IDENTITY | Heron on 3-4-5 = 6, cross-checked against ½bh | `Double` → `Double` |
| 8 | Volume | `VolumeKit` | IDENTITY | cone = ⅓ cylinder | `Double` → `Double` |
| 9 | Cubic yards | `VolumeKit` | PUBLISHED | NIST SP 811 §B.8 · yd³→m³ = `7.645549E−01` | `Double` → `Double` |
| 10 | Roof pitch | `PitchKit` | IDENTITY | 6/12 → 26.565°, 50 %, multiplier √1.25 | `Double` → `Double` |
| 11 | Rafter | `PitchKit` | IDENTITY | framing square: 6/12 → 13.42"/ft · hip 18.00"/ft | `Double` → `Double` |
| 12 | Square up | `GeometryKit` | IDENTITY | 3-4-5 and 5-12-13 exact | `Double` → `Double` |
| 13 | Miter & bevel | `GeometryKit` | PUBLISHED | crown tables · 38° spring → 31.62° / 33.86° | `Double`,`Int` → `(Double,Double)` |
| 14 | Circle / pipe wrap | `GeometryKit` | IDENTITY | circumference = πd | `Double` → `Double` |
| 15 | Board feet | `LumberKit` | PUBLISHED | NIST PS 20-20 §2.2 · 2×4×8 = **16/3 BF exactly** | `Rational` → `Rational` |
| 16 | Nominal vs dressed | `LumberKit` | PUBLISHED | PS 20-20 Table 3 · 2×4 dry = 1½" × 3½" | `Rational` → `FeetInch` |
| 17 | Wire gauge | `GaugeKit` | PUBLISHED | NBS Handbook 100 §2.1 · ³⁹√92 = 1.1229322 | `Int` → `Double` |

That is **16 user-facing calculators** (1–4 are the tape engine, presented as three tools plus the
keypad). `Tool` in `DesignShared/ToolCatalog.swift` is the machine-readable version of this table.

### The one honest caveat, which must survive into any copy you write

SP 811 §B.7.1 rounds **decimal digits**; PS 20-20 §B1 rounds **millimetres**. Neither publishes a
rule for rounding to a binary fraction denominator (1/16, 1/32, 1/64). What is cited is the
**tie-breaking rule**; applying it at a fraction denominator is this app's extension by analogy.
Never claim NIST publishes a worked 1/16 example. It does not.

---

## 2. The discard list — do not propose these back in

| Discarded | Why |
|---|---|
| **Cut list with kerf** | No published authority, and `cut list optimizer` already autocompletes to five named apps (cutflow, glessio, kerf, kerfmate, lumbercut). |
| **Drill sizes** (number/letter) | ANSI/ASME B94.11M is copyrighted and purchase-only. *ASTM v. Public.Resource.Org* covered non-commercial dissemination only. |
| **Pipe schedule dimensions** | ASME B36.10M / B36.19M copyrighted; wall thickness is tabulated, not computed. |
| **Anything electrical past dimension** | Ampacity, conductor sizing, voltage drop, box fill — the owner's liability line. AWG *diameter* survives; nothing else. |
| **On-screen physical ruler** | Depends on per-device screen PPI, breaks on unknown future devices and display-zoom modes. It is the incumbent's single largest source of 1★ reviews. |
| **Log rules** (Doyle/Scribner) | Passes the gate (USDA GTR FPL-1, public domain) but fails theme fit: forestry, not tape work. |
| **Generic unit conversion / currency** | Apple ships 121 units offline and free; free incumbents hold 190k/128k/81k ratings. |
| **AR measuring** | Apple's Measure app owns it. Storypole never measures — it does maths on a measurement already taken. Say so in store copy: ~15 of the incumbent's 1★ reviews are buyers who expected an AR tape. |

**Equal spacing and on-center have no published authority** and ship as IDENTITY/INVARIANT by an
explicit owner decision (2026-07-29). Label them honestly; never dress an identity as an oracle.

---

## 3. Units and formatting — correctness, not preference

Design may not override any of these.

1. **Fractions first, always.** Decimals appear only as a secondary line or on request. Defect ④:
   *"Normal carpentrs do not use decimals we use fractions."* (3★ 2025-10-14)
2. **Selectable denominator**, 1/2 … 1/64. Default 1/16.
3. **Ties go to even** by default (`RoundingRule.halfToEven`). The trade convention
   (`.halfAwayFromZero`) is offered and **labelled as having no published authority**.
4. **Round at the display denominator only**, never at intermediate steps. The Kits handle this;
   do not add rounding in a view.
5. **Never render a tape past a real tape's length.** `Tape.smallest(for:)` returns `nil` and the
   graphic must then not be drawn. There is deliberately no "use the longest" fallback — that is
   the defect. Blade labels are **feet and inches**, never a running inch count.
6. **Feet and Inch keys are never disabled.** Not on the second operand, not ever. This is the
   incumbent's twelve-year defect.
7. **Fractions are typed numerator-first** — numerator, `/`, denominator. Three separate reviewers
   call the incumbent's denominator-first spinner backwards.
8. **US survey foot** is a labelled legacy mode only; default is the international foot.

---

## 4. Platform matrix

| | iPhone | iPad | Mac | Watch |
|---|---|---|---|---|
| Tape calculator + tape graphic | ✅ | ✅ | ✅ | ✅ (running total) |
| Convert · Roof pitch · Square up · Circle · Board feet · Wire gauge | ✅ | ✅ | ✅ | ✅ |
| Fraction round · Area · Volume · Cubic yards · Rafter · Miter · Nominal vs dressed | ✅ | ✅ | ✅ | ❌ |
| **Equal spacing · On center** | ✅ | ✅ | ✅ | ❌ — the answer is a list |
| Reference (the citations) | ✅ | ✅ | ✅ | ❌ |

**iPhone/iPad/Mac must behave identically.** The incumbent crashes on iPad on its core feature
(2★ 2026-01-10) — parity is the wedge, not a nicety. Compact width = 3 tabs (Calc / Tools /
Reference); regular width and Mac = `NavigationSplitView`.

**Watch rules, inherited from `overtonelab.swift/DesignSystem/DESIGN_GUIDELINES.md` §8:**
- **Stack, never row** — labels above values, so a long localized label never moves the number.
- **The Digital Crown replaces number entry.** `TapeCrownField` drives *sixteenths as an integer*
  — fine detent 1/16", fast spin 1". This is how you enter a fraction without a keyboard, and it is
  the single most important thing on the watch.
- **No paging between tools.** List ↔ tool, header button plus a left-to-right drag. overtonelab
  tried paging twice and removed it: it fights the crown.
- **Never `.textCase(.uppercase)`** on notation — it corrupts Greek and technical strings.
- Opens on the last-used tool, already showing a number.
- **No complication in v1**, so no App Group is needed. If one is ever added: register bundle IDs
  and `APP_GROUPS` via the ASC API, but **the group identifier itself must be created by Xcode** —
  build *without* `-authenticationKey*` or provisioning fails with a misleading
  *"Provisioning profile doesn't support the … App Group"*. And adopt
  `.containerBackground(.clear, for: .widget)` or it renders grey on a real device.

---

## 5. Accessibility floor

- **Dynamic Type throughout. No pinned point sizes.** (The watch has a few `size:` values for
  chrome glyphs only; no readout uses one.)
- `accessibilityIdentifier` on **every** input and every result. The convention is already in
  place: `calc.readout`, `key.digit7`, `spacing.marks`, `bf.total`, `awg.inch`.
- Results combine into one accessibility element with a label and a value.
- Crown fields implement `accessibilityAdjustableAction`.
- Colour is never the only signal — the "derived spacing" warning carries text, not just a tint.

---

## 6. What you may decide, and what you may not

**Free:** layout, hierarchy, spacing, colour, typography, motion, iconography, the tape graphic's
visual treatment, empty states, onboarding, the catalog's presentation.

**Fixed:** the calculator list (§1) · number formatting, rounding and unit display (§3) · the
discard list (§2) · the platform matrix (§4) · the accessibility floor (§5) · no
StoreKit/network/analytics.

If a design needs a number the Kits do not expose, that number does not exist yet — it must pass
the four-step oracle gate in `HANDOFF_storypole.md` §4 before any pixel depends on it.

---

## 7. Where things are

```
storypole/
  project.yml                    XcodeGen. PRODUCT_NAME: Storypole on EVERY target (5.2.5).
  Storypole/
    StorypoleApp.swift  ContentView.swift  Router.swift
    Calc/CalcView.swift          the keypad + readout + history
    Calc/TapeView.swift          the tape graphic — takes NO arithmetic decisions of its own
    Tools/                       ToolDetailView + the 16 calculators, grouped by section
    Views/                       Components (ResultRow, DimensionField, NumberField), catalog, Reference
  StorypoleWatch/                App, WatchRootView, WatchToolList, WatchComponents
  DesignShared/                  Tokens(SP), Format(Fmt), LanguageStore, ToolCatalog  ← tokens land here
  Kits/<Group>/<Name>Kit/        7 packages, Sources + Tests + Oracles.swift
  storypole.icon/                Icon Composer source; tools/genicon.py regenerates 1024.png
  storypoleUITests/              AUTHORED, NOT RUN — needs a sim; not wired into any scheme
```

`ToolDetailView` and `WatchToolView` each split their tool switch across **two** `@ViewBuilder`
functions. Keep that: one switch over 16 cases blows the type-checker's expression limit and it
reports the failure on an unrelated line.

---

## 8. Verify

```bash
cd storypole/Kits/<Group>/<Name>Kit && swift test     # all 7 green — 138 tests
cd storypole && xcodegen generate
xcodebuild -scheme storypole -destination 'generic/platform=iOS' build     # embeds the watch app
xcodebuild -scheme storypole -destination 'platform=macOS'       build
```

Plus a `#Preview` on every view you touch. **That is the whole gate. Do not boot a simulator.**

Design files are expected to land after this brief. The app must absorb them without
restructuring — which is why `DesignShared/` exists and why no view computes a number.
