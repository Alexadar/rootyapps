# Par — financial calculator · plan

> **This is the brief for a fresh Claude Code session.** Self-contained; assume no memory of prior
> chats. Working directory = the `rootyapps` repo root.
> **Status: §4–§8 filled in and human-approved 2026-07-27. Sources captured, pre-checks green.**

**App name: `Par`.** A bond trades *at par* when its price equals face value — insider-true, short,
and honest across every function in the app rather than over-indexing on one.

- **Directory:** `par/` — **no `.swift` anywhere in the name.** A shipped binary or menu-bar entry
  reading `par.swift` is rejected under Guideline 5.2.5. Kit names (`TVMKit`) are unaffected.
- **Bundle id:** `oleksandr.aisixteen.fincalc` — **registered on App Store Connect 2026-07-28 and
  permanent** (UNIVERSAL, named "Par"). It follows the `<prefix>.<slug>` pattern every other app in the
  account uses; bundle ids are invisible to users and cannot be changed without orphaning installs.
  Team `LSKNNBG94G` · iOS/macOS 26
- **Store name (30 max):** `Par: Financial Calculator` (25) — **the head noun is spelled out in full,
  deliberately.** "Calc" does not match "calculator": Kerf Calc shipped with `Calc` in its name and was
  absent from the top ~180 results for all 8 of its target terms because no indexed field contained the
  word buyers actually type. Do not repeat that.
- **Price:** **$9.99** one-time, set on App Store Connect 2026-07-28 (base territory USA,
  proceeds $8.49). No ads, no subscription, no IAP.

---

## 1. The house rules

We renovate abandoned-but-demanded niche apps into **buy-once, offline, no-ads, no-subscription** tools.
The moat is **validated math you can prove** — every displayed number traceable to a cited external
authority, asserted by tests. Trust first, pixels later.

**Read before coding:** `calculators/VALIDATION.md` (governs), `calculators/ORACLE_SCAFFOLD_PROMPT.md`
§3–§6 (exact Kit shape, corpus, integrity guard, `Package.swift` template), and one green exemplar —
`ephemeris.swift/EphemerisKit/` is the closest in spirit.

## 2. Why this app

The two calculators permitted in the CFA exam are standard in banking, mortgage and commercial real
estate. People *must* have this tool. The apps serving them are bad, and buyers pay premium prices anyway
— all figures API-verified 2026-07-27, US storefront:

| App | Price | Ratings | ★ | Last update |
|---|---|---|---|---|
| The incumbent maker's own branded app | $14.99 | 114 | **2.8** | **65.7 months ago** |
| A cloned-hardware app | $16.99 | 350 | **1.6** | current |
| Vicinno Financial Calculator | $5.99 | 1,208 | 4.2 | **75.8 months ago** |
| 10BII Calc HD (Ernest Brock) | $8.99 | 3,726 | 4.9 | 8.2 months |
| MathU RPN | $24.99 | 108 | 5.0 | 2.4 months |
| BA Financial Calculator (free, genuinely good) | Free | 3,297 | 4.8 | 10.5 months |

**They fail at being apps, not at math.** Verbatim from Vicinno's reviews:
_"Calculator opens at about twice the size of my iPad screen making half the buttons inaccessible. No
resize or scroll function available."_ and _"I'd give it 5 if it had a Split View on the iPad. Asked but
never got a response."_ That is the entire opening — and it means **layout and legibility are the
product**, not a polish pass at the end.

Note the one credible free competitor (3,297 r at 4.8★). The pitch is therefore *"the one that works
properly on iPad and shows its work"* — not *"not broken"*.

## 3. ⚠️ LICENSING — the hard constraint. Read twice.

**Never use, anywhere** — app name, subtitle, keyword field, description, screenshots, UI text, or code
identifiers: **HP · 12C · 12c · BA II Plus · BA-II · TI · Texas Instruments · 10bII · 10BII**.
These are live trademarks, and a competitor trademark in App Store metadata is **auto-rejected at review**.

**Never copy trade dress** — a gold-on-brown key layout, another maker's key legends, or any physical
unit's distinctive appearance. **Never** ship a ROM image or a keystroke database extracted from a
physical calculator, and **never** transcribe tables out of a copyrighted textbook.

