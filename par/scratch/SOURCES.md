# Par — primary sources, transcribed

Every expected number in the Kits traces to a row in this file. All retrieved **2026-07-27**.
Transcription is itself error-prone: each family has a `*.py` pre-check here that recomputes the
published value from the published inputs. A row that doesn't reproduce is a transcription bug —
re-read the source, don't adjust the tolerance.

Licensing: every source below is either a US government work (public domain) or published by the
convention's own author for educational use. No copyrighted textbook tables, no trademarks.

---

## 1. 31 CFR Part 356, Appendix B — "Formulas and Examples" (US Treasury, public domain)

Uniform Offering Circular for the sale and issue of marketable book-entry Treasury securities.
Read at <https://www.law.cornell.edu/cfr/text/31/appendix-B_to_part_356>.
Symbols: `C` = coupon rate per 100, `i` = nominal yield, `n` = full half-years to maturity,
`r` = days from settlement to next coupon, `s` = days in the current half-year, `A` = accrued
interest per 100.

| § | inputs | published result |
|---|---|---|
| II.A — price from yield, regular first period | 8¾% 30-yr bond, issued 1990-05-15, due 2020-05-15; C=8.75, i=.0884, n=59, r=184, s=184 | **P = 99.057893** |
| II.D — price with accrued interest | 9½% 10-yr note, accrues from 1985-11-15, issued 1985-11-29; C=9.50, i=.0954, n=19, r=167, s=181 | **A = .367403**, **P = 99.730918** |
| I.D — accrued interest over two half-years (reopening) | 10¾% bond, originally issued 1985-07-02, reopened 1985-11-04; 44 days of a 181-day half-year + 81 days of a 184-day half-year | **$36.727983109 → $36.72798** |
| VI.A — bill price from discount rate | issued 1989-11-24, matures 1990-02-22; d = .07610, r = 90; `P = 100(1 − dr/360)` | **P = 98.097500** |
| VI.D.1 — bill coupon-equivalent, ≤ 6 months | cash-management bill issued 1990-06-01, due 1990-06-21; P = 99.559444, r = 20, y = 365 | **i = .080756** (8.076%) |
| VI.D.2 — bill coupon-equivalent, > 6 months | 52-week bill issued 1990-06-07, due 1991-06-06; P = 92.265000, r = 364, y = 365; quadratic with a = .248630137, b = .997260274, c = −.083834607 | **i = .082373244** (8.237%) |
| III.B — TIPS index ratio (reopening) | 3⅝% 10-yr TIPS issued 1998-01-15, reopened 1998-10-15; Ref CPI_Date = 163.29032, Ref CPI_IssueDate = 161.55484 | **Index Ratio = 1.01074** (truncated to 5 dp) |

Verify the exact par amount in §I.D against the source before pinning the dollar figure.

## 2. 12 CFR Part 1026 (Regulation Z), Appendix J — APR by the actuarial method (public domain)

`https://www.govinfo.gov/content/pkg/CFR-2024-title12-vol9/pdf/CFR-2024-title12-vol9-part1026-appJ.pdf`
(1–1–24 edition, pp. 431–442). **The equations and all examples are page images in both the print CFR
and eCFR** — these were transcribed by rendering pp. 435–440 at 150 dpi and reading them. Appendix J
states its own numbers "were obtained by using a 10 digit programmable calculator and the iteration
procedure described above", and that the APR is correct when rounded to 2 decimals.

Symbols: `A` = amount advanced, `P` = payment, `n` = number of payments, `w` = unit-periods per year,
`t` = full unit-periods to the first payment, `f` = leading fractional unit-period, `I = wi × 100`.

### (c)(1) Single advance, otherwise regular
| ex | inputs | published APR |
|---|---|---|
| i | A=5000, P=230, n=24, monthly, w=12, t=1, f=0 | **9.69%** (i = .0969/12 per period) |
| ii | A=6000, P=200, n=36, w=12, t=1, f=19/30 | **11.82%** |
| iii | A=5000, P=219.17, n=24, semimonthly, w=24, t=0, f=6/15 | **10.34%** |
| iv | A=10000, P=385, n=40, quarterly, w=4, t=1, f=39/90 | **8.97%** |
| v | A=500, P=17.60, n=30, weekly, w=52, t=4, f=4/7 | **14.96%** |

