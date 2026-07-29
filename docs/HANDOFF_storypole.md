# HANDOFF — Storypole

**A feet-inch-fraction tape-measure calculator for iOS, macOS and watchOS.**

| | |
|---|---|
| **App Store name** | `Storypole: Inch Calculator` (26 chars) |
| **Subtitle** | `Feet & Fraction Tape Measure` (28 chars) |
| **Directory** | `storypole.swift/` |
| **Bundle identifier** | `oleksandr.aisixteen.storypole` |
| **Watch bundle** | `oleksandr.aisixteen.storypole.watchkitapp` |
| **`PRODUCT_NAME`** | `Storypole` — must be set explicitly, see §6 |
| **Price** | paid upfront, buy-once. No ads, no subscription, no IAP, no StoreKit |

*A story pole is the carpenter's physical layout stick — one board marked with every measurement for
a job. That is exactly what this app is: marks on a length.*

**Name chosen by the owner 2026-07-29.** Trademark and App Store collision checks are still
outstanding and are the owner's to run before anything is registered.

**Status: draft plan. Nothing has been built. No directory exists yet.**
You are picking this up cold. Read this whole file before doing anything.

> Evidence base, all measured 2026-07-29 from sanctioned endpoints (iTunes Search API + Customer
> Reviews RSS, US storefront):
> `docs/upgrade_target_2026-07-29.md` · `docs/unit_converter_2026-07-29.md` ·
> `docs/kerflike_2026-07-29.md` · `docs/own_analytics_2026-07-29.md`.
> Read `marketing/autoaso.md` §6.4 (Apple build-gate), §6.5 (hard-won ASO rules) before touching
> any store metadata.

---

## 0. Why this app exists

We measured our own App Store analytics: **Kerf Calc took 4 US impressions in 12 days and made
zero sales.** The portfolio's binding constraint is *impressions*, not product quality — the funnel
below the impression converts fine (Ephemeris: 4.9 % impression→page, 11.8 % page→download, one real
$7.21 sale to a stranger). See `docs/own_analytics_2026-07-29.md`.

This app was chosen because it is the **only** candidate found in a month of sweeps that is
simultaneously:

- **proven selling** — a paid incumbent at $3.99 with 2,193 ratings and **19 purchases-worth of
  reviews in the last 12 months**
- **genuinely wounded** — four named, quotable defects, unfixed
- **unclaimed by Apple** — feet-inch-**fractions** exist nowhere in Apple's stack
- **on searched terms** — the best autocomplete demand signal measured all month

**Do not widen this into a generic unit converter.** Apple ships 121 units offline and free, and the
free incumbents own 190k/128k/81k ratings. That fight is lost before it starts
(`docs/unit_converter_2026-07-29.md` §6–7).

---

## 1. What the incumbent does

**Tape Measure Calculator Pro** ("Tapeulator"), Bugfoot Studios LLC, trackId `482504435`.
$3.99 · 2,193 ratings · 4.85★ · Utilities · released **2011-12-02** · v4.9 (2025-10-07) ·
`minimumOsVersion 11.0` · 38 MB.

Its job, in its own words:

> *"Ever need to do math on a measurement? What is **25 3/8" ÷ 3, BUT on a measuring tape?** Skip the
> math, converting to fractions, and go right to the answer on the tape!! **Saves you time and costly
> mistakes on material!**"*

1. Enter measurements the way a tradesman reads them — feet + inches + **fractions**, not decimals.
2. Add / subtract / multiply / divide them, mixing fractions and decimals freely.
3. Results returned in inches, feet **and** centimetres, in both decimal and fraction form.
4. **The answer is drawn as a mark on a picture of a tape measure** — *"No need to guess where to
   place your mark."*

Plus a camera measuring mode and an Apple Watch app.

**Step 4 is the actual product.** Fraction arithmetic is easy; knowing where 8 7/16" falls between
the marks on the tape in your hand is what people get wrong.

**Who buys it** (from reviews): home remodellers (daily), woodworkers, metalworkers, **pipe cutters**,
electricians in the field, a goldsmith, DIYers.