**Free to use:** every formula here (TVM, NPV, IRR, amortization, bond pricing, depreciation are
uncopyrightable mathematics); **RPN entry** (a 1920s notation, nobody's property); plain descriptive
words — *financial calculator, TVM, amortization, IRR, NPV, bond yield, present value, cash flow*; and
**US-government publications, which are public domain** — which is where almost every oracle below comes
from (Treasury, CFPB, IRS, NIST).

If you are ever unsure whether a term is a mark, don't use it and flag it in your report.

---

## 4. Structure

Ten Kits, chosen to cover the **whole** function surface a financial calculator is bought for — not a
subset. Each is a Foundation-only SPM package; none depends on another.

```
par/
  PLAN.md                        # this file
  DESIGN_BRIEF.md                # written last (§8)
  scratch/                       # sources + python pre-checks (committed, not gitignored)
  Kits/DayCount/DayCountKit/     # date & day-count conventions — everything else dates on this
  Kits/TVM/TVMKit/               # five-register solve: n · i · PV · PMT · FV
  Kits/Amort/AmortKit/           # amortization schedule, balances, interest/principal split
  Kits/CashFlow/CashFlowKit/     # NPV · NFV · IRR · MIRR · payback · discounted payback
  Kits/Bond/BondKit/             # price · accrued · YTM · duration · convexity · bills · TIPS
  Kits/Depreciation/DepKit/      # SL · DB · DB-crossover · SYD · MACRS (GDS half-year & mid-quarter)
  Kits/Rate/RateKit/             # APR (actuarial + US Rule) · APY · nominal↔effective↔continuous
  Kits/Percent/PercentKit/       # %change · markup vs margin · cost-sell-margin · break-even
  Kits/Stat/StatKit/             # 1-var & 2-var stats · regression (lin/ln/exp/pwr) · forecast
  Kits/RealEstate/RealEstateKit/ # NOI · cap rate · DSCR · LTV · max loan · cash-on-cash · GRM
  Chains/ChainTests/             # NOT a Kit: the 90-pair chain matrix and its tests (§7 step 4b)
  Par/                           # the app target (§6)
```

Each Kit: `// swift-tools-version:5.9`, `platforms: [.macOS(.v13), .iOS(.v16)]`, one `.target` + one
`.testTarget`, **no dependencies, no resources, Foundation only**. `public enum <Topic>` static
namespaces, unit-suffixed labels, `precondition`/`throws` on illegal domains only (never clamp for UI),
`///` docs carrying `Pure, stateless.` and a `MODEL CAVEAT:` wherever a convention is assumed.

**The replay seam (required by `plan_tape.md`).** The tape stores each solved problem's *inputs* and
re-derives its result on reopening — it never persists a number it cannot re-compute. Two Kit-level
properties therefore carry that feature, and both are tested per Kit in `ReplayTests.swift`:

1. **Every public input type is `Codable`, losslessly** — `TVM.Registers`, `Amortization.Loan`,
   `CashFlow.Group`, `Rate.Advance`/`Payment`, `DayCount.YearMonthDay`/`Convention`, and the same for
   each remaining Kit as it lands.
2. **Decoding validates and throws.** A tape file is untrusted input (truncated, hand-edited, written by
   an older build), so an impossible value must surface as a `DecodingError`, never a `precondition`
   trap. The validating `init(from:)` on each of those types exists for exactly this reason — the
   memberwise synthesis would bypass the checks and let a February 31st through.
3. **Solves are bit-for-bit deterministic**: `solve(decoded) == solve(original)` with `==`, not a
   tolerance. That is what lets the app-target tape test compare a stored result against a re-solved one
   exactly.

A ~40-line bracket-then-refine `Solve.swift` is **deliberately duplicated** into CashFlowKit, BondKit and
RateKit — Kits carry no dependencies, and three copies of a solver is cheaper than a dependency edge.

## 5. Oracles — the core deliverable

**All primary sources are already captured and transcribed in `par/scratch/SOURCES.md`, and every family
has a green Python pre-check beside it.** Read that file before writing a corpus; do not re-derive.

Corpus shape per test target (the richer of the two variants in this repo):

```swift
struct Oracle {
    let id: String
    let source: String            // citation + URI/edition/page — MUST be non-empty
    let inputs: [String: Double]  // tests read inputs from here too, so they contain no literals
    let precision: String         // *why* this tolerance, in words
    let values: [String: Double]
    let tolerances: [String: Double]
    func matches(_ key: String, _ actual: Double) -> Bool
}
enum Oracles { static let all: [Oracle]; static func require(_ id: String) -> Oracle }
```

Plus, in every Kit, an **integrity guard** (copy `EphemerisKit/Tests/.../OracleGuardTests.swift`) failing
on an empty `source`/`inputs`/`precision`, a value without a matching tolerance or vice versa, or a
duplicate id — **and a coverage guard** that iterates the Kit's own `allCases` (`DayCount.Convention`,
`Depreciation.Method`, `TVM.Variable`, `Stat.Model`) and fails if a case has no oracle. Suite headers
carry an `ORACLES:` block labelling each entry `PUBLISHED` / `IDENTITY` / `INVARIANT`.