### (c)(2) Odd first payment
| ex | inputs | published APR |
|---|---|---|
| i | A=5000, P₁=250, P=230, n=24, w=12, t=1, f=0 | **10.08%** |
| ii | A=400, P₁=39.50, P=38.31, n=12, 4-weekly, w=13, t=1, f=5/28 | **28.50%** |

### (c)(3) Odd final payment
| ex | inputs | published APR |
|---|---|---|
| i | A=5000, P=230, Pₙ=280, n=24, w=12, t=1, f=0 | **10.50%** |
| ii | A=200, P=9.50, Pₙ=30, n=20, biweekly, w=26, t=0, f=8/14 | **12.22%** |

### (c)(4) Odd first *and* final payment
| ex | inputs | published APR |
|---|---|---|
| i | A=5000, P₁=250, P=230, Pₙ=280, n=24, w=12, t=1, f=0 | **10.90%** |
| ii | A=8000, P₁=449.36, P=465, Pₙ=200, n=20, every 2 months, w=6, t=0, f=52/60 | **7.30%** |

### (c)(5) Single advance, single payment
| ex | inputs | published APR |
|---|---|---|
| i | A=1000, P=1080, unit-period 255 days, w=365/255, t=1, f=0 | **11.45%** (Form 1 or 4) |
| ii | A=1000, P=1044, unit-period 6 months, w=2, t=1, f=0 | **8.80%** (Form 1 or 4) |
| iii | A=1000, P=1135.19, unit-period 1 year, w=1, t=1, f=6/12 | **8.76%** (Form 2 or 4) |
| iv | A=1000, P=1240, unit-period 1 year, w=1, t=2, f=0 | **11.36%** (Form 3 or 4) |

### (c)(6) Complex single advance — irregular series (these double as IRR oracles)
| ex | inputs | published APR |
|---|---|---|
| i — skipped-payment loan | A=2135 on 1978-01-25; 24 payments of 100 every 4 weeks, w=13, in four series: (t₁=0, f₁=26/28, 9 pmts) (t₂=10, f₂=12/28, 6) (t₃=16, f₃=26/28, 6) (t₄=23, f₄=12/28, 3) | **12.00%** |
| ii — skipped payments plus single payments | A=7350 on 1978-03-03; 3×1000 monthly from 1978-09-15 (t=6, f=12/30), single 2000 at (t=12, f=12/30), 3×750 from 1979-09-15 (t=18, f=12/30), final 1000 at (t=22, f=29/30); w=12 | **10.22%** |

Closed forms per case are given at (c)(1)–(c)(6); the general equation is (b)(8) and the iteration
procedure (b)(9). Reg Z's own *legal* tolerance is ⅛ of 1 percentage point (§1026.22(a)(2)) — that is a
compliance tolerance, **not** our test tolerance, which is the 2-dp rounding of the published value.

## 3. 12 CFR Part 1030 (Regulation DD), Appendix A — APY (public domain)

<https://www.law.cornell.edu/cfr/text/12/appendix-A_to_part_1030>

```
APY        = 100 [ (1 + Interest/Principal) ^ (365/Days in term)      − 1 ]
APY Earned = 100 [ (1 + Interest earned/Balance) ^ (365/Days in period) − 1 ]
```

| example | inputs | published APY |
|---|---|---|
| Part I A — NOW account | principal 1000, interest 61.68, 365 days | **6.17%** |
| Part I A — 6-month CD | principal 1000, interest 30.37, 182 days | **6.18%** |
| Part I — stepped-rate 6-month CD | 1000; 5% daily 91 d then 5.5% daily 92 d; interest 26.68, 183 days | **5.39%** |
| Part I — stepped-rate 2-year CD | 1000; 6% then 6.5% daily; interest 133.13, 730 days | **6.45%** |
| Part II — APY earned, statement period | balance 1000, interest 5.25, 30 days | **6.58%** |
| Part II — APY earned | balance 1500, interest 6.50, 30 days | **5.40%** |
| Part II — APY earned, quarterly | balance 2000, interest 21.00, 91 days | **4.28%** |