> *"Great tool to use in the field **as an electrician**."* — 5★ 2026-02-11
> *"I use it **in construction and in goldsmithing**"* — 5★ 2026-07-02
> *"For a non-mathematically inclined **amateur woodworker**, this app is a lifesaver."* — 5★ 2026-06-08
> *"**Been using it since 2013** and it hasn't failed me yet."* — 5★ 2026-02-13
> *"This little gem saved me a decent amount of money by making it easy to **double check my work
> before cutting**. Measure twice, cut once!"*

**The job to be done is: prevent an expensive wrong cut.** That is exactly what oracle-first sells.

**It is not abandoned — it is on life support.** v4.9's release notes read *"support for iOS26 and
every new iPhone — more Apple Watch app bug fixes."* The developer ships the minimum to stay
installable. Note what that means: the defects below **survived that update**.

---

## 2. THE MAIN PAIN POINT

Four named defects, each a direct quote. Every one is something we would not ship.

**① The core feature crashes on iPad.**
> *"A great tool - But it has problems w/iPad — I can't say enough good things about this. It works
> great on my iPhone but **it crashes every single time I try to use a fraction on my iPad.**"*
> — 2★ 2026-01-10

**② The tape graphic shows a wrong result.**
> *"**Wrong result showing in tape measure graphic** — I just upgraded to iPhone 17 and the results is
> wrong in the tape measure graphic"* — 1★ 2025-09-26

**③ Multiplication is broken or unfindable, and support does not answer.**
> *"Awful app **can't even multiply for square footage**. Developer should be more transparent, **no
> response when contacting** about issue."* — 1★ 2025-11-22

**④ It violates the trade's own convention** — this is the `autoaso.md` §6.4 "precision & convention"
gap stated perfectly:
> *"Needs different output settings — **Normal carpenters do not use decimals, we use fractions.** The
> tape at the end is in inches for some crazy reason. **No tape goes into the 200s** that I've ever
> seen."* — 3★ 2025-10-14

**If you build nothing else correctly, build ④ and ①.** Fractions-first output on a tape that behaves
like a real tape, working identically on iPhone, iPad and Mac, is the entire wedge.

---

## 3. The ten candidate functions

All ten sit on the same theme — *math on a measurement*. Each is asked for in evidence, has a
plausible citable authority, and is not something Apple does. Every survivor becomes a Kit.

> **These are CANDIDATES, not a settled list, and they are a FLOOR not a ceiling.** The authorities
> below were identified from desk research and have **not all been read end to end**. Each one still
> has to pass the oracle gate in §4 — you must open the document, confirm the section says what is
> claimed, and extract a worked example. **Anything that fails is discarded, not carried forward.**
> Expect one or two of these ten to die on contact; that is the gate working, not a problem.
>
> **And if you find more functions that pass the gate, add them — no permission needed.** See
> §4 "Passing the gate is standing permission to add". A well-oracled twelve beats a speculative ten.

| # | Function | Kit | Authority |
|---|---|---|---|
| 1 | **Equal-spacing layout** — divide a span into N equal parts, emit the list of marks | `LayoutKit` | pure arithmetic |
| 2 | **On-center layout** — 16"/19.2"/24" o.c. across a real span, including the odd last bay | `LayoutKit` | pure arithmetic |
| 3 | **Cut list with kerf allowance** — pieces from stock, accounting for blade width | `CutListKit` | pure arithmetic |
| 4 | **Square-up / diagonal** — 3-4-5 and Pythagorean diagonal from two feet-inch sides | `GeometryKit` | Pythagoras |
| 5 | **Roof pitch & rafter** — rise/run/hypotenuse; pitch as x-in-12 ↔ degrees ↔ percent | `PitchKit` | trigonometry |
| 6 | **Area, volume, cubic yards** — square footage; concrete yd³ | `VolumeKit` | NIST SP 811 §B.8 (yd³→m³ = 7.645549E−01) |
| 7 | **Board feet + nominal vs dressed lumber** | `LumberKit` | USDA FS GTR FPL; NIST PS 20-25 |
| 8 | **Miter & bevel angles** for a measured corner | `GeometryKit` | trigonometry |
| 9 | **Circumference / pipe wrap / arc length** | `GeometryKit` | geometry |
| 10 | **Precision engine** — fraction denominator, round-half-to-even, tape realism | `DimensionKit` | NIST SP 811 §B.7.1 |

### Notes on the load-bearing ones