### 5.1 DayCountKit

`Convention { thirty360, thirtyE360, thirtyE360ISDA, actualActualICMA, actual360, actual365Fixed }`;
`days(from:to:convention:terminationDate:)`, `yearFraction(...)`, `dateByAdding(days:)`,
`dateByAdding(months:)` (month-end clamping), `dayOfWeek`, `isLeapYear`, `daysInMonth`.

| oracle | class | source | pin |
|---|---|---|---|
| `isda-3060-<start>-<end>` (22 rows) | PUBLISHED | ISDA `30-360-2006ISDADefs.xls`, 2006 ISDA Definitions §4.16(f)/(g)/(h) | exact integer day counts for all three variants — `scratch/isda_30_360.csv` |
| `isda-3060-termination-date` | PUBLISHED | same, Comparison sheet termination date 2009-02-28 | `2008-08-31→2009-02-28` = 178 under §4.16(h) while `2006-08-31→2007-02-28` = 180. Ignore the termination date and exactly these two rows fail |
| `treasury-halfyear-44-181-81-184` | PUBLISHED | 31 CFR 356 App B §I.D(2) | 44/181 and 81/184 actual/actual half-year fractions, exact |
| `bond-basis-361-day-year` | PUBLISHED | ISDA Bond-Basis sheet, Example 2 | the two half-years sum to **361**, not 360 |
| leap/century/month-end | INVARIANT | definition | 2000 vs 1900, Feb 28/29, Jan-31 + 1 month, additivity where the convention permits |

`MODEL CAVEAT:` all arithmetic is on `DateComponents` in a fixed UTC Gregorian calendar — no locale, no
time zone, no DST.

### 5.2 TVMKit

`solve(for: .periods|.ratePct|.presentValue|.payment|.futureValue, Registers)` where `Registers` =
`{ periods, annualRatePct, presentValue, payment, futureValue, paymentsPerYear, compoundsPerYear,
timing: .end|.begin }`; plus `periodicRate(...)`.

| oracle | class | source | pin |
|---|---|---|---|
| `tvm-five-way-roundtrip` | IDENTITY | definition | solve each of the five from the other four; recover the input to ≤1e-9 relative, over a grid of rates/terms/timings |
| `treasury-356-II-A-as-annuity` | PUBLISHED | 31 CFR 356 App B §II.A | 59 half-years, i/2 = .0442, C/2 = 4.375 → aₙ = 20.8610780353 and vⁿ = .0779403508 (Treasury prints both) |
| `regdd-appA-effective` | PUBLISHED | 12 CFR 1030 App A | 1000 → 1061.68 over 365 days = 6.17% effective |
| `tvm-annuity-due` | INVARIANT | definition | `PV_begin == PV_end × (1+i)`, both directions |
| `tvm-zero-rate` | INVARIANT | Treasury's own special case ("if i = 0, then aₙ = n") | i = 0 exact; `n = −PV/PMT` |
| `tvm-tiny-rate` | INVARIANT | definition | i = 1e-9 via `log1p`/`expm1` vs series, ≤1e-9 |
| `tvm-py-ne-cy` | INVARIANT | definition | payments/yr ≠ compounds/yr → periodic rate `(1+i/m)^(m/p) − 1`; monthly payments on semiannual compounding (the Canadian mortgage case) |

