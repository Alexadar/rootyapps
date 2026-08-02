#!/usr/bin/env python3
"""Dump ISDA's own 30/360 calculation-examples workbook to CSV.

Source: ISDA, "Calculation examples of 30/360 and 30E/360 in the 2006 ISDA
Definitions" — https://www.isda.org/a/mIJEE/30-360-2006ISDADefs.xls
(linked from https://www.isda.org/2008/12/22/30-360-day-count-conventions/)
Retrieved 2026-07-27.

The workbook's "Comparison" sheet carries, for ~22 published date pairs, the
day count under 30/360 (Bond Basis, ISDA 2006 §4.16(f)), 30E/360 (Eurobond
Basis, §4.16(g)), 30E/360 (ISDA, §4.16(h)) and Actual — together with the D1/D2
substitutions each convention applies. Those rows are the oracle corpus for
DayCountKit; this script is the transcription mechanism, not the authority.

Usage (needs xlrd, which reads legacy .xls):
    python3 -m venv /tmp/venv && /tmp/venv/bin/pip install xlrd
    /tmp/venv/bin/python dump_isda_xls.py 30-360-2006ISDADefs.xls > isda_30_360.csv
"""
import csv
import datetime
import sys

import xlrd


def as_iso(cell, datemode):
    if cell.ctype == 3:  # XL_CELL_DATE
        return datetime.datetime(*xlrd.xldate_as_tuple(cell.value, datemode)).date().isoformat()
    return cell.value


def main(path: str) -> None:
    book = xlrd.open_workbook(path)
    sheet = book.sheet_by_name("Comparison")
    out = csv.writer(sys.stdout)
    out.writerow(
        [
            "start", "end",
            "d1_bond", "d2_bond", "days_bond",
            "d1_euro", "d2_euro", "days_euro",
            "d1_isda", "d2_isda", "days_isda",
            "days_actual",
        ]
    )
    # Rows 36..57 (0-based) of "Comparison" hold the detail table: the same date
    # pairs as the summary block above it, plus the D1/D2 each convention uses.
    for r in range(36, 58):
        row = [as_iso(sheet.cell(r, c), book.datemode) for c in range(12)]
        if not isinstance(row[0], str) or not row[0][:2].isdigit():
            continue
        out.writerow(row)


if __name__ == "__main__":
    main(sys.argv[1])
