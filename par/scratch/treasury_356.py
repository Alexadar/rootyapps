#!/usr/bin/env python3
"""Pre-check: 31 CFR part 356 Appendix B against Treasury's own worked examples.

Oracle: 31 CFR part 356, Appendix B, "Formulas and Examples" — read from the GPO
print CFR (7-1-24 edition), pp. 409-412 and 419-421:
https://www.govinfo.gov/content/pkg/CFR-2024-title31-vol2/pdf/CFR-2024-title31-vol2-part356-appB.pdf
US government work, public domain. See SOURCES.md §1.

KEY FINDING (this is why the pre-check exists): Treasury does **not** discount the
fractional first period exponentially. Every price formula multiplies the price by
the *simple* interest factor [1 + (r/s)(i/2)]:

    A. regular first period      P·[1+(r/s)(i/2)] = (C/2)(r/s) + (C/2)aₙ + 100vⁿ
    B. short first period        same, with r,s per the short period
    C. long first period         P·[1+(r/s)(i/2)] = [(C/2)(r/s)]v + (C/2)aₙ + 100vⁿ
    D. reopening, regular period (P+A)·[1+(r/s)(i/2)] = C/2 + (C/2)aₙ + 100vⁿ
    E. reopening, regular portion of a long first period
                                 (P+A)·[1+(r/s)(i/2)] = (r′/s″)(C/2) + C/2 + (C/2)aₙ + 100vⁿ

with vⁿ = 1/(1+i/2)ⁿ, aₙ = (1−vⁿ)/(i/2)  [and aₙ = n when i = 0, by Treasury's own
special case], A = [(s−r)/s](C/2). An exponential (1+i/2)^(r/s) discount instead of
the simple factor reproduces §II.A (where r = s) but misses §II.D by 7.7e-3 per 100
— i.e. it looks right until it silently isn't. Run: python3 treasury_356.py
"""
import math
import sys

FAILURES = 0


def report(label, got, want, tol, note=""):
    global FAILURES
    ok = abs(got - want) <= tol
    FAILURES += 0 if ok else 1
    print(f"{'ok  ' if ok else 'FAIL'} {label:46} got {got:.9f} published {want:.9f}"
          f"  |Δ| {abs(got - want):.2e} (tol {tol:.0e}) {note}")


# ── §I. accrued interest ────────────────────────────────────────────────────


def accrued_regular(C, r, s, par=100.0):
    """§I: accrued interest = [(s−r)/s](C/2), scaled to par."""
    return par / 100.0 * ((s - r) / s) * (C / 2.0)


def accrued_two_half_years(C, days1, s1, days2, s2, par=1000.0, treasury_daily_rounding=True):
    """§I.D(2): a reopening whose accrual spans two half-years of different length.

    Treasury computes the *daily* accrual per $1,000, rounds it to nine decimals,
    then multiplies by the day count in each half-year — which is why the exact
    product differs from the published figure in the 8th decimal.
    """
    coupon = par * (C / 100.0) / 2.0
    d1, d2 = coupon / s1, coupon / s2
    if treasury_daily_rounding:
        d1, d2 = round(d1, 9), round(d2, 9)
    return d1 * days1 + d2 * days2


# §I.D(2): 10¾% bond issued 1985-07-02, reopened 1985-11-04; 44 days of a 181-day
# half-year plus 81 days of a 184-day half-year, per $1,000.
report("§I.D(2) accrued, two half-years, $1,000 par",
       accrued_two_half_years(10.75, 44, 181, 81, 184), 36.727983109, 5e-9,
       "(daily accrual rounded to 9 dp, as published)")
report("§I.D(2) same, without Treasury's daily rounding",
       accrued_two_half_years(10.75, 44, 181, 81, 184, treasury_daily_rounding=False),
       36.727983109, 5e-8, "(exact product; published value carries their rounding)")

# ── §II. yield → price, all five non-indexed cases ──────────────────────────


def vn_an(i, n):
    v_n = 1.0 / (1.0 + i / 2.0) ** n
    a_n = n if i == 0 else (1.0 - v_n) / (i / 2.0)
    return v_n, a_n


def price_regular(C, i, n, r, s):
    """§II.A / §II.B — regular or short first interest payment period."""
    v_n, a_n = vn_an(i, n)
    rhs = (C / 2.0) * (r / s) + (C / 2.0) * a_n + 100.0 * v_n
    return rhs / (1.0 + (r / s) * (i / 2.0))


def price_long_first(C, i, n, r, s):
    """§II.C — long first interest payment period."""
    v = 1.0 / (1.0 + i / 2.0)
    v_n, a_n = vn_an(i, n)
    rhs = ((C / 2.0) * (r / s)) * v + (C / 2.0) * a_n + 100.0 * v_n
    return rhs / (1.0 + (r / s) * (i / 2.0))


def price_reopening_regular(C, i, n, r, s):
    """§II.D — reopened during a regular interest period; returns (P, A)."""
    v_n, a_n = vn_an(i, n)
    a = accrued_regular(C, r, s)
    rhs = C / 2.0 + (C / 2.0) * a_n + 100.0 * v_n
    return rhs / (1.0 + (r / s) * (i / 2.0)) - a, a


def price_reopening_long_regular_portion(C, i, n, r, s, r_prime, s_dprime):
    """§II.E — reopened during the regular portion of a long first period."""
    v_n, a_n = vn_an(i, n)
    ai_prime = (r_prime / s_dprime) * (C / 2.0)
    ai = accrued_regular(C, r, s)
    a = ai_prime + ai
    rhs = ai_prime + C / 2.0 + (C / 2.0) * a_n + 100.0 * v_n
    return rhs / (1.0 + (r / s) * (i / 2.0)) - a, a