`MODEL CAVEAT:` cash out is negative; both directions are tested.

### 5.3 AmortKit

`payment(...)`, `schedule(...) -> [Period{index, payment, interest, principal, balance}]`,
`balance(after:)`, `totals(in: Range)`, `rounding: .exact | .currency(cents:)` (final payment absorbs
the residue).

| oracle | class | source | pin |
|---|---|---|---|
| `amort-closes` | IDENTITY | definition | Σprincipal == principal; final balance == 0 (≤1e-9, or ≤1¢ under `.currency`) |
| `amort-interest-is-balance-times-rate` | IDENTITY | definition | every period, exactly |
| `regz-appJ-c1-i-schedule` … (5 rows) | PUBLISHED | 12 CFR 1026 App J (c)(1) | at the published APR, a schedule for A=5000 / P=230 / n=24 terminates at zero balance |
| `amort-balance-matches-tvm` | INVARIANT | cross-check | `balance(after: k)` equals the TVM future value at n = k |
| `amort-due-vs-end` | INVARIANT | definition | annuity-due schedule differs by exactly one period of discounting |

### 5.4 CashFlowKit

`npv(rate:flows:)`, `nfv`, `irr(flows:)` → `.unique(Double) | .multiple([Double]) | .none`,
`mirr(financeRate:reinvestRate:)`, `payback`, `discountedPayback`, `uniformPresentValue`,
`groupedFlows(amount:count:)` (the CFj/Nj entry model), `discountFactor`.

| oracle | class | source | pin |
|---|---|---|---|
| `irr-zeroes-npv` | IDENTITY | definition | `NPV(flows, IRR) == 0`, ≤1e-10 of scale |
| `regz-appJ-c6-i` | PUBLISHED | 12 CFR 1026 App J (c)(6)(i) | skipped-payment loan, A=2135, 24×100 in four series → **12.00%** — a published IRR on genuinely irregular flows |
| `regz-appJ-c6-ii` | PUBLISHED | App J (c)(6)(ii) | A=7350 with mixed series and single payments → **10.22%** |
| `nist-hb135-ex7-1` | PUBLISHED | NIST HB 135e2025 §7.1.1, pp.94–95 | UPV* 16.15/15.48 → base LCC **$27 944**, alternative **$26 344** |
| `nist-hb135-upv` | PUBLISHED | NIST HB 135e2025 §6 | UPV(d, n) = (1−(1+d)⁻ⁿ)/d at the handbook's stated rate |
| `irr-multiple-sign-changes` | INVARIANT | definition | two sign changes → both roots reported, never one silently |
| `npv-monotone-and-linear` | INVARIANT | definition | monotone in rate for conventional flows; linear in the flow vector |

### 5.5 BondKit

Treasury's **five** price cases, not one: `price(...)` for a regular, short-first, long-first, reopened-in-
regular-period and reopened-in-long-period security; `accruedInterest(...)`,
`accruedAcrossTwoHalfYears(...)`, `yieldToMaturity(...)`, `currentYield`, `macaulayDuration`,
`modifiedDuration`, `convexity`, `billPrice(discountRate:days:)`, `billDiscountRate(price:days:)`,
`billInvestmentRate(price:days:yearBasis:)` (both branches), `tipsIndexRatio`, `tipsAdjustedPrincipal`.

Formulas use Treasury's **simple** interest factor `[1 + (r/s)(i/2)]` on the fractional first period —
*not* an exponential `(1+i/2)^(r/s)`. The pre-check proves an exponential discount still reproduces §II.A
(where r = s) and then misses §II.D by 7.7e-3 per 100. See `scratch/treasury_356.py`.