**1 & 2 — layout marks.** *"I need 7 balusters evenly spaced in 62 1/4"."* Every calculator returns a
spacing number; none return **the list of marks to make on the tape**. This app already draws a tape.
Nobody has this. It is the strongest single differentiator on the list.

**3 — cut list with kerf.** Highest-value function for anyone cutting material, and the literal reason
"measure twice, cut once" exists in the incumbent's own marketing.

**5 — roof pitch.** This closes a competitor's wound verbatim — RedX Roof, 1★: *"Following the
measurements for **hip and Jack rafters to the 16th** came up with the **wrong measurements and a lot
of wasted material**."* Give pitch three ways; roofers, framers and inspectors each use a different one.

**6 — area/volume.** Directly closes defect ③.

**7 — the trap nobody states.** NIST PS 20-25 App. B carries an explicit CAUTION that board feet are
based on **nominal** dimensions while cubic metres are based on **dressed** ones, so converting
between them is not a legitimate unit conversion. Ship the dressed table (2×4 = 1.5" × 3.5") **and
say why**. We would be the only app that does.

**10 — makes the other nine correct.** Output in fractions to a chosen denominator (1/16, 1/32, 1/64),
decimals only on request, round-half-to-even per NIST, and **never draw a tape longer than a real
tape**. This is defect ④.

### Deliberately excluded — do not add these

- **Drill sizes (number/letter)** and **pipe schedule dimensions** — both licensing dealbreakers.
  ANSI/ASME B94.11M and ASME B36.10M/B36.19M are copyrighted and purchase-only; *ASTM v.
  Public.Resource.Org* covered **non-commercial** dissemination only and does not clear a paid app.
  Fractional and metric drills are formula-generated and fine.
- **Anything electrical beyond dimension lookup.** AWG *diameter* from the NBS Handbook 100 formula
  (`d(n) = 0.005 × 92^((36−n)/39)` inch, public domain) is a measurement and is acceptable. **Ampacity,
  conductor sizing, voltage drop and box fill are OUT** — that is the liability line the owner drew.
- **Metric ↔ imperial as a headline.** Apple does 121 units offline and free. Supporting detail only.
- **Currency, clothing sizes, generic unit conversion.** Different app, lost fight.

---

## 4. Find more functions — your task, not a closed list

The ten above are a floor, not a ceiling. **Before you write code, go find more**, using the method
that produced them:

1. **Read the incumbents' reviews yourself.** Sanctioned endpoint only:
   `https://itunes.apple.com/us/rss/customerreviews/id={trackId}/sortBy=mostRecent/json`,
   **≥3.5 s throttle**, cache to disk. Start with `482504435` (Tape Measure Calculator Pro), then
   the neighbours in `docs/kerflike_2026-07-29.md` — RedX Roof, Construction Cost Estimator,
   Planimeter, Ductulator, Calculator!, Units Plus.
2. **Mine Apple autocomplete for real queries** —
   `https://search.itunes.apple.com/WebObjects/MZSearchHints.woa/wa/hints?clientApplication=Software&term=X`
   with header `X-Apple-Store-Front: 143441-1,29` (**without it the endpoint returns an empty array**).
   Include shopping-intent forms: `best X apps`, `apps for X`. 228 phrases are already collected —
   ask the owner for `k5_phrases.json` if you want the existing set.
3. **Run every candidate through `autoaso.md` §6.4 BUILD-GATE #6 by eye, not by regex.** A keyword
   match once classified MyScript Calculator as NOT SERVED when Apple's Math Notes does exactly its
   job. Verdicts: NOT SERVED / PARTIALLY SERVED / THIN LAYER. Only THIN LAYER is a stop.
4. **Kill anything whose only authority is a copyrighted standard.** The rule is not merely "is
   reproducing facts legal" — it is "can we *cite* it". If the normative source is ASTM/ASME/ANSI/ISO
   and purchase-only, we cannot make the oracle claim, so we do not ship the feature.

### THE ORACLE GATE — the rule that governs this whole phase

**A function ships only if it has an oracle. Research finds candidate functions; the oracle gate
decides which survive. Everything unoracled is DISCARDED, not deferred.**

For every candidate function, before any code:

| Step | Question | Fail → |
|---|---|---|
| 1 | Is there a **named, published, freely citable** authority for this computation? | **DISCARD** |
| 2 | Can I quote it — document, section number, and a URI? | **DISCARD** |
| 3 | Can I extract at least one **worked example with a known answer** from it? | **DISCARD** |
| 4 | Is it public domain / uncopyrightable (US Gov, statute, edict of government)? | **DISCARD** |

"Discard" means it does not enter the plan at all. **Do not** carry an unoracled function forward as
a `TODO(oracle):` hoping to find a source later — `TODO(oracle):` exists only for a *gap inside an
already-oracled Kit*, never as a licence to ship an unsourced function.

Two failure modes that must never happen:

- **Inventing a number** to make a test pass. Not once, not "temporarily".
- **Citing a source you have not actually read.** If the URL 403s or the document is paywalled, the
  authority does not exist for our purposes. Record it as unverified and discard the function.

Record the discards too, with the reason. A written "we cannot source drill sizes, therefore no drill
sizes" is a permanent answer that stops the question being re-opened every few months.

### ✅ Passing the gate is standing permission to add

**If you find a function that passes all four steps, you are free to add it. You do not need to ask.**
The ten in §3 are a floor, not a quota and not a ceiling — a genuinely oracled eleventh, fifteenth or
twentieth function is a better app, and finding them is the point of this phase.

The only conditions:

1. **It passes the gate in full** — named freely-citable authority, quotable section, worked example,
   public domain. No exceptions, no "close enough".
2. **It fits the theme** — *math on a measurement*, for someone holding a tape. If it needs a
   sentence of justification to connect it to that job, it belongs in a different app. This is how
   the project stays a tape-measure calculator rather than drifting into a generic unit converter,
   which is a fight we have already measured and lost (`docs/unit_converter_2026-07-29.md` §6–7).
3. **It is not on the excluded list** below. Those are hard stops on licensing and liability, not
   defaults to be argued past — a clean-looking source does not reopen them.

Additions get the same treatment as the original ten: their own Kit, their own `Oracles.swift`
corpus, their own Style-A suites. List them in your Phase B report marked **NEW** with the authority
attached, so the design brief in §9 carries the true final list rather than the speculative one.

The same freedom runs in reverse: **if one of the ten fails the gate, kill it.** Nothing in §3 is
protected by having been written down first.

Report what you find with the evidence attached — quote, date, star rating, app — plus the surviving
oracle for each function, before building anything.

---

## 5. Oracles and units — the non-negotiable core

Follow the house pattern exactly. Reference implementations: `overtonelab.swift/Kits/**`,
`kerfcalc.swift/Kits/**`.

**Structure.** One SwiftPM package per Kit, at `Kits/<Group>/<Name>Kit/`, with
`Sources/<Name>Kit/` and `Tests/<Name>KitTests/`. Kits are pure computation — **no SwiftUI, no
Foundation UI, no app imports**. The app depends on Kits; Kits never depend on the app.

**Every displayed number must trace to a cited published authority and be asserted by a test.**

- Each Kit carries an `Oracles.swift` corpus: cases with a `source` string **and a URI**, plus
  `Oracles.require(id)` so a missing oracle fails loud rather than silently skipping.
- Style-A suite headers. Label each oracle `PUBLISHED` / `IDENTITY` / `INVARIANT`.
- Tests must **FAIL LOUD** when a fixture is absent — never skip green. See
  `overtonelab.swift/Kits/Tuning/CommaKit/Tests/CommaKitTests/ScalaOracleTests.swift` for the
  fixture-present-or-fail pattern, and `CommaKit-tools/fetch-oracles.sh` + `oracles.manifest` for
  downloaded fixtures (fixtures are gitignored).
- Leave `TODO(oracle):` where an authority is still missing. **Do not invent a number to make a test
  pass, ever.**

**Clean authorities for this app** (all US Government / public domain — verified in
`docs/unit_converter_2026-07-29.md` §4):

