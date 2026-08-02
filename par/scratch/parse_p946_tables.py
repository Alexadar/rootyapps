#!/usr/bin/env python3
"""Extract the MACRS GDS percentage tables from IRS Publication 946 into CSV.

Source: IRS Publication 946 (2025), Appendix A, Tables A-1 through A-5, pp. 70-72;
https://www.irs.gov/pub/irs-pdf/p946.pdf (US government work, public domain).
Retrieved 2026-07-27.

    pdftotext -layout p946.pdf p946.txt
    python3 parse_p946_tables.py p946.txt

Mechanical transcription beats hand-typing 5 tables x 6 columns; macrs.py then
checks every extracted number against the rules that generated it.
"""
import re
import sys

TABLES = {
    "A-1": ("irs946_2025_tableA1.csv", "Half-Year Convention"),
    "A-2": ("irs946_2025_tableA2_q1.csv", "Mid-Quarter Convention / First Quarter"),
    "A-3": ("irs946_2025_tableA3_q2.csv", "Mid-Quarter Convention / Second Quarter"),
    "A-4": ("irs946_2025_tableA4_q3.csv", "Mid-Quarter Convention / Third Quarter"),
    "A-5": ("irs946_2025_tableA5_q4.csv", "Mid-Quarter Convention / Fourth Quarter"),
}
COLUMNS = ["3", "5", "7", "10", "15", "20"]


def table_start(text, name):
    """The heading that actually opens the table, not a cross-reference to it."""
    needle = f"Table {name}."
    at = -1
    while True:
        at = text.find(needle, at + 1)
        if at == -1:
            return None
        if "Depreciation rate for recovery period" in text[at:at + 1200]:
            return at


def parse(text, name):
    start = table_start(text, name)
    if start is None:
        return {}
    end = len(text)
    for other in TABLES:
        if other == name:
            continue
        here = table_start(text, other)
        if here is not None and here > start:
            end = min(end, here)
    block = text[start:end]

    rows = {}
    for line in block.splitlines():
        m = re.match(r"\s+(\d{1,2})\s+((?:\d+\.\d+%?\s*)+)$", line)
        if not m:
            continue
        year = int(m.group(1))
        values = [v.rstrip("%") for v in m.group(2).split()]
        if year in rows:  # a later table's rows, guard against overrun
            break
        rows[year] = values
    return rows


def main(path):
    text = open(path).read()
    for name, (filename, subtitle) in TABLES.items():
        rows = parse(text, name)
        if not rows:
            print(f"{name}: NOT FOUND", file=sys.stderr)
            continue
        # Longest column count tells us how many classes each row covers; rows are
        # right-aligned in the source, so map values onto the columns that still have
        # years remaining (3-yr ends at 4, 5-yr at 6, 7-yr at 8, 10-yr at 11, 15-yr at 16).
        lengths = {"3": 4, "5": 6, "7": 8, "10": 11, "15": 16, "20": 21}
        with open(filename, "w") as fh:
            fh.write(f"# IRS Publication 946 (2025), Appendix A, Table {name}: {subtitle}\n")
            fh.write("# https://www.irs.gov/pub/irs-pdf/p946.pdf - retrieved 2026-07-27\n")
            fh.write("# Extracted by parse_p946_tables.py; verified by macrs.py.\n")
            fh.write("year," + ",".join(COLUMNS) + "\n")
            for year in sorted(rows):
                active = [c for c in COLUMNS if year <= lengths[c]]
                values = rows[year]
                if len(values) != len(active):
                    print(f"{name} year {year}: {len(values)} values for {len(active)} columns",
                          file=sys.stderr)
                cells = {c: "" for c in COLUMNS}
                for column, value in zip(active, values):
                    cells[column] = value
                fh.write(str(year) + "," + ",".join(cells[c] for c in COLUMNS) + "\n")
        print(f"{name} -> {filename} ({len(rows)} years)")


if __name__ == "__main__":
    main(sys.argv[1])