| oracle | class | source | pin (per 100) |
|---|---|---|---|
| `treasury-II-A-price` | PUBLISHED | 31 CFR 356 App B §II.A | C=8.75, i=.0884, n=59, r=s=184 → **99.057893** (±5e-7) |
| `treasury-II-B-price-short-first` | PUBLISHED | §II.B | C=8.50, i=.0859, n=3, r=181, s=183 → **99.838183** |
| `treasury-II-C-price-long-first` | PUBLISHED | §II.C | C=8.50, i=.0853, n=10, r=75, s=181 → **99.805118** |
| `treasury-II-D-price-reopening` | PUBLISHED | §II.D | C=9.50, i=.0954, n=19, r=167, s=181 → A=**.367403**, P=**99.730918** |
| `treasury-II-E-price-reopening-long` | PUBLISHED | §II.E | C=10.75, i=.1047, n=39, r=103, s=184, r′=44, s″=181 → A=**3.672798**, P=**102.214586** |
| `treasury-I-D-accrued-two-half-years` | PUBLISHED | §I.D(2) | $1,000 par → **$36.727983109** (Treasury rounds the daily accrual to 9 dp first; the exact product differs at 1.6e-8 — tolerance documents this) |
| `treasury-VI-A-bill-price` | PUBLISHED | §VI.A | d=.07610, r=90 → **98.097500** |
| `treasury-VI-D-1-investment-rate` | PUBLISHED | §VI.D.1 | P=99.559444, r=20 → **.080756** (±2e-6: the published step (2) rounds (100−P)/P to 6 dp; unrounded is .08075725) |
| `treasury-VI-D-2-investment-rate` | PUBLISHED | §VI.D.2 | P=92.265000, r=364 → **.082373244**, via a = .248630137, b = .997260274, c = −.083834607 |
| `treasury-III-index-ratio` | PUBLISHED | §III | 163.29032 / 161.55484 → **1.01074**, truncated to 5 dp (truncated, not rounded) |
| `bond-price-yield-invert` | IDENTITY | definition | `yield(price(y)) == y` to ≤1e-9 over a coupon × maturity × yield grid (measured: 1e-9 by bisection) |
| `duration-is-price-derivative` | INVARIANT | definition | modified duration == −(1/P)·dP/dy by central difference, ≤1e-6 relative; convexity likewise |
| `bond-zero-yield` | INVARIANT | Treasury §II definitions | i = 0 → aₙ = n (Treasury's own special case), price = undiscounted sum |

### 5.6 DepKit

`straightLine`, `decliningBalance(factor:)`, `decliningBalanceWithCrossover(factor:)`,
`sumOfYearsDigits`, `macrs(recoveryYears:method:convention:)` for GDS half-year and mid-quarter
(all four quarters), `bookValue(after:)`, `remainingDepreciableBasis`.

**MACRS finding (from `scratch/macrs.py`):** the published tables are *not* a rounding of the continuous
schedule — they are computed in **rounded percentages that carry forward** (each year rounded to 2 dp,
3 dp for 20-year, and the rounded figure is what reduces the running basis). That carry is what produces
the published alternations (7-year 8.93 / 8.92 / 8.93; 10-year …6.55 / 6.56 / 6.55) and makes every column
total exactly 100.00%. Implementing it that way reproduces **11 of 12 published columns exactly**;
implementing the continuous schedule instead misses by up to 0.0064 pp. So `macrs` takes a
`rounding: .irsTable(decimals:) | .exact`.

| oracle | class | source | pin |
|---|---|---|---|
| `irs946-2025-tableA1-<n>yr` (6 columns) | PUBLISHED | IRS Pub 946 (2025) App A Table A-1, p.70 | exact equality under `.irsTable`; `scratch/irs946_2025_tableA1.csv` |
| `irs946-2025-tableA2-q1-<n>yr` (6 columns) | PUBLISHED | Table A-2, p.70–71 | exact, **except** the 20-year column at years 2 and 21 — see below |
| `irs946-2025-tableA2-q1-20yr-anomaly` | PUBLISHED | Table A-2, verified against a 200-dpi render of p.71 | the published column gives 7.000 / 0.565 where the method gives 7.008 / 0.557 (both columns still total 100.00%; the 0.008 pp is shifted from year 2 to year 21). Asserted **as the documented deviation**, so a change in the method breaks the test rather than hiding in a loose tolerance. Goes on the RELEASE_CHECKLIST for a human cross-check |
| `irs946-2025-furniture-example` | PUBLISHED | Pub 946, "Figuring the Deduction" | $10,000 of 7-year property → 1,429 / 2,449 / 1,749 / 1,249 / 893 / 892 / 893 / 446 |
| `dep-closes` | IDENTITY | definition | Σdepreciation == cost − salvage for every method; ΣMACRS == 100.00% |
| `db-crossover-year` | INVARIANT | definition | crossover is the first year SL on remaining basis beats DB; book value monotone and never below salvage |
| `syd-weights` | IDENTITY | definition | year k factor == (n−k+1)/(n(n+1)/2) |

### 5.7 RateKit

`aprActuarial(advances:payments:unitPeriodsPerYear:)` per Reg Z App J (b)(8) — the general equation, with
advances and payments each carrying `(amount, fullPeriods, fraction)`; `aprUnitedStatesRule(...)` (Reg Z's
other permitted method); `apy(interest:principal:days:)`, `apyEarned(...)` per Reg DD App A;
`nominalToEffective`, `effectiveToNominal`, `continuousEquivalent`, `addOnToSimple`.

The fractional period uses the **simple** factor `(1 + f·i)`, not `(1+i)^f`. Nine of the seventeen
published examples only pass with it right (`scratch/regz_appJ.py`).

| oracle | class | source | pin |
|---|---|---|---|
| `regz-appJ-c1-i` … `c6-ii` (**17 rows**) | PUBLISHED | 12 CFR 1026 App J (c)(1)–(c)(6), transcribed in SOURCES.md §2 | each published APR to its 2 dp (tolerance 0.005 pp — measured worst deviation 0.00488 pp, i.e. the published rounding itself). Covers regular / long-first / short-first / odd-first-payment / odd-final-payment / both-odd / single-payment (4 forms) / skipped-payment / mixed-series |
| `regdd-appA-apy-<n>` | PUBLISHED | 12 CFR 1030 App A | 1000/61.68/365 → **6.17%**; 1000/30.37/182 → **6.18%**; earned 1000/5.25/30 → **6.58%** |
| `nominal-effective-roundtrip` | IDENTITY | definition | ≤1e-12 over m ∈ {1,2,4,12,52,365}, and the continuous limit |
| `apr-vs-irr` | INVARIANT | cross-Kit | APR/w equals the CashFlowKit IRR of the same flows when f = 0 |
| `regz-tolerance-note` | — | 12 CFR 1026.22(a)(2) | Reg Z's ⅛-point legal tolerance is documented in the API docs and **not** used as a test tolerance |

### 5.8 PercentKit

`percentChange`, `percentOf`, `percentTotal`, `markupOnCost`, `marginOnPrice`, `costSellMargin` (solve any
one of the three), `breakEvenUnits(fixed:price:variable:)`, `breakEvenRevenue`, `unitsForTargetProfit`,
`grossProfit`, `chainedDiscount`, `taxInclusive`/`taxExclusive`.

All entries are IDENTITY class — these are definitions, and the corpus says so rather than dressing them
up with a citation. Tested as: markup↔margin round-trip (`margin = markup/(1+markup)`), the
cost-sell-margin triangle solving consistently from any two, break-even where profit is exactly zero,
chained discounts ≠ summed discounts, and the sign of every result under a negative change.

### 5.9 StatKit

1-var: `n, Σx, Σx², mean, sampleSD, populationSD, variance, median, sorted quartiles`.
2-var: `Σxy, meanX/Y, sampleSD, correlation, slope, intercept, forecastY(x:), forecastX(y:)`,
`Model { linear, logarithmic, exponential, power }` (fit by transforming the data), `autocorrelation(lag:)`.
Variance uses a **numerically stable** one-pass form (Welford), not `Σx² − n·x̄²`.

| oracle | class | source | pin |
|---|---|---|---|
| `nist-strd-norris` | PUBLISHED | NIST/ITL StRD, `Norris.dat` (linear least squares, 36 obs) — `scratch/nist_Norris.dat` | B0 = **−0.262323073774029** (sd 0.232818234301152), B1 = **1.00211681802045** (sd 0.429796848199937e-3), residual sd **0.884796396144373**, R² **0.999993745883712** |
| `nist-strd-lew` | PUBLISHED | NIST/ITL StRD, `Lew.dat` (200 obs) — `scratch/nist_Lew.dat` | mean **−177.435000000000**, s **277.332168044316**, r(1) **−0.307304800605679** |
| `nist-strd-numacc2` | PUBLISHED | NIST/ITL StRD `NumAcc2` certified values | 1001 values (1.2 then alternating 1.1/1.3): mean **1.2 exact**, s **0.1 exact**, r(1) **−0.999 exact**. This is the catastrophic-cancellation test — the textbook variance formula fails it |
| `regression-invariance` | INVARIANT | definition | slope/intercept invariant under x-shift the right way; r ∈ [−1, 1]; r² == R²; forecast inverts |
| coverage guard | guard | — | every `Stat.Model` case has an oracle |

NIST StRD is a US-government reference set published specifically to test statistical software; using its
certified values is exactly its purpose.

### 5.10 RealEstateKit

`noi(grossIncome:vacancy:operatingExpenses:)`, `capRate(noi:value:)`, `valueFromNOI(noi:capRate:)`,
`grossRentMultiplier`, `dscr(noi:annualDebtService:)`, `ltv(loan:value:)`,
`maxLoanByDSCR(noi:targetDSCR:ratePct:amortYears:)`, `maxLoanByLTV`, `cashOnCash`, `equityDividendRate`,
`breakEvenOccupancy`, `pricePerUnit`, `pricePerSquareFoot`, `oneToOneExchangeBasis`.

IDENTITY/INVARIANT class throughout — these are ratio definitions, and the corpus labels them as such.
Cross-Kit invariants carry the weight: `maxLoanByDSCR` must be the loan whose TVM-computed payment gives
exactly the target DSCR; `capRate × valueFromNOI` round-trips; DSCR = 1.0 ⇔ break-even.
**`TODO(oracle):`** a published underwriting worked example (HUD MAP guide or a Fannie Mae multifamily
term sheet) would upgrade `maxLoanByDSCR` to PUBLISHED — attempted and not obtained this session, so it
stays honestly labelled rather than dressed up.

## 6. UI — deliberately minimal, but two things must be right

Only after every Kit is green. **One plain SwiftUI screen per tool**, a simple list to choose between
them. Native components only — **do not invent a design system, do not theme, do not animate.** Every
input a `TextField` with an explicit min…max; every output a labelled row with its unit. **Zero math in
views**: a `@MainActor ObservableObject` whose outputs are computed calls into the Kit.

Two exceptions, because they *are* the competitive point:

1. **Adaptive layout that genuinely works on iPad and Mac, including Split View.**
2. **Dynamic Type.** No fixed point sizes anywhere.

Ship the **amortization schedule and cash-flow list as visible, scrollable tables** rather than hidden
registers. That alone differentiates from every incumbent.

**Verify by build only**: `xcodegen generate`, then `xcodebuild` iOS + macOS → BUILD SUCCEEDED, plus an
Xcode `#Preview` per screen. Do **not** boot a simulator, capture screenshots, or run UI tests.

## 7. Order of work and gates

1. ~~Fill in this plan~~ — **done, approved 2026-07-27.**
2. ~~Capture the primary sources~~ — **done: `scratch/SOURCES.md`, `isda_30_360.csv`,
   `irs946_2025_table*.csv`, `nist_Norris.dat`, `nist_Lew.dat`, `30-360-2006ISDADefs.xls`.**
3. ~~Python pre-checks~~ — **done and green: `daycount.py` (22 rows × 3 conventions, exact),
   `macrs.py` (11/12 columns exact + 1 documented anomaly), `regz_appJ.py` (17/17 within published
   rounding), `treasury_356.py` (14/14).** Tolerances below come from these measured residuals.
4. ~~Kits~~ — **all ten green offline as of 2026-07-27, 202 tests:** DayCount 24 · TVM 23 · Amort 19 ·
   CashFlow 21 · Rate 20 · Bond 31 · Dep 21 · Percent 12 · Stat 19 · RealEstate 12. Each carries its
   corpus, an integrity + coverage guard, PUBLISHED/IDENTITY/INVARIANT suites, and the
   `ReplayTests.swift` seam. Two Kits are honestly definition-backed rather than publication-backed
   (Percent, RealEstate) and say so in their own test suites; RealEstate carries the one open
   `TODO(oracle):` in the project.

4b. **`par/Chains/ChainTests/` — the seams between Kits, 50 tests, green.** Not a Kit and it ships
   nothing: Kits take no dependencies on each other, so a chain like *dates → day count → bond price* has
   no home inside either one, and two individually-correct Kits can still be wrong together. Ten Kits
   give **90 ordered pairs**; `ChainSupport/ChainMatrix.swift` classifies every one of them and a
   coverage guard fails if a pair is unclassified, if a chain is marked tested without a test, or if a
   dismissal is too terse to argue with. Composition: **10 published · 26 identity · 14 invariant ·
   38 not-applicable · 2 recorded gaps.**
5. ~~App shell + UI~~ — **done 2026-07-28.** `project.yml` (xcodegen), bundle
   **`oleksandr.aisixteen.fincalc`** (registered on App Store Connect, permanent), `PRODUCT_NAME: Par`,
   `par-macOS.entitlements` with read-write file access, and the repo's first `DocumentGroup` app —
   `UTExportedTypeDeclarations` + `CFBundleDocumentTypes` via an xcodegen `info:` block, since
   `INFOPLIST_KEY_*` cannot express nested arrays. **All ten tools built** (37 files, ~4,900 lines),
   each with a view model, a screen, rendered failure states, a `ProvenanceStrip`, and dark + AX5
   previews. iOS and macOS **BUILD SUCCEEDED**.
6. **Phase 5b — the tape** (built alongside §5, since the templates arrived with it). `par/plan_tape.md` governs: a tape of *solved problems*, appended
   automatically, correctable line by line, labelled, stored as a document, printable and exportable.
   Do not start it while any Kit still has a `TODO(oracle):`; report with that file's four testable
   claims demonstrated in the app target's tests.
7. Then `par/DESIGN_BRIEF.md` (§8) — which must carry the tape as a first-class surface, not an
   afterthought, because it is what the $9.99 incumbent in this category is loved for.

**Never:** invent an oracle number (`TODO(oracle):` instead), use any trademark from §3, commit without
explicit human go, or touch App Store Connect.

**Report per Kit:** oracle count, sources cited, `swift test` result, remaining `TODO(oracle):`. Flag
anything you could not cite. *A green suite containing an uncited number is worse than a red one.*

## 8. `DESIGN_BRIEF.md` — the redesign handoff, written after the code

A self-contained brief for a separate design-focused session (assume no memory). It must carry:

- **What Par is and who buys it**, and the wedge: the incumbents' fatal reviews are about *layout*, so
  adaptive iPhone/iPad/Mac layout including Split View, and Dynamic Type with no pinned point sizes, are
  **requirements, not polish**.
- **Screen inventory** — one row per screen: inputs (with ranges), outputs, and the single **hero
  number**; which screens are forms and which need real scrollable tables.
- **The Kit API surface it may call**, with the rule: views and view models format and display, they
  never compute. Kit APIs and oracle corpora are **frozen** — a design need that seems to require new
  math comes back as a question, not an edit.
- **What to port, not invent** — `truecourse.swift/DesignSystem` and `overtonelab.swift` primitives
  (`NumberField(range:)`, `ResultRow(unit:emphasis:)`, `.glassCard()`, `Fmt`); replace in place, never a
  parallel `DesignSystem/` folder (types double-declare).
- **Hard bans** — the §3 trademark list and the trade-dress ban.
- **Accessibility** — an `accessibilityIdentifier` on every input and hero output.
- **How to verify** — `xcodegen generate`, iOS + macOS `xcodebuild`, a light and a dark `#Preview` per
  screen. No simulator, no screenshots, no UI tests.
- **Where the truth lives** — this file §3 and §5, `scratch/SOURCES.md`, `calculators/VALIDATION.md`.