# §II.A — 8¾% 30-year bond issued 1990-05-15, due 2020-05-15, yield 8.84%.
report("§II.A price, regular first period",
       price_regular(8.75, 0.0884, 59, 184, 184), 99.057893, 5e-7)
# §II.B — 8½% 2-year note issued 1990-04-02, due 1992-03-31, yield 8.59%.
report("§II.B price, short first period",
       price_regular(8.50, 0.0859, 3, 181, 183), 99.838183, 5e-7)
# §II.C — 8½% 5-year 2-month note issued 1990-03-01, due 1995-05-15, yield 8.53%.
report("§II.C price, long first period",
       price_long_first(8.50, 0.0853, 10, 75, 181), 99.805118, 5e-7)
# §II.D — 9½% 10-year note accruing from 1985-11-15, issued 1985-11-29, yield 9.54%.
p_d, a_d = price_reopening_regular(9.50, 0.0954, 19, 167, 181)
report("§II.D accrued interest", a_d, 0.367403, 5e-7)
report("§II.D price, reopening in a regular period", p_d, 99.730918, 5e-7)
# §II.E — 10¾% 19-year 9-month bond issued 1985-07-02, reopened 1985-11-04, yield 10.47%.
p_e, a_e = price_reopening_long_regular_portion(10.75, 0.1047, 39, 103, 184, 44, 181)
report("§II.E accrued interest", a_e, 3.672798, 5e-6)
report("§II.E price, reopening in a long first period", p_e, 102.214586, 5e-6)

# ── §VI. Treasury bills ─────────────────────────────────────────────────────


def bill_price(discount_rate, r):
    """§VI.A: P = 100[1 − d·r/360]."""
    return 100.0 * (1.0 - discount_rate * r / 360.0)


def bill_investment_rate(price, r, y=365, treasury_intermediate_rounding=False):
    """§VI.D: the investment (coupon-equivalent) rate. Two branches at half a year.

    §VI.D.1 (r ≤ y/2):  i = [(100−P)/P] × (y/r)
    §VI.D.2 (r >  y/2):  P[1 + (r − y/2)(i/y)](1 + i/2) = 100, solved as a quadratic
                         with a = r/2y − 0.25, b = r/y, c = (P−100)/P.
    """
    if r <= y / 2.0:
        ratio = (100.0 - price) / price
        if treasury_intermediate_rounding:
            ratio = round(ratio, 6)  # the published example's step (2)
        return ratio * (y / r)
    a = r / (2.0 * y) - 0.25
    b = r / y
    c = (price - 100.0) / price
    return (-b + math.sqrt(b * b - 4.0 * a * c)) / (2.0 * a)


# §VI.A — bill issued 1989-11-24, due 1990-02-22, discount rate 7.610%.
report("§VI.A bill price from discount rate", bill_price(0.07610, 90), 98.097500, 5e-7)
# §VI.D.1 — cash-management bill 1990-06-01 → 1990-06-21, price 99.559444.
report("§VI.D.1 investment rate, 20-day bill",
       bill_investment_rate(99.559444, 20), 0.080756, 2e-6,
       "(published step (2) rounds (100−P)/P to 6 dp)")
report("§VI.D.1 same, with Treasury's step-(2) rounding",
       bill_investment_rate(99.559444, 20, treasury_intermediate_rounding=True),
       0.080756, 5e-7, "(published i itself carries 6 dp)")
# §VI.D.2 — 52-week bill 1990-06-07 → 1991-06-06, price 92.265000.
report("§VI.D.2 investment rate, 364-day bill",
       bill_investment_rate(92.265000, 364), 0.082373244, 5e-9)

# ── §III. inflation-indexed securities ──────────────────────────────────────


def index_ratio(ref_cpi_date, ref_cpi_issue):
    """§III: Index Ratio = Ref CPI_Date / Ref CPI_IssueDate, truncated to 5 dp."""
    return math.floor((ref_cpi_date / ref_cpi_issue) * 1e5) / 1e5


# 3⅝% 10-year TIPS issued 1998-01-15, reopened 1998-10-15.
report("§III index ratio (truncated to 5 dp)",
       index_ratio(163.29032, 161.55484), 1.01074, 0.0)

# ── inversion: price → yield, and the i = 0 special case ────────────────────


def yield_from_price(price, C, n, r, s, price_fn=price_regular):
    """Bisect; price is strictly decreasing in i over any sane bracket."""
    lo, hi = 0.0, 2.0
    for _ in range(200):
        mid = 0.5 * (lo + hi)
        if price_fn(C, mid, n, r, s) > price:
            lo = mid
        else:
            hi = mid
    return 0.5 * (lo + hi)


print("\nprice → yield inversion (bisection, 200 halvings):")
worst = 0.0
for C, n, r, s in ((8.75, 59, 184, 184), (9.50, 19, 167, 181), (2.0, 3, 90, 182), (0.125, 1, 1, 184)):
    for i_true in (1e-9, 0.0001, 0.005, 0.0442, 0.0954, 0.15, 0.40, 1.0):
        p = price_regular(C, i_true, n, r, s)
        worst = max(worst, abs(yield_from_price(p, C, n, r, s) - i_true))
print(f"  worst |yield(price(i)) − i| = {worst:.3e}  → Swift round-trip tolerance 1e-9")

v0, a0 = vn_an(0.0, 12)
print(f"  i = 0 special case: aₙ = {a0} (Treasury: 'if i = 0, then aₙ = n'), vⁿ = {v0}")
p_zero = price_regular(5.0, 0.0, 12, 184, 184)
print(f"  zero-yield price with C=5, n=12: {p_zero:.6f} (= 100 + 6.5 coupons undiscounted)")

print(f"\nfailures: {FAILURES}")
sys.exit(1 if FAILURES else 0)
