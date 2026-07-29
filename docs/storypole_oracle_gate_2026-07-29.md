# Storypole — Phase A + Phase B report (research → oracle gate)

> Executed 2026-07-29 per `docs/HANDOFF_storypole.md` §8. **Phases A and B only.** No directory was
> created, no code written. Phase C does not begin until this report is approved.
>
> Everything below was fetched live and read. Cache + fetch log:
> `<scratchpad>/authorities/fetch_log.tsv`, `<scratchpad>/reviews/`, `<scratchpad>/hints/`.
> Worked-example reproduction: `<scratchpad>/verify_oracles.py` — **all pass**.

---

## 0. Headline

**The oracle story is stronger than the handoff assumed, and the market story is weaker.**

- The rounding rule at the heart of the app is not merely citable — it has a **published,
  discriminating worked example**. NIST PS 20-20 Table 3 lists a lumber dimension where
  round-half-to-even and round-half-away-from-zero give *different* answers, and the standard
  publishes the half-to-even one. That single table row is the best oracle in the corpus.
- Two citations in the handoff are **wrong and are corrected below** (`PS 20-25` does not exist;
  the AWG passage is §2.1, not §2.2).
- Three of the ten candidates have **no published authority at all** and survive only as
  IDENTITY/INVARIANT. They are also the three the handoff calls the strongest differentiators.
  That is a decision for you, set out in §4.
- The **single most-repeated functional complaint in 455 incumbent reviews is not in the §3 ten**:
  you cannot multiply one dimension by another. It spans 2014→2025. Added as **NEW**.
- The search terms are **not** an open field. `feet inch calculator` autocompletes to eight
  competitor app names, and the top-ranked apps on all three target terms are free with
  9k–39k ratings, including Calculated Industries' own. See §6 — this is the material risk.

---

## 1. Phase A — what was actually read

| Source | Result |
|---|---|
| Customer Reviews RSS, `482504435`, pages 1–10 | **455 unique reviews**, 2011-12-10 → 2026-07-02. Histogram 1★:37 2★:16 3★:13 4★:39 5★:350 |
| iTunes lookup, incumbent | live: $3.99 · 2,193 ratings · 4.848★ · v4.9 · 2025-10-07 · minOS 11.0 · Bugfoot Studios LLC · Utilities |
| Apple autocomplete (`MZSearchHints`, store-front `143441-1,29`) | **53 terms probed, 42 returned hints** |
| iTunes search, 3 target terms | top-5 competitor sets (§6) |
| `marketing/autoaso.md` §6.4, §6.5 | read before any classification |

> **Endpoint note for whoever runs this next:** `MZSearchHints` returns an **XML plist**, not JSON,
> despite the `json`-ish call shape. Parse with `plistlib`. Shopping-intent forms
> (`best X apps`, `apps for X`) returned **zero** hints across all five tried — in this category
> the demand sits on the bare tool phrase.
>
> `k5_phrases.json` is **not in the repo** (nor `kerflike.py` / `upgrade.py`). The 53-term corpus
> here was collected fresh. If you still have the 228-phrase set, handing it over would make the
> keyword block comparable to the earlier sweeps.

### The four handoff defects — all four verified verbatim

Each was found in the live pull at the quoted date and star rating. They are real.

1. **iPad crash on fractions** — 2★ 2026-01-10 v4.9: *"it works great on my iPhone but it crashes
   every single time I try to use a fraction on my iPad. There's no place to ask for support"*
2. **Tape graphic wrong** — 1★ 2025-09-26 v4.8.1: *"Wrong result showing in tape measure graphic"*
3. **Cannot multiply** — 1★ 2025-11-22 v4.9: *"Awful app can't even multiply for square footage.
   Developer should be more transparent, no response when contacting about issue."*
4. **Violates the trade's convention** — 3★ 2025-10-14 v4.9: *"Normal carpentrs do not use decimals
   we use fractions. The tape at the end is in inches for some crazy reason. No tape goes into the
   200s that I've ever seen. This should be feet and inches."*

### What the handoff missed — defect ③ is far bigger than one review

**Dimensioned multiplication has been broken since at least 2014 and is the most-repeated
functional complaint in the corpus.** Twelve years, one unfixed defect:

> 2★ 2014-08-04 — *"I hit the 'X' multiplication symbol then go to put in the 2nd measurement of
> 11 feet 4 inches, I cannot do it because the **FEET and INCHES buttons are GRAYED OUT**...
> it works with subtraction and addition, just not multiplication and division."*
> 2★ 2016-09-24 — *"I can not multiply 12'-4" X 12'-4"... **I need feet and inches by feet and
> inches. NO need for decimals.**"*
> 2★ 2018-10-11 — *"you can't multiply feet to feet or inches to inches due to not being able to
> enter the 'Feet or Inches' to the second measurement."*
> 1★ 2019-05-06 · 1★ 2019-03-18 · 1★ 2015-06-17 · 1★ 2025-11-22 — same defect.

This is a **dimensional-analysis** requirement (linear × linear = area; area ÷ linear = linear),
not a missing button. It is added as a function in §3.

### Also found, not in the handoff

| Finding | Evidence |
|---|---|
| **Decimal output where fractions are required** — defect ④, independently stated | 2★ 2016-09-24: *"19'-10" + 46' should equal 65'-10" Your calculator says **65.653789'** this is a useless number for a builder"* · 2★ 2023-10-07: *"If i wanted to see decimals, I'd just use my calculator app."* |
| **Tape shows inches only, not feet+inches** — defect ④ again | 5★ 2016-04-25: *"Wish you could change the ruler to feet and inches not just inches, so you can easily say **3' 5 5/16" instead of just seeing 41 5/16"**"* |
| **A real fraction-arithmetic error** | 2★ 2021-07-10: *"I knew it had to end in 15/16 ... but it came up **13/16**. Did the calculation by hand to confirm."* (reproduced as an invariant test — see §5) |
| **Negative mixed numbers rendered wrong** | 5★ 2016-04-25: *"it would show **-7 7/8 but it should be -7 1/8**... Can't have numbers going backwards and fractions going forward."* |
| **Wrong tape graphic cost real money** | 1★ 2020-11-13: *"Do not trust the tape on this app. It's an 1" short on every measurement. **This app cost me hundreds of dollars in miscut wood.**"* |
| **Fraction entry is a spinner, denominator-first** | 5★ 2022-02-04: *"wish it didn't make me do the denominator first"* · 4★ 2021-01-03: *"**This is backwards**"* · 3★ 2019-06-04: *"too time consuming to use the fraction spin things in the shop. **If you could directly enter fractions, this would rock!**"* |
| **Automatic halving / quartering** | 5★ 2024-03-14: *"The only thing I wish it had was an **automatic halving setting**"* · 5★ 2014-07-28: *"where are the **4 quarters of a drawer face that measures 17 7/16"**"* |
| **Recall a previous result into the next calculation** | 5★ 2020-04-17: *"I would like to be able click on a measurement I just calculated and be able to add or subtract from that"* (= `autoaso` §6.4 aim-higher #1, STATEFUL) |
| **No landscape** | 1★ 2023-04-09: *"What app nowadays does not work in landscape? THIS ONE!"* |

**The best demand quote in the corpus**, 5★ 2024-06-04, and the reason cut lists matter:

> *"I calculate cut lists so I'm not crossing back and forth across our 8,000 sqf shop wasting
> time... going from 16ths (my general margin of error) to decimals and back and forth... quite
> often the **shop fairy** swoops down and steals 1/4" or 1/2" or adds 1" and then I'm going back
> across the shop to grab another piece."*

**Trades named by actual buyers:** electrician · goldsmith · cabinet maker · welder/fabricator ·
draftsman · furniture maker (40 years) · hobby woodworker · deck builder · remodeller · homeowner.

---

## 2. Authorities — fetched, opened, and confirmed to say what was claimed

| ID | Document | HTTP | Claim confirmed? |
|---|---|---|---|
| `sp811` | NIST SP 811 (2008), `nvlpubs.nist.gov/nistpubs/Legacy/SP/nistspecialpublication811e2008.pdf` | **200** | ✅ §B.2, §B.7.1, §B.7.2, §B.8 all verbatim |
| `ps20` | NIST **PS 20-20** (Jan 2020), `nist.gov/document/doc-ps-20-20-american-softwood-lumber-standard` | **200** | ✅ §2.2, Table 3, App. B §B1 verbatim |
| `hb100` | NBS Handbook 100, `nvlpubs.nist.gov/nistpubs/Legacy/hb/nbshandbook100.pdf` | **200** | ✅ AWG law — but at **§2.1**, not §2.2 |
| `fr85` | 85 FR 62698, Federal Register API doc `2020-21902` | **200** | ✅ "Deprecation of the U.S. Survey Foot", 2020-10-05 |
| `nist_length` | NIST "SI Units – Length" | **200** | ✅ quotes Fed. Reg. 59-5442: inch *"exactly equivalent to 25.4 mm"* |
| `logrules` | Freese, *A Collection of Log Rules*, GTR FPL-1, `research.fs.usda.gov/download/treesearch/9829.pdf` | **200** | ✅ public domain — **discarded on theme fit**, §4 |
| `ah73` | USDA Agriculture Handbook 73, *Wood-Frame House Construction* | **200** | ✅ 16" and 24" o.c. verbatim; **19.2" absent** |
| `ps20_25` | the handoff's "NIST PS 20-25" | **404** | ❌ **does not exist** |

> `fpl.fs.usda.gov` returns **403** to scripted requests for all three GTRs. The documents are
> reachable at `research.fs.usda.gov/download/treesearch/<id>.pdf`. Use that host.

### ⚠️ Two citation corrections the handoff carries

1. **There is no NIST PS 20-25.** The current American Softwood Lumber Standard is
   **PS 20-20, January 2020**. `nvlpubs.nist.gov/nistpubs/ps/NIST.PS.20-25.pdf` → 404; the NIST
   document page serves PS 20-20, whose cover reads *"Voluntary Product Standard PS 20-20 /
   American Softwood Lumber Standard / January 2020"*. **Every citation must read PS 20-20.**
2. **AWG is NBS Handbook 100 §2.1** ("General Use of the American Wire Gage"), not §2.2.

---

## 3. SURVIVORS — the shipping list

Class per the house taxonomy in `kerfcalc.swift/docs/VALIDATION.md`:
**PUBLISHED** (an external published number) · **IDENTITY** (a definition, cross-checked
numerically) · **INVARIANT** (bounds, round-trips, cancellation).

### 3.1 PUBLISHED — carry an external worked example

| # | Function | Kit | Authority (doc · section · URI) | Worked example, verified |
|---|---|---|---|---|
| **10** | **Round-half-to-even at the display precision** | `DimensionKit` | NIST SP 811 §B.7.1 rule 3, `nvlpubs.nist.gov/nistpubs/Legacy/SP/nistspecialpublication811e2008.pdf` — *"the digit preceding the 5 is unchanged if it is even and increased by 1 if it is odd. (Note that this means that the final digit is always even.)"* | `6.9749515` → 7 digits = **6.974952** (preceding 1 odd → up); `6.9749505` → 7 digits = **6.974950** (preceding 0 even → unchanged) |
| **10** | **Same rule, independently, for lumber** | `DimensionKit` | NIST **PS 20-20** App. B **§B1** — *"if 5 followed by only zeroes, retain the digit in the unit position ... if it is even or increase it one mm if it is odd"* | **The discriminating case:** dressed **7-1/2 in × 25.4 = 190.5 mm exactly**. Half-to-even → 190. Half-away-from-zero → 191. **PS 20-20 Table 3 publishes 190.** |
| **10** | **Significant-figure conversion** | `DimensionKit` | NIST SP 811 §B.7.2 | `36 ft × 0.3048 = 10.9728 m = 11.0 m` |
| **10** | **Exact inch / foot / yard** | `DimensionKit` | Fed. Reg. doc **59-5442**, 24 FR 5348 (NBS, 30 Jun 1959), via NIST *SI Units – Length* — inch *"exactly equivalent to 25.4 mm"* | 1 in ≡ 127/5 mm · 1 ft ≡ 381/1250 m · 1 yd ≡ 1143/1250 m, all exact rationals |
| **10** | **US survey foot, labelled legacy** | `DimensionKit` | **85 FR 62698** (2020-10-05), *"Deprecation of the United States (U.S.) Survey Foot"* | 1200/3937 m; deprecated from 2023-01-01. Default international foot. |
| **6** | **Cubic yards** | `VolumeKit` | NIST SP 811 §B.8 | yd³ → m³ = **7.645549E−01**; independently 0.9144³ = 0.764554858, residual **4.2e−08** |
| **7** | **Board feet** | `LumberKit` | PS 20-20 **§2.2 Board measure** — *"multiplying the nominal thickness in inches ... by the nominal width in feet by the length in feet"* | 2×4×8 ft = **16/3 BF** exactly (5⅓); 2×10×16 ft = 80/3; 1×12×10 ft = 10 |
| **7** | **Nominal vs dressed lumber** | `LumberKit` | PS 20-20 **Table 3** ("boards, dimension, and timbers") | **2×4 dry = 1-1/2″ × 3-1/2″.** All **29 dressed sizes** in Table 3 reproduced exactly from 25.4 mm/in + B1 rounding |
| **7** | **The board-foot CAUTION nobody states** | `LumberKit` | PS 20-20 App. B, verbatim — *"CAUTION: Use great care when converting board feet, based on NOMINAL cross-sectional dimensions, to cubic meters of lumber, based on DRESSED cross-sectional dimensions."* | Ship the refusal, not a number. We would be the only app that says this. |
| **NEW** | **AWG wire diameter** (dimension only) | `GaugeKit` | NBS Handbook 100 **§2.1** — *"the diameter of No. 0000 is defined as 0.4600 inch and of No. 36 as 0.0050 inch. There are 38 sizes between"*, ratio `³⁹√92` | HB100 prints **1.1229322**; computed `³⁹√92` = 1.1229322 (7 dp). Both defined anchors reproduce exactly. |

### 3.2 IDENTITY / INVARIANT — provable, no external number needed

These are theorems and definitions. They are not "unsourced"; they are a different, legitimate
class the house already uses. All eight already exist green in `kerfcalc.swift/Kits/`.

| # | Function | Kit | Class | Note |
|---|---|---|---|---|
| **4** | Square-up / diagonal (3-4-5, Pythagoras) | `GeometryKit` | IDENTITY | ports `Area.diagonal`, `.leg` |
| **5** | Roof pitch & rafter (x-in-12 ↔ deg ↔ %) | `PitchKit` | IDENTITY | ports `FramingKit/{Pitch,Rafter}.swift`, which already carry oracle suites |
| **6** | Area & volume geometry | `VolumeKit` | IDENTITY | ports `GeometryKit/{Area,Volume}.swift` |
| **8** | Miter & bevel | `GeometryKit` | IDENTITY | ports `MaterialsKit/CompoundMiter.swift`; `miter angle calculator` is a measured query |
| **9** | Circumference / arc / pipe wrap | `GeometryKit` | IDENTITY | ports `Area.circumference`, `.circularSegment` |
| **NEW** | **Dimensional analysis on × and ÷** | `DimensionKit` | IDENTITY | **linear×linear=area, area×linear=volume, area÷linear=linear.** Closes the 12-year defect. `kerfcalc`'s `TapeCalc` already has `enum Dim { scalar, linear, square, cubic }` — port it. |
| **NEW** | **Mixed-number sign correctness** | `DimensionKit` | INVARIANT | `format(-x)` must parse back to `-x`; kills the *"-7 7/8 should be -7 1/8"* class of bug |
| **10** | Exactness invariants | `DimensionKit` | INVARIANT | `a+b−b == a` exactly; `⅓+⅓+⅓ == 1`; parse→format round-trips; **the tape never renders past a real tape's length** (defect ④) |

---

## 4. ⚠️ THE ONE DECISION FOR YOU — candidates 1, 2, 3

The handoff lists these with authority *"pure arithmetic"*. **Read literally, gate steps 1–3
discard all three: there is no document, no section, and no published worked example.** They are
also the three the handoff calls the strongest differentiators. I did not decide this quietly.

What I found when I went looking for a document:

| # | Function | What exists | What does not |
|---|---|---|---|
| **1** | Equal spacing — divide a span into N, emit **the list of marks** | Nothing published. Demand is real and specific: `baluster spacing calculator` and `even spacing calculator` both return autocomplete hits; 5★ 2024-03-14 asks for auto-halving; 5★ 2014-07-28 wants "the 4 quarters of a drawer face that measures 17 7/16""; 5★ 2016-10-28 *"Works perfectly if you need to break up an elevation into equals"* | No authority, no worked example |
| **2** | On-center layout incl. the odd last bay | **16″ and 24″ o.c. ARE published** — USDA Agriculture Handbook 73, *Wood-Frame House Construction*: *"joists ... spaced 16 inches on center"*, *"The joist spacing should not exceed 16 inches on center ... nor exceed 24 inches on center"*, *"2- by 4-inch studs spaced 16 inches on center"* | **19.2″ o.c. is NOT in AH-73** (it is the 96″ sheet ÷ 5 — identity, not citation). No published worked *layout*. And demand is weak: `stud spacing` and `on center spacing` both returned **zero** autocomplete hints |
| **3** | Cut list with kerf allowance | Nothing published — and the category is **already contested**: `cut list optimizer` autocompletes to *cutflow · glessio · kerf · kerfmate · lumbercut*. Demand is real (the "shop fairy" review) | No authority; not an open field |

> ### ✅ DECIDED 2026-07-29 (owner): ship 1 and 2 as IDENTITY, drop 3.
> `LayoutKit` ships equal spacing and on-center marks, labelled **IDENTITY/INVARIANT — never
> PUBLISHED**. AH-73 is cited for the 16″/24″ values; 19.2″ is labelled the derived 96″÷5
> sheet-module bay. Cut list with kerf is **dropped**. Final list: **16 calculators, 7 Kits.**

**My recommendation (as put to the owner): ship 1 and 2, drop 3.**

- **1 and 2 are the app.** They are honest IDENTITY/INVARIANT functions — the arithmetic is
  provable and testable (marks are monotonic, first = 0, last = span, count = N+1, sum of bays =
  span exactly, every mark lands on the chosen denominator). Labelling them IDENTITY rather than
  PUBLISHED is truthful and costs nothing, because **no competitor emits the marks at all**.
  For #2, cite AH-73 for the 16″/24″ values and label 19.2″ as the derived sheet-module bay.
- **3 should be dropped from v1.** No authority, five named incumbents already on the phrase, and
  a real cut-list optimiser is a bin-packing product, not a tape function. The "shop fairy" need
  is better served by #1 and by dimensional multiply than by a half-hearted optimiser.

**What I will not do:** label an identity as PUBLISHED to get it through the gate, or invent a
"reference" that is our own arithmetic restated. If you want a strict reading of §4, say so and
all three are discarded — the app is then the precision engine plus the ported eight, which is
still a better product than the incumbent.

---

## 5. DISCARDS — with reasons, so they stay shut

| Discarded | Reason |
|---|---|
| **Log rules** (Doyle · Scribner · International ¼″) | **Passes the gate** — Freese, *A Collection of Log Rules*, USDA FS GTR FPL-1, fetched 200, public domain. **Discarded on §4 condition 2, theme fit:** log scaling is forestry/sawmill work, not someone holding a tape. Buyers here are carpenters, electricians, cabinet makers, goldsmiths. Recorded so this is not re-argued. |
| **On-screen physical ruler** ("hold a real ruler to the phone") | Requested often — and it is the single largest source of the incumbent's 1★ reviews (*"Not calibrated for iPhone 6 Plus"*, *"Ruler incorrect on iPhone X"*, *"this app calls a tape measure's two inches, one inch"*). Correctness depends on physical screen PPI per device and breaks on every unknown future device and on display-zoom modes. **We cannot make an oracle claim about a rendered physical length. Do not ship it.** |
| **Drill sizes** (number/letter) | ANSI/ASME B94.11M copyrighted, purchase-only. *ASTM v. Public.Resource.Org* covered non-commercial dissemination only. Fractional/metric drills are formula-generated and would be fine, but are not worth the confusion. |
| **Pipe schedule dimensions** | ASME B36.10M / B36.19M copyrighted; wall thickness is tabulated, not computed. |
| **Anything electrical beyond dimension lookup** | Ampacity, conductor sizing, voltage drop, box fill — the owner's liability line. AWG *diameter* survives as a dimension (§3.1). |
| **Generic unit conversion, currency, clothing sizes** | `docs/unit_converter_2026-07-29.md` §6–7. Apple ships 121 units offline and free; free incumbents hold 190k/128k/81k ratings. |
| **Metric ↔ imperial as a headline** | Supporting detail only. Mixed-unit entry within one calculation stays (cabinet-maker and 2017-10-05 reviews ask for it). |

### Apple build-gate #6 verdicts (`autoaso.md` §6.4)

| Capability | Verdict |
|---|---|
| Feet-inch-**fraction** arithmetic, compound entry, fraction output | **NOT SERVED.** Apple's Convert mode is two fields/one unit each and structurally cannot accept "3 ft 4 in"; compound output is one level deep across 7 units; fractions exist nowhere (`unit_converter_2026-07-29.md` §1). |
| Layout marks, board feet, nominal-vs-dressed, pitch, AWG | **NOT SERVED.** Apple's recognizer vocabulary has zero hits for gauge/board/lumber/drill. |
| Area & volume arithmetic | **PARTIALLY SERVED** — Calculator converts area units but cannot multiply two dimensioned lengths. Ship the layer above. |
| AR distance measuring | **THIN LAYER — deliberately out of scope.** Apple's Measure app owns it. Storypole never measures; it does math on a measurement you already took. This must be explicit in the store copy, because ~15 of the incumbent's 1★ reviews are buyers who expected an AR tape. |

---

## 6. ⚠️ Market risk that changed during this phase

The handoff frames the target as a lone $3.99 incumbent on life support. Measured today, the
**target search terms are led by free apps with large rating bases**:

| App | Price | Ratings | ★ | Updated |
|---|---|---|---|---|
| Construction Master Pro Calc (Calculated Industries) | Free | **39,096** | 4.84 | 2026-06-25 |
| Construction Master 5 Calc (Calculated Industries) | Free | 12,971 | 4.84 | 2026-01-31 |
| Feet & Inches Tape Calculator (Tue Nguyen Minh) | Free | 9,264 | 4.37 | 2025-11-26 |
| Feet and Inches Calculator (Evan Winograd) | Free | 401 | 4.59 | 2026-04-07 |
| *Tape Measure Calculator Pro (the target)* | $3.99 | 2,193 | 4.85 | 2025-10-07 |

`feet inch calculator` autocompletes to **eight** competitor app names (`tape mate`, `unit zoom`,
`truss`, `smart`, `one16`, `convert`, `calcrete`, `feench`). The incumbent did **not** appear in
the top 5 for `tape measure calculator`.

Two honest caveats: the iTunes search index is a proxy for, not identical to, in-app App Store
search (`autoaso.md` §6.5), and `formattedPrice: Free` for the Calculated Industries apps is what
the API returned — CI historically sold these paid, so these are plausibly free-with-IAP shells.
**Neither caveat removes the point:** the trade's dominant brand is on this phrase, free,
39k ratings, updated last month. That is a materially harder field than §0 of the handoff
describes, and it should be weighed before Phase C.

---

## 7. Proposed name / subtitle / keyword block

Built only from phrases that **returned autocomplete hits** in this run.

| Field | Value | chars | Atoms |
|---|---|---|---|
| Name | `Storypole: Inch Calculator` | 26 | storypole · inch · calculator |
| Subtitle | `Feet & Fraction Tape Measure` | 28 | feet · fraction · tape · measure |
| Keywords | `board,foot,lumber,miter,spacing,layout,carpentry,woodworking,construction,math,cut,list,rafter` | 94 | no repeats of any name/subtitle atom |

**Head-noun check passes** — `calculator` is spelled in full in the Name. This is precisely the
`autoaso.md` §6.5 abbreviation trap that cost Kerf Calc its indexing.

Measured phrases this pool matches: `feet and inches calculator` · `best feet and inches calculator
apps` · `apps for feet and inches calculations` · `calculator for feet and inches` · `feet inch
calculator` · `inch fraction calculator` · `fraction calculator construction` · `fraction
calculator: feet inch` · `tape measure calculator` · `tape measure math` · `board foot calculator` ·
`miter angle calculator` · `baluster spacing calculator` · `even spacing calculator` ·
`construction calculator` · `carpentry calculator` · `woodworking calculator`.

---

## 8. Port map — kerfcalc → storypole

Per your decision: **port + harden, re-gate independently.**

| Storypole Kit | Ported from | Hardening required |
|---|---|---|
| `DimensionKit` | `kerfcalc.swift/Kits/Dimension/DimensionKit/{Rational,FeetInch,Units,LengthEntry,TapeCalc}.swift` | `RoundingRule` (§9); `Int64` overflow guards; negative mixed-number formatting; tape-length cap |
| `VolumeKit` | `GeometryKit/{Area,Volume,Concrete}.swift` | re-cite yd³ to SP 811 §B.8 |
| `PitchKit` | `FramingKit/{Pitch,Rafter}.swift` | as-is; suites already green |
| `GeometryKit` | `MaterialsKit/CompoundMiter.swift` + `Area.{diagonal,leg,circumference,circularSegment}` | as-is |
| `LumberKit` | `MaterialsKit.Estimate.boardFeet` | **new**: PS 20-20 Table 3 dressed-size table + the CAUTION |
| `LayoutKit` | **new code** | equal spacing + on-center marks |
| `GaugeKit` | **new code** | AWG diameter, HB100 §2.1 |

**Nothing is copied without re-gating.** Every ported function gets its own `Oracles.swift` entry
with the URI, or is explicitly labelled IDENTITY/INVARIANT.

---

## 9. The rounding conflict, resolved

Your decision was **both rules, explicit**. Phase B evidence supports it and sharpens the default:

- `kerfcalc`'s shipped `Rational.rounded(toDenominator:)` is **half-away-from-zero**, documented in
  `kerfcalc.swift/docs/VALIDATION.md` as *"the symmetric carpentry convention"*.
- NIST SP 811 §B.7.1 and PS 20-20 §B1 **both** specify **half-to-even**, and PS 20-20 Table 3
  contains a published case where the two rules disagree (190.5 mm → **190**, not 191).

So: `RoundingRule.halfToEven` is the default and is the one carrying a published oracle;
`.halfAwayFromZero` ships as the labelled trade convention. Every call site names its rule.

> **Honest limit on the citation, which must not be overstated.** SP 811 §B.7.1 rounds *decimal
> digits*; PS 20-20 §B1 rounds *millimetres*. **Neither publishes a rule for rounding to a binary
> fraction denominator (1/16, 1/32, 1/64).** What is cited is the **tie-breaking rule**; applying
> it at a fraction denominator is our extension by analogy. The corpus will say so, and no test
> will claim NIST publishes a worked 1/16 example. It does not.

---

## 10. Verification performed

- **Every URI in §2 was fetched**, status logged, and the claimed section read in the extracted
  text. The two that failed (`PS 20-25` 404, `fpl.fs.usda.gov` 403) are recorded as such and
  routed to working sources rather than cited unread.
- **Every worked example was reproduced independently** in CPython `fractions.Fraction` /
  `decimal` — a second implementation sharing no code with any Swift — in
  `<scratchpad>/verify_oracles.py`. **All pass**, including all 29 PS 20-20 Table 3 dressed sizes
  and both SP 811 tie cases. The one initial failure was my own row-pairing error (3/8″ is a
  nominal, not a dressed, thickness), corrected and re-run.
- **No number in this report was invented.** Where an authority does not exist, §4 and §5 say so.
- **Apple throttle honoured** — ≥3.5 s between requests; every response cached to disk as the
  receipt.

---

## 11. Carried forward into Phase C/F

- **watchOS App Group procedure** (owner-supplied README, 2026-07-29): bundle IDs and the
  `APP_GROUPS` capability can be created via the ASC API, but **the group identifier itself cannot
  — Xcode creates it, and only when it falls back to the signed-in Apple ID.** Building with
  `-authenticationKeyPath/-authenticationKeyID/-authenticationKeyIssuerID` makes Xcode authenticate
  as the API key, which has no Certificates/Identifiers/Profiles access, and fails with the
  misleading *"Provisioning profile doesn't support the group.… App Group."* **Drop the auth flags.**
  Storypole needs this **only if it ships a complication**; a plain watch app does not.
  Also carried: `WKCompanionAppBundleIdentifier` + `WKRunsIndependentlyOfCompanionApp` (never
  `WKWatchOnly` alongside them); extension version must match host via `$(MARKETING_VERSION)`;
  app groups do not cross the pairing (that needs `WatchConnectivity`); complication `kind` strings
  are cached, so bump the identifier to invalidate.
- `PRODUCT_NAME: Storypole` on **every** target (5.2.5 / "Swift" — three prior rejections).
- App directory is **`storypole/`** per your decision, not the handoff's `storypole.swift/`.

---

## 12. Recommended shipping list

**11 functions across 7 Kits**, if you accept §4:

`DimensionKit` (rounding · exact units · survey foot · dimensional analysis · sign invariants) ·
`LumberKit` (board feet · nominal-vs-dressed · the CAUTION) · `VolumeKit` (area · volume ·
cubic yards) · `PitchKit` (pitch · rafter) · `GeometryKit` (diagonal · miter · circumference) ·
`LayoutKit` (equal spacing · on-center) · `GaugeKit` (AWG).

**Dropped from the original ten:** #3 cut list with kerf (§4).
**Added:** dimensional analysis on × and ÷ · AWG · sign invariants.

**✅ Approved by the owner 2026-07-29. Phase C is underway.** Build plan, including the watch
curation and the 3-tab app shape, is in the session plan file; the Phase E design brief will
restate the final list as the contract for whoever builds the UI.
