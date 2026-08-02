#!/usr/bin/env python3
"""Pre-check: the three 30/360 variants against ISDA's own published examples.

Oracle: isda_30_360.csv, produced by dump_isda_xls.py from
https://www.isda.org/a/mIJEE/30-360-2006ISDADefs.xls (2006 ISDA Definitions
§4.16(f)/(g)/(h)).  See SOURCES.md §6.

These are integer day counts, so the expected residual is exactly 0 — the point
of this script is to confirm the *rules* (especially the 30E/360 (ISDA)
termination-date exception) reproduce all 22 rows before they are written in
Swift.  Run: python3 daycount.py
"""
import calendar
import csv
import datetime
import os
import sys

TERMINATION_DATE = datetime.date(2009, 2, 28)  # the Comparison sheet's own value


def is_last_of_february(d: datetime.date) -> bool:
    return d.month == 2 and d.day == calendar.monthrange(d.year, 2)[1]


def d1_d2(start: datetime.date, end: datetime.date, convention: str, termination=None):
    """Return the (D1, D2) substitutions for one convention. §4.16(f)/(g)/(h)."""
    d1, d2 = start.day, end.day
    if convention == "bond":  # 30/360, Bond Basis — §4.16(f)
        if d1 == 31:
            d1 = 30
        if d2 == 31 and start.day in (30, 31):
            d2 = 30
    elif convention == "euro":  # 30E/360, Eurobond Basis — §4.16(g)
        if d1 == 31:
            d1 = 30
        if d2 == 31:
            d2 = 30
    elif convention == "isda":  # 30E/360 (ISDA) — §4.16(h)
        if d1 == 31 or is_last_of_february(start):
            d1 = 30
        if d2 == 31 or (is_last_of_february(end) and end != termination):
            d2 = 30
    else:
        raise ValueError(convention)
    return d1, d2


def days_30_360(start, end, convention, termination=None) -> int:
    d1, d2 = d1_d2(start, end, convention, termination)
    return (end.year - start.year) * 360 + (end.month - start.month) * 30 + (d2 - d1)


def main() -> int:
    here = os.path.dirname(os.path.abspath(__file__))
    with open(os.path.join(here, "isda_30_360.csv")) as fh:
        rows = [r for r in csv.DictReader(fh)]

    failures = 0
    print(f"{'start':11} {'end':11}  bond      euro      isda      actual")
    for r in rows:
        start = datetime.date.fromisoformat(r["start"])
        end = datetime.date.fromisoformat(r["end"])
        line = [f"{r['start']:11} {r['end']:11}"]
        for conv, key in (("bond", "days_bond"), ("euro", "days_euro"), ("isda", "days_isda")):
            got = days_30_360(start, end, conv, TERMINATION_DATE)
            want = int(float(r[key]))
            ok = got == want
            failures += 0 if ok else 1
            line.append(f"{got:4d}{'  ' if ok else ' ✗'}{'' if ok else f'(want {want})'}   ")
            # also check the published D1/D2 substitutions, not just the total
            gd1, gd2 = d1_d2(start, end, conv, TERMINATION_DATE)
            wd1 = int(float(r[f"d1_{'bond' if conv == 'bond' else ('euro' if conv == 'euro' else 'isda')}"]))
            wd2 = int(float(r[f"d2_{'bond' if conv == 'bond' else ('euro' if conv == 'euro' else 'isda')}"]))
            if (gd1, gd2) != (wd1, wd2):
                failures += 1
                line.append(f"[D1/D2 {gd1}/{gd2} want {wd1}/{wd2}]")
        actual = (end - start).days
        want_actual = int(float(r["days_actual"]))
        if actual != want_actual:
            failures += 1
        line.append(f"{actual:4d}")
        print("".join(line))

    print()
    print(f"rows: {len(rows)}  failures: {failures}")
    if failures == 0:
        print("residual: 0 (exact integers) — Swift tolerance for day counts is exact equality")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
