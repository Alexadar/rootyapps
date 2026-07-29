#!/usr/bin/env python3
"""Pre-check: derive the IRS MACRS percentage tables from the declining-balance rules.

Oracle: irs946_2025_tableA1.csv (half-year) and irs946_2025_tableA2_q1.csv
(mid-quarter, first quarter), transcribed from IRS Pub 946 (2025) Appendix A,
p. 70-71.  See SOURCES.md §4.

The point: DepKit must *compute* MACRS (200%/150% declining balance switching to
straight line, with the placed-in-service convention), not ship the table as a
lookup.  The table is the oracle; this script measures the deviation so the Swift
tolerance is evidence-based.  Run: python3 macrs.py
"""
import csv
import math
import os
import sys

FACTOR = {3: 2.0, 5: 2.0, 7: 2.0, 10: 2.0, 15: 1.5, 20: 1.5}  # Pub 946: GDS method by class


def macrs_percentages(recovery: int, factor: float, first_year_fraction: float, dp=None):
    """Yearly recovery percentages of unadjusted basis, in percent.

    Declining balance at `factor/recovery` on the remaining basis, switching to
    straight line over the remaining recovery period when that yields more; the
    first (and mirrored last) year is shortened by the placed-in-service
    convention.  Salvage value is ignored, per MACRS.

    `dp` reproduces the IRS tables' own arithmetic: each year's percentage is
    rounded to `dp` decimals and the *rounded* figure is what reduces the running
    basis, so the rounding carries forward.  That carry is what produces the
    published alternations (7-year 8.93/8.92/8.93, 10-year …6.55/6.56/6.55) and
    makes each column sum to exactly 100.00.  With dp=None the schedule is exact.
    """
    basis = 100.0
    out = []
    elapsed = 0.0  # years already in service at the start of the current year
    year = 1
    while basis > 1e-12 and year <= recovery + 1:
        fraction = first_year_fraction if year == 1 else min(1.0, recovery - elapsed)
        remaining_life = recovery - elapsed
        db = basis * (factor / recovery) * fraction
        sl = (basis / remaining_life) * fraction if remaining_life > 0 else basis
        dep = min(max(db, sl), basis)
        if dp is not None:
            # round half up, as published tables do (Python's round() is half-even)
            scale = 10 ** dp
            dep = math.floor(dep * scale + 0.5) / scale
        out.append(dep)
        basis -= dep
        elapsed += fraction
        year += 1
    return out


# TWO documented anomalies out of the 30 published columns, both verified against a
# 200-dpi render of the source pages rather than the text extraction:
#
#  1. Table A-2 (mid-quarter, Q1), 20-year: publishes 7.000 in year 2 and 0.565 in
#     year 21 where the rounded-carry method gives 7.008 and 0.557.
#  2. Table A-3 (mid-quarter, Q2), 7-year: publishes 17.85 in year 1 and 3.34 in
#     year 8 where the method gives 17.86 and 3.33.  The exact year-1 figure is
#     2/7 x 0.625 = 17.857142…, which rounds to 17.86 by any ordinary rule — and the
#     same table's 3-year column (41.666… -> 41.67) proves the IRS is rounding, not
#     truncating.  So this column is internally inconsistent with its own siblings.
#
# In both cases the 0.01/0.008 pp is *shifted* to a later year and the column still
# totals exactly 100.00%, so nothing is lost — but nothing is silently absorbed
# either.  28 of 30 columns reproduce exactly; these two are recorded as published
# facts about the tables, and they go on the RELEASE_CHECKLIST for a human to confirm
# against a fresh copy of the publication before shipping.
KNOWN_DEVIATIONS = {
    ("irs946_2025_tableA2_q1.csv", 20): {2: (7.008, 7.000), 21: (0.557, 0.565)},
    ("irs946_2025_tableA3_q2.csv", 7): {1: (17.86, 17.85), 8: (3.33, 3.34)},
}


def check(path: str, first_year_fraction: float, label: str) -> int:
    here = os.path.dirname(os.path.abspath(__file__))
    with open(os.path.join(here, path)) as fh:
        rows = [r for r in csv.DictReader(l for l in fh if not l.startswith("#"))]

    worst_exact = 0.0
    failures = 0
    print(f"\n=== {label} ===")
    for recovery in (3, 5, 7, 10, 15, 20):
        want = [float(r[str(recovery)]) for r in rows if r[str(recovery)]]
        dp = 3 if recovery == 20 else 2
        exact = macrs_percentages(recovery, FACTOR[recovery], first_year_fraction)
        table = macrs_percentages(recovery, FACTOR[recovery], first_year_fraction, dp=dp)
        if len(table) != len(want):
            print(f"{recovery:2d}-year: LENGTH {len(table)} vs published {len(want)}")
            failures += 1
            continue
        known = KNOWN_DEVIATIONS.get((path, recovery), {})
        deviations = {
            y: (round(g, dp), w)
            for y, (g, w) in enumerate(zip(table, want), 1)
            if round(g, dp) != w
        }
        dev_table = max((abs(g - w) for g, w in zip(table, want)), default=0.0)
        dev_exact = max(abs(g - w) for g, w in zip(exact, want))
        worst_exact = max(worst_exact, dev_exact)
        ok = deviations == known
        failures += 0 if ok else 1
        if known and ok:
            print(f"{recovery:2d}-year: ok  (known published anomaly at years {sorted(known)})")
        print(
            f"{recovery:2d}-year: {'ok  ' if ok else 'FAIL'} rounded-carry Δ = {dev_table:.5f} pp"
            f" · exact-vs-published Δ = {dev_exact:.5f} pp"
            f" · Σpublished {sum(want):.2f}% Σexact {sum(exact):.6f}%"
        )
        if not ok:
            for y, (g, w) in enumerate(zip(table, want), 1):
                if abs(g - w) > 0:
                    print(f"        year {y}: rounded-carry {g:.4f} vs published {w}")
    print(f"worst exact-vs-published deviation: {worst_exact:.6f} pp")
    return failures


def furniture_example() -> int:
    """Pub 946 worked example: $10,000 of 7-year property, half-year convention."""
    published = [1429, 2449, 1749, 1249, 893, 892, 893, 446]
    pct = macrs_percentages(7, 2.0, 0.5, dp=2)
    got = [round(10000 * p / 100) for p in pct]
    ok = got == published
    print(f"\n=== Pub 946 furniture example (7-year, $10,000) ===")
    print(f"computed {got}\npublished {published}  -> {'ok' if ok else 'FAIL'}")
    return 0 if ok else 1


TABLES = [
    ("irs946_2025_tableA1.csv", 0.5, "Table A-1 — half-year convention"),
    ("irs946_2025_tableA2_q1.csv", 3.5 / 4, "Table A-2 — mid-quarter, Q1"),
    ("irs946_2025_tableA3_q2.csv", 2.5 / 4, "Table A-3 — mid-quarter, Q2"),
    ("irs946_2025_tableA4_q3.csv", 1.5 / 4, "Table A-4 — mid-quarter, Q3"),
    ("irs946_2025_tableA5_q4.csv", 0.5 / 4, "Table A-5 — mid-quarter, Q4"),
]

if __name__ == "__main__":
    failures = 0
    for path, fraction, label in TABLES:
        failures += check(path, fraction, label)
    failures += furniture_example()
    print(f"\nfailures: {failures}  (known published anomalies are counted as passes and listed above)")
    sys.exit(1 if failures else 0)