⚠ Only the first two and the 1000/5.25/30 row were read directly from the regulation text; the rest came
from a summarizer and **must be re-read from the source before they enter the corpus** (each is trivially
recomputable from the formula — `regdd_appA.py` does exactly that, so a mis-transcribed row will fail).

## 4. IRS Publication 946 (2025), Appendix A — MACRS percentage tables (public domain)

<https://www.irs.gov/pub/irs-pdf/p946.pdf>, pp. 70–73: **all five tables** — A-1 (half-year) and A-2
through A-5 (mid-quarter, quarters 1–4). Extracted mechanically by `parse_p946_tables.py` into
`irs946_2025_tableA1.csv` … `irs946_2025_tableA5_q4.csv`; A-1 and A-2 were independently hand-transcribed
first and the two agree exactly.

**Finding — the tables carry their rounding forward.** The published percentages are not a rounding of
the continuous declining-balance schedule. Each year is rounded (2 dp, 3 dp for 20-year property) and the
*rounded* figure reduces the running basis, so the rounding compounds. That is what produces the
published alternations (7-year 8.93 / 8.92 / 8.93; 10-year …6.55 / 6.56 / 6.55) and makes every column
total exactly 100.00%. Reproducing it that way matches **28 of the 30 columns digit for digit**; computing
the continuous schedule instead misses by up to 0.0064 pp.

**Finding — two published columns are internally inconsistent.** Both verified against 200-dpi renders of
the source pages, not just the text extraction:

| table | column | year | published | rounding-carry method |
|---|---|---|---|---|
| A-2 (mid-quarter Q1) | 20-year | 2 | 7.000 | 7.008 |
| A-2 (mid-quarter Q1) | 20-year | 21 | 0.565 | 0.557 |
| A-3 (mid-quarter Q2) | 7-year | 1 | 17.85 | 17.86 |
| A-3 (mid-quarter Q2) | 7-year | 8 | 3.34 | 3.33 |

In both cases the difference is *shifted* to a later year and the column still totals 100.00%. The A-3
case is the clearer one: the exact first-year figure is 2/7 × 0.625 = 17.857142…, which rounds to 17.86 by
any ordinary rule, and the same table's 3-year column (41.666… → 41.67) shows the IRS is rounding rather
than truncating. DepKit asserts **both** sides of each divergence, so neither the published value nor
Par's own can drift unnoticed — and it goes on the release checklist for a human to confirm against a
fresh copy of the publication.

Worked example, "Figuring the Deduction" chapter: office furniture (7-year property), cost **$10,000**,
placed in service August, half-year convention, no §179 and no bonus →
**1,429 · 2,449 · 1,749 · 1,249 · 893 · 892 · 893 · 446** (dollars, per year).

Method per column: 3/5/7/10-year = 200% DB switching to SL; 15/20-year = 150% DB switching to SL.
Sum of each column = 100.00% (a closure invariant worth asserting).

## 5. NIST Handbook 135e2025 — Life-Cycle Costing Manual (public domain)

<https://nvlpubs.nist.gov/nistpubs/hb/2025/NIST.HB.135e2025.pdf>, §7.1.1 Example 7-1
("Decision to Accept or Reject Storm Windows"), pp. 94–95:

- initial cost $2000, base/service date January 2019, 20-year study period, DOE discount rate 3% real,
  no replacement, zero residual; gas $1.05/therm, electricity $0.135/kWh
- FEMP UPV* factors: natural gas **16.15**, electricity **15.48**
- base case (do nothing): E = 1.05 × 1500 × 16.15 + 0.135 × 1200 × 15.48 → LCC **$27 944**
- alternative: E = 1.05 × 1300 × 16.15 + 0.135 × 1100 × 15.48 = 24 344 → LCC **$26 344**

`LCC = I₀ + Repl − Res + E + OMR + X` (Eq. 7-1). Also the source for the SPV/UPV factor definitions,
net savings, SIR and AIRR (§6).

