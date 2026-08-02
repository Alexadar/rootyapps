#!/usr/bin/env python3
"""Pre-check: Regulation Z Appendix J actuarial-method APR against all 16 published examples.

Oracle: 12 CFR part 1026, Appendix J, examples (c)(1)–(c)(6), transcribed in
SOURCES.md §2 from a 150-dpi render of the GPO print CFR (the equations and
examples are page images, not text).

General equation, Appendix J (b)(8) — the unpaid balance of the amount financed
discounted at the unit-period rate i:

    Σ_k  A_k / [ (1 + e_k·i)(1+i)^q_k ]  =  Σ_j  P_j / [ (1 + f_j·i)(1+i)^t_j ]

with the annual percentage rate I = w · i · 100.  Note the *simple* interest
factor (1 + f·i) on the leading fractional unit-period — not (1+i)^f.  Getting
that wrong is the classic Appendix J bug, and several examples below (f = 19/30,
6/15, 39/90, 4/7, 5/28, 52/60, 26/28, 12/28, 29/30) only pass with it right.

These same irregular-series examples are the IRR oracles for CashFlowKit.
Run: python3 regz_appJ.py
"""
import sys

# ── the Appendix J engine ────────────────────────────────────────────────────


def pv(amount, t, f, i):
    """Present value of one amount t full unit-periods plus fraction f away."""
    return amount / ((1.0 + f * i) * (1.0 + i) ** t)


def series(amount, count, t, f):
    """`count` equal payments starting at (t, f), one unit-period apart."""
    return [(amount, t + k, f) for k in range(count)]


def residual(i, advances, payments):
    return sum(pv(a, q, e, i) for a, q, e in advances) - sum(pv(p, t, f, i) for p, t, f in payments)


def solve_rate(advances, payments, lo=1e-12, hi=1.0):
    """Bisect for the unit-period rate. Monotone in i for a single advance."""
    f_lo, f_hi = residual(lo, advances, payments), residual(hi, advances, payments)
    if f_lo * f_hi > 0:
        raise ValueError(f"not bracketed: f({lo})={f_lo:.6g} f({hi})={f_hi:.6g}")
    for _ in range(200):
        mid = 0.5 * (lo + hi)
        f_mid = residual(mid, advances, payments)
        if f_lo * f_mid <= 0:
            hi, f_hi = mid, f_mid
        else:
            lo, f_lo = mid, f_mid
    return 0.5 * (lo + hi)


def apr(advances, payments, w):
    i = solve_rate(advances, payments)
    return 100.0 * w * i, i, residual(i, advances, payments)


# ── the published examples ───────────────────────────────────────────────────
# (label, advances, payments, unit-periods per year, published APR)
EXAMPLES = [
    # (c)(1) single advance, otherwise regular
    ("c1-i   monthly, regular first period", [(5000, 0, 0)], series(230, 24, 1, 0), 12, 9.69),
    ("c1-ii  monthly, long first period", [(6000, 0, 0)], series(200, 36, 1, 19 / 30), 12, 11.82),
    ("c1-iii semimonthly, short first period", [(5000, 0, 0)], series(219.17, 24, 0, 6 / 15), 24, 10.34),
    ("c1-iv  quarterly, long first period", [(10000, 0, 0)], series(385, 40, 1, 39 / 90), 4, 8.97),
    ("c1-v   weekly, long first period", [(500, 0, 0)], series(17.60, 30, 4, 4 / 7), 52, 14.96),
    # (c)(2) odd first payment
    ("c2-i   monthly, irregular first payment", [(5000, 0, 0)],
     [(250, 1, 0)] + series(230, 23, 2, 0), 12, 10.08),
    ("c2-ii  every 4 weeks, long first period + irregular first payment", [(400, 0, 0)],
     [(39.50, 1, 5 / 28)] + series(38.31, 11, 2, 5 / 28), 13, 28.50),
    # (c)(3) odd final payment
    ("c3-i   monthly, irregular final payment", [(5000, 0, 0)],
     series(230, 23, 1, 0) + [(280, 24, 0)], 12, 10.50),
    ("c3-ii  every 2 weeks, short first period + irregular final", [(200, 0, 0)],
     series(9.50, 19, 0, 8 / 14) + [(30, 19, 8 / 14)], 26, 12.22),
    # (c)(4) odd first and final payment
    ("c4-i   monthly, irregular first and final", [(5000, 0, 0)],
     [(250, 1, 0)] + series(230, 22, 2, 0) + [(280, 24, 0)], 12, 10.90),
    ("c4-ii  every 2 months, short first period, irregular first and final", [(8000, 0, 0)],
     [(449.36, 0, 52 / 60)] + series(465, 18, 1, 52 / 60) + [(200, 19, 52 / 60)], 6, 7.30),
    # (c)(5) single advance, single payment
    ("c5-i   term 255 days", [(1000, 0, 0)], [(1080, 1, 0)], 365 / 255, 11.45),
    ("c5-ii  term 6 months", [(1000, 0, 0)], [(1044, 1, 0)], 2, 8.80),
    ("c5-iii term 18 months, fraction in months", [(1000, 0, 0)], [(1135.19, 1, 6 / 12)], 1, 8.76),
    ("c5-iv  term exactly 2 years", [(1000, 0, 0)], [(1240, 2, 0)], 1, 11.36),
    # (c)(6) complex single advance — irregular series
    ("c6-i   skipped-payment loan", [(2135, 0, 0)],
     series(100, 9, 0, 26 / 28) + series(100, 6, 10, 12 / 28)
     + series(100, 6, 16, 26 / 28) + series(100, 3, 23, 12 / 28), 13, 12.00),
    ("c6-ii  skipped payments plus single payments", [(7350, 0, 0)],
     series(1000, 3, 6, 12 / 30) + [(2000, 12, 12 / 30)]
     + series(750, 3, 18, 12 / 30) + [(1000, 22, 29 / 30)], 12, 10.22),
]


def main() -> int:
    failures = 0
    worst = 0.0
    print(f"{'example':62} {'computed':>9} {'published':>10} {'Δ pp':>8}  residual")
    for label, advances, payments, w, published in EXAMPLES:
        got, i, res = apr(advances, payments, w)
        delta = abs(got - published)
        # Appendix J: "the annual percentage rate obtained, when rounded to 2
        # decimals, is correct" — so the test is the 2-dp rounding, half-width .005
        ok = round(got, 2) == published
        failures += 0 if ok else 1
        worst = max(worst, delta)
        print(
            f"{label:62} {got:9.4f} {published:10.2f} {delta:8.4f}  {res:+.2e}"
            f"{'' if ok else '   ✗ FAIL'}"
        )
    print()
    print(f"examples: {len(EXAMPLES)}  failures: {failures}")
    print(f"worst |computed − published| = {worst:.5f} pp (published to 2 dp, half-width 0.005)")
    print("→ Swift tolerance: 0.005 pp on the APR, i.e. the published rounding itself")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