| Need | Authority |
|---|---|
| inch = 25.4 mm, lb = 0.45359237 kg, yard = 0.9144 m — all **exact** | Federal Register doc 59-5442, 24 FR 5348 (NBS 1959); NIST "SI Units – Length" |
| Exact-vs-rounded factor labelling | NIST SP 811 §B.2 (*"A factor in boldface is exact…"*). Cite NASA SP-7012 if reproducing tables wholesale — SP 811 App. B descends from IEEE-copyrighted ANSI/IEEE 268-1982 |
| Significant-figure rule | NIST SP 811 §B.7.2, worked example *"36 ft × 0.3048 = 10.9728 m = 11.0 m"* |
| **Round-half-to-even** | NIST SP 811 §B.7.1, verbatim. Do **not** use ASTM E29 (copyrighted) |
| Feet-inch-fraction rounding, lumber nominal-vs-dressed, the board-foot CAUTION | NIST PS 20-25 App. B §B1 |
| Board feet & log rules | Freese, *A Collection of Log Rules*, USDA FS GTR FPL |
| Cubic yards | NIST SP 811 §B.8 |
| US survey foot as explicit legacy mode | 85 FR 62698 — *"Beginning on January 1, 2023, the U.S. survey foot should not be used"* |
| AWG diameter (dimension only) | NBS Handbook 100 §2.2 |

**Units and the precision engine (`DimensionKit`) — get this right first.**

- Internal representation must be **exact rational**, not `Double`. Feet-inch-fractions are rationals;
  binary floating point will produce 8 7/16" ≠ 8 7/16". Use an integer numerator/denominator type
  (e.g. sixty-fourths, or a reduced `Rational`) and only convert to `Double` for rendering.
- Round-half-to-even at the display denominator, never at intermediate steps.
- Default output **fractions**, denominator user-selectable (1/2 … 1/64). Decimal only on request.
- Support the **US survey foot** as an explicitly labelled legacy mode; default to the international
  foot.
- Testable invariants: parse→format round-trips; `a+b−b == a` exactly; every published NIST example
  reproduces; the tape never renders beyond a real tape's length.

---

## 6. App structure, design and platforms

**Targets: iOS + macOS from day one, plus watchOS.** The incumbent's defining failure is that it
crashes on iPad. Parity across phone, tablet and Mac is the wedge, not a nice-to-have.

**Build config** — copy the `project.yml` pattern from `overtonelab.swift`:

- `options.bundleIdPrefix: oleksandr.aisixteen`, `DEVELOPMENT_TEAM: LSKNNBG94G`,
  deployment targets iOS/macOS `26.0`.
- **`PRODUCT_NAME: Storypole` must be set explicitly on every target.** With `GENERATE_INFOPLIST_FILE`, the
  generator always sets `CFBundleName` (the macOS menu-bar title) from `PRODUCT_NAME` and silently
  ignores `INFOPLIST_KEY_CFBundleName`. Without it the binary ships as `storypole.swift` and **App Review
  rejects under 5.2.5** (Apple trademark "Swift"). This has bitten this repo three times.
- Also set `INFOPLIST_KEY_CFBundleDisplayName`.

**watchOS — mirror `overtonelab.swift` exactly:**

```yaml
  StorypoleWatch:
    type: application
    platform: watchOS          # NOT supportedDestinations — XcodeGen rejects watchOS there
    deploymentTarget: "26.0"
    sources:
      - path: StorypoleWatch
      - path: DesignShared     # same tokens AND the same Localizable.xcstrings as phone
      - path: storypole.icon
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: oleksandr.aisixteen.storypole.watchkitapp
        PRODUCT_NAME: Storypole
        INFOPLIST_KEY_CFBundleDisplayName: Storypole
        INFOPLIST_KEY_WKApplication: YES
        INFOPLIST_KEY_WKCompanionAppBundleIdentifier: oleksandr.aisixteen.storypole
        INFOPLIST_KEY_ITSAppUsesNonExemptEncryption: NO
```

and on the iOS app target, `dependencies: - target: StorypoleWatch / embed: true / platformFilter: iOS`.

Watch file layout follows `overtonelab.swift/OverToneLabWatch/` — so
`StorypoleWatch/StorypoleWatchApp.swift`, `WatchRootView.swift`, `WatchToolList.swift`,
`WatchComponents.swift`.
**If a widget or complication is added, adopt `.containerBackground(.clear, for: .widget)`** — without
it the widget looks fine in Simulator and renders grey on a real device.

**A watch tape calculator is genuinely useful** — hands full, tape in one hand, phone in your pocket.
Prioritise: read a running total, add a measurement, see the fraction. Not layout planning.