## 6. ISDA — 30/360 calculation examples (published by the convention's author, "educational use")

Workbook `30-360-2006ISDADefs.xls`, <https://www.isda.org/a/mIJEE/30-360-2006ISDADefs.xls>, linked from
<https://www.isda.org/2008/12/22/30-360-day-count-conventions/>. Committed here beside
`dump_isda_xls.py`, which produces `isda_30_360.csv` (22 published date pairs × 3 conventions + actual).

Rule text quoted by the workbook, per **2006 ISDA Definitions §4.16**:

- **30/360 / Bond Basis, §4.16(f)** — `days = (Y2−Y1)·360 + (M2−M1)·30 + (D2−D1)`;
  if DAY1 = 31 → D1 = 30; if DAY2 = 31 **and** DAY1 ∈ {30, 31} → D2 = 30.
- **30E/360 / Eurobond Basis, §4.16(g)** — as above, but D2 = 30 whenever DAY2 = 31, unconditionally.
  ("Based on ICMA Rule 251 and FBF; this is the version of 30E/360 used by Excel.")
- **30E/360 (ISDA), §4.16(h)** — D1 = 30 if DAY1 = 31 *or* DAY1 is the last day of February;
  D2 = 30 if DAY2 = 31 *or* DAY2 is the last day of February **but not the Termination Date**.

The Comparison sheet's termination date is **2009-02-28** — which is why row `2008-08-31 → 2009-02-28`
keeps D2 = 28 under §4.16(h) while `2006-08-31 → 2007-02-28` substitutes 30. Any implementation that
ignores the termination date reproduces 20 of the 22 rows and fails exactly those two: that pair is the
single most valuable oracle in the file.

Bond-Basis sheet also documents the 361-day curiosity: `2007-02-28 → 2007-08-31` = 183 and
`2006-08-31 → 2007-02-28` = 178, so the two half-years sum to 361 rather than 360.

## 7. NIST/ITL Statistical Reference Datasets (StRD) — certified statistics (public domain)

Published by NIST specifically to test the numerical accuracy of statistical software, with certified
values computed in extended precision. Retrieved 2026-07-27; the data files are committed here and
emitted into StatKit's corpus by `gen_stat_oracles.py` (Kits carry no resources).

| dataset | n | certified values |
|---|---|---|
| **Norris** — linear least squares, `nist_Norris.dat` (<https://www.itl.nist.gov/div898/strd/lls/data/LINKS/DATA/Norris.dat>) | 36 | B0 = **−0.262323073774029** (sd 0.232818234301152) · B1 = **1.00211681802045** (sd 0.429796848199937e-3) · residual sd **0.884796396144373** · R² **0.999993745883712** |
| **Lew** — univariate, `nist_Lew.dat` (<https://www.itl.nist.gov/div898/strd/univ/data/Lew.dat>) | 200 | mean **−177.435000000000** · s **277.332168044316** · r(1) **−0.307304800605679** |
| **NumAcc2** — univariate, defined by construction (1.2 then alternating 1.1/1.3) | 1001 | mean **1.2**, s **0.1**, r(1) **−0.999**, all *exact* |

NumAcc2 exists to break the textbook variance formula `√((Σx² − n·x̄²)/(n−1))`. StatKit uses Welford's
recurrence instead, and its test asserts both that the stable form reproduces 0.1 **and** that the naive
form fails on the same data — otherwise the choice of algorithm would be unproven.

## 8. Not obtained

- **MSRB Rule G-33** (30/360 accrued interest for municipal securities) — msrb.org returns HTTP 403 to
  automated fetch. 30/360 stays ISDA-cited; do not substitute a secondary description of the rule.
- **A published underwriting worked example** for RealEstateKit (HUD Multifamily Accelerated Processing
  guide, or an agency multifamily term sheet with a DSCR-sized loan). Attempted 2026-07-27, not obtained.
  `maxLoanByDSCR` therefore stays IDENTITY class, cross-checked against the coverage it reproduces rather
  than against a citation, and `RealEstateTests` carries the `TODO(oracle):` as an assertion so it cannot
  be quietly forgotten.