**Design.** Build with native components and no invented design system until design files arrive.
`DesignShared/` (tokens, formatters, `LanguageStore`, `ToolCatalog`, the string catalog) is shared by
phone, Mac and watch — put it in place from the start so the design drop has somewhere to land.
Dynamic Type throughout, **no pinned point sizes**. `accessibilityIdentifier` on every input and
result. **Expect to receive design files later and be ready to absorb them without restructuring.**

**Do not** add StoreKit, ads, subscriptions or IAP. Paid-upfront, buy-once, offline. No account, no
network, no analytics SDK.

---

## 7. Naming — DECIDED: Storypole

**The name is settled. Do not re-open it.** Use `Storypole` everywhere; the alternatives at the end of
this section are recorded only in case the owner's trademark check forces a change.

| Field | Value | chars |
|---|---|---|
| **Name** | `Storypole: Inch Calculator` | 26 |
| **Subtitle** | `Feet & Fraction Tape Measure` | 28 |
| **Directory** | `storypole.swift/` | |
| **Bundle ID** | `oleksandr.aisixteen.storypole` | |
| **Watch target** | `StorypoleWatch` → `oleksandr.aisixteen.storypole.watchkitapp` | |
| **`PRODUCT_NAME`** | `Storypole` (all targets) | |

Constraints that produced it: App Store name is **indexed** and capped at 30 characters. It must carry
a real query term — and note that **"Calc" does not match "calculator"** in App Store search
(`autoaso.md` §6.5), so the word is spelled out. Must not contain "Swift". Avoids "Tapeulator" (the
incumbent's) and every trademark: Stanley · DeWalt · Milwaukee · Craftsman · Construction Master ·
Calculated Industries.

The measured high-demand queries this name should aim at:
`feet and inches calculator` · `tape measure calculator` · `inch fraction calculator` ·
`fraction calculator construction` · `tape measure math`

### ⚠️ "Tape calculator" is ambiguous — never use it bare

**"Tape calculator" without the word "measure" means an adding machine** — the paper-roll printout of
a running list of calculations. That is the established meaning in this category, evidenced in our own
sweeps: *Digits Tape Calculator* ($1.99, 1,122 r) and *Adding Tape Printing Calculator with virtual
tape* ($2.99) are both adding machines, and our own `par/plan_tape.md` uses "tape" in that sense.

Autocomplete confirms the measurement sense always carries **measure**:
`tape measure -> tape measure calculator · tape measure math · tape measure ruler`.

So a name reading `<Brand>: Tape Calculator` would compete for adding-machine queries we do not want
while missing the measurement queries we do. **Use "Tape Measure", "Feet Inch" or "Inch Fraction".**

### The name/subtitle pairing

Indexed fields **combine within a locale** (`autoaso.md` §6.5) — name + subtitle + keyword field pool
together, so no word needs repeating. Split the query terms across the two 30-char fields:

| Field | Content | chars | Atoms contributed |
|---|---|---|---|
| Name | `Storypole: Inch Calculator` | 26 | storypole · inch · calculator |
| Subtitle | `Feet & Fraction Tape Measure` | 28 | feet · fraction · tape · measure |

Combined index: `inch` `calculator` `feet` `fraction` `tape` `measure` — which matches *tape measure
calculator*, *feet inch calculator*, *inch fraction calculator*, *fraction calculator* and *tape
measure math*, with no wasted characters and no adding-machine ambiguity.

### Fallbacks — only if the trademark check kills Storypole

| # | App Store name | chars | Directory | Bundle identifier |
|---|---|---|---|---|
| 2 | `Snapline: Feet Inch Calculator` | 30 | `snapline.swift` | `oleksandr.aisixteen.snapline` |
| 3 | `Sixteenth: Inch Calculator` | 26 | `sixteenth.swift` | `oleksandr.aisixteen.sixteenth` |
| 4 | `Markline: Inch Calculator` | 25 | `markline.swift` | `oleksandr.aisixteen.markline` |
| 5 | `Scribe: Feet Inch Calculator` | 28 | `scribe.swift` | `oleksandr.aisixteen.scribe` |
| 6 | `Trammel: Feet Inch Calculator` | 29 | `trammel.swift` | `oleksandr.aisixteen.trammel` |
| 7 | `Foldrule: Inch Calculator` | 25 | `foldrule.swift` | `oleksandr.aisixteen.foldrule` |
| 8 | `Tickmark: Inch Calculator` | 25 | `tickmark.swift` | `oleksandr.aisixteen.tickmark` |
| 9 | `Plumbline: Inch Calculator` | 26 | `plumbline.swift` | `oleksandr.aisixteen.plumbline` |
| 10 | `Batten: Feet Inch Calculator` | 28 | `batten.swift` | `oleksandr.aisixteen.batten` |

Pattern in every case: watch target `<Brand>Watch`, bundle
`oleksandr.aisixteen.<brand>.watchkitapp`.

---

## 8. Order of work — a strict pipeline, in this order

**Phase A — RESEARCH.** Find candidate calculator functions by the §4 method: incumbent reviews,
autocomplete, the neighbouring apps in `docs/kerflike_2026-07-29.md`. Cast wide; the ten in §3 are a
floor, not a ceiling. Output: a candidate list with the demand evidence attached (quote, date, stars,
app).

**Phase B — ORACLE GATE.** Run every candidate through the four-step gate in §4 — **including the ten
in §3, which are not exempt.** Keep only functions with a named, freely citable authority and at least
one worked example. Discard the rest outright and write down why. **Anything new that passes is yours
to add without asking** (§4). Output: a surviving function list — each with its authority (document ·
section · URI) and worked example, additions marked **NEW** — plus a discard list with reasons. The
surviving list may be shorter or longer than ten; both are correct outcomes.

**Phase C — UNITS.** Build `DimensionKit` first: exact-rational feet-inch-fractions, NIST
round-half-to-even, the fraction/denominator engine, tape realism, US survey foot as a labelled
legacy mode. **Nothing else starts until this is green.** Every other Kit depends on the unit type
being exact, so getting this wrong poisons everything downstream.

**Phase D — KITS.** Implement the surviving functions, one Kit each, every one with its own
`Oracles.swift` corpus and Style-A suites, all green.

**Phase E — DESIGN HANDOFF MD.** *(see §9)* Write the design brief with the **final, known list of
oracles** — not the speculative one in §3. Only now, because only now is the list actually true.

**Phase F — UI.** Minimal native UI against the green Kits: the tape, the four operations,
fractions-first output. iPhone + iPad + Mac, identical behaviour. Prove the iPad case the incumbent
fails. Then the watchOS target.

Do not run these out of order. In particular **do not design UI around a function that has not passed
the oracle gate** — that is how an unsourced feature gets built because a screen already had a button
for it.

---

## 9. Phase E deliverable — `docs/DESIGN_BRIEF_storypole.md`

Written **after** Phase D, for the Claude doing design. It must contain:

1. **The final oracle list** — every shipping function, with: Kit name, what it computes, the
   authority (document · section · URI), the worked example that proves it, and the unit types in and
   out. This is the contract; design must not invent a function that is not on it.
2. **The discard list** — what was researched and rejected, with reasons. Prevents design proposing
   drill sizes or pipe schedules back into scope.
3. **Units and formatting rules** — fractions-first, selectable denominator, round-half-to-even,
   never render a tape past a real tape's length. These are correctness constraints, not preferences,
   and design cannot override them.
4. **Platform matrix** — what appears on iPhone, iPad, Mac and Watch, and what is deliberately
   omitted from the wrist.
5. **Accessibility floor** — Dynamic Type throughout with no pinned point sizes,
   `accessibilityIdentifier` on every input and result.
6. **What design is free to decide** and what it is not. Layout, hierarchy, colour, motion: free.
   Number formatting, rounding, unit display, the oracle list: fixed.

State plainly in that file that design files are expected to land afterwards and the app must absorb
them without restructuring — which is why `DesignShared/` exists from Phase C.

---

## 10. Boundaries

Report back at the end of Phase B (surviving + discarded functions) and again at the end of Phase D
(which Kits are green, which carry `TODO(oracle):`), plus a proposed name/subtitle/keyword block built
from measured autocomplete phrases.

Create `storypole.swift/` when Phase C begins — **never** fork anything from `marketing/`; every app
calls those scripts in place.

**Do not** create an App Store version, submit, set a price, or assign a build to an external
TestFlight group. Those are the owner's decisions — ask first (`CLAUDE.md`, and the store-assets rules
in `marketing/autoaso.md`).
