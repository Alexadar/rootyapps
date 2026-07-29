#!/usr/bin/env python3
"""Storypole Phase B — independently reproduce every worked example before it enters the corpus.

Nothing here is copied from a Swift implementation; this is the second, independent
implementation whose job is to prove the published numbers are reachable. Exact rationals
via fractions.Fraction, never float, except where the source itself is decimal.
"""
from fractions import Fraction as F
from decimal import Decimal, ROUND_HALF_EVEN, ROUND_HALF_UP
import sys

fails = []
def check(label, got, want, note=""):
    ok = got == want
    if not ok:
        fails.append(label)
    print(f"{'PASS' if ok else 'FAIL'}  {label}: got {got!r}, published {want!r} {note}")

print("=" * 78)
print("ORACLE 1 — NIST SP 811 §B.7.1 rounding rules (decimal digits, half-to-even tie)")
print("=" * 78)
# Rule 3 is round-half-to-even. Reproduce all four published examples verbatim.
def sig_round(value: str, digits: int) -> str:
    d = Decimal(value)
    # significant-figure rounding, half-to-even
    from decimal import Context
    return str(Context(prec=digits, rounding=ROUND_HALF_EVEN).create_decimal(d))

check("6.9749515 -> 3 sig digits", sig_round("6.9749515", 3), "6.97")
check("6.9749515 -> 2 sig digits", sig_round("6.9749515", 2), "7.0")
check("6.9749515 -> 5 sig digits", sig_round("6.9749515", 5), "6.9750")
# The two tie cases that make the rule half-to-EVEN rather than half-up:
check("6.9749515 -> 7 sig digits (tie, preceding 1 is ODD -> up)",
      sig_round("6.9749515", 7), "6.974952")
check("6.9749505 -> 7 sig digits (tie, preceding 0 is EVEN -> unchanged)",
      sig_round("6.9749505", 7), "6.974950")
# Prove half-UP would give the wrong answer on the second one -> the rules differ observably.
from decimal import Context
half_up = str(Context(prec=7, rounding=ROUND_HALF_UP).create_decimal(Decimal("6.9749505")))
print(f"      (half-UP on 6.9749505 -> {half_up}; SP 811 publishes 6.974950. The rules differ.)")

print()
print("=" * 78)
print("ORACLE 2 — NIST SP 811 §B.7.2 significant-figure conversion")
print("=" * 78)
val = Decimal("36") * Decimal("0.3048")
check("36 ft x 0.3048", str(val), "10.9728")
check("36 ft in metres, rounded to 3 sig digits", sig_round(str(val), 3), "11.0")

print()
print("=" * 78)
print("ORACLE 3 — NIST PS 20-20 App.B B1 + Table 3: inch->mm at 25.4, half-to-even tie")
print("=" * 78)
print("B1: 'Metric dimensions are calculated at 25.4 millimeters (mm) times the dressed")
print("     dimension in inches. The nearest mm is significant for dimensions greater than")
print("     1/8 inch ... if 5 followed by only zeroes, retain the digit in the unit position")
print("     if it is even or increase it one mm if it is odd.'")
print()

def ps20_mm(dressed_inch: F) -> int:
    """B1 rounding rule for dimensions > 1/8 inch: nearest mm, ties to even."""
    mm = Decimal(dressed_inch.numerator) * Decimal("25.4") / Decimal(dressed_inch.denominator)
    return int(mm.quantize(Decimal("1"), rounding=ROUND_HALF_EVEN))

# (dressed inches, published mm from PS 20-20 Table 3)
TABLE3 = [
    # NB: 3/8 in is a NOMINAL board thickness, not a dressed one -- its dressed value is
    # 5/16 in = 8 mm. Do not pair 3/8 with 8 mm; only dressed sizes are in this column.
    (F(5, 16),  8,  "5/16 in"),
    (F(7, 16),  11, "7/16 in"),
    (F(9, 16),  14, "9/16 in"),
    (F(5, 8),   16, "5/8 in"),
    (F(3, 4),   19, "3/4 in"),
    (F(1),      25, "1 in"),
    (F(5, 4),   32, "1-1/4 in"),
    (F(3, 2),   38, "1-1/2 in  (38.1 -> 38)"),
    (F(2),      51, "2 in      (50.8 -> 51)"),
    (F(5, 2),   64, "2-1/2 in  TIE 63.5, unit digit 3 is ODD  -> 64"),
    (F(3),      76, "3 in      (76.2 -> 76)"),
    (F(7, 2),   89, "3-1/2 in  (88.9 -> 89)"),
    (F(4),     102, "4 in      (101.6 -> 102)"),
    (F(9, 2),  114, "4-1/2 in  (114.3 -> 114)"),
    (F(11, 2), 140, "5-1/2 in  (139.7 -> 140)"),
    (F(13, 2), 165, "6-1/2 in  (165.1 -> 165)"),
    (F(29, 4), 184, "7-1/4 in  (184.15 -> 184)"),
    (F(15, 2), 190, "7-1/2 in  TIE 190.5, unit digit 0 is EVEN -> 190"),
    (F(33, 4), 210, "8-1/4 in  (209.55 -> 210)"),
    (F(17, 2), 216, "8-1/2 in  (215.9 -> 216)"),
    (F(37, 4), 235, "9-1/4 in  (234.95 -> 235)"),
    (F(19, 2), 241, "9-1/2 in  (241.3 -> 241)"),
    (F(41, 4), 260, "10-1/4 in (260.35 -> 260)"),
    (F(45, 4), 286, "11-1/4 in (285.75 -> 286)"),
    (F(23, 2), 292, "11-1/2 in (292.1 -> 292)"),
    (F(53, 4), 337, "13-1/4 in (336.55 -> 337)"),
    (F(27, 2), 343, "13-1/2 in (342.9 -> 343)"),
    (F(61, 4), 387, "15-1/4 in (387.35 -> 387)"),
    (F(31, 2), 394, "15-1/2 in (393.7 -> 394)"),
]
for dressed, published, note in TABLE3:
    check(f"25.4 x {dressed} in", ps20_mm(dressed), published, f"-- {note}")

print()
print("--- The two ties are the whole point: they disagree with half-away-from-zero ---")
def ps20_mm_halfup(dressed_inch: F) -> int:
    mm = Decimal(dressed_inch.numerator) * Decimal("25.4") / Decimal(dressed_inch.denominator)
    return int(mm.quantize(Decimal("1"), rounding=ROUND_HALF_UP))
for dressed, published, _ in [(F(5,2), 64, ""), (F(15,2), 190, "")]:
    he, hu = ps20_mm(dressed), ps20_mm_halfup(dressed)
    verdict = "SAME" if he == hu else "DIFFER"
    print(f"  {dressed} in -> half-even {he}, half-up {hu}  [{verdict}], PS 20 publishes {published}")

print()
print("=" * 78)
print("ORACLE 4 — PS 20-20 §2.2 board measure")
print("=" * 78)
print("'The number of board feet in a piece of lumber is obtained by multiplying the nominal")
print(" thickness in inches or fraction of an inch by the nominal width in feet by the length")
print(" in feet.'  -> BF = T_in x (W_in/12) x L_ft, exact rational.")
def board_feet(t_in: F, w_in: F, l_ft: F) -> F:
    return t_in * (w_in / 12) * l_ft
check("2x4, 8 ft", board_feet(F(2), F(4), F(8)), F(16, 3), "= 5 1/3 BF")
check("2x10, 16 ft", board_feet(F(2), F(10), F(16)), F(80, 3), "= 26 2/3 BF")
check("1x12, 10 ft", board_feet(F(1), F(12), F(10)), F(10), "= 10 BF exactly")
print("  NOTE: uses NOMINAL dimensions. PS 20-20 App.B CAUTION forbids treating board-foot")
print("        -> cubic-metre as a unit conversion, because m3 is based on DRESSED size.")

print()
print("=" * 78)
print("ORACLE 5 — exact inch/foot/yard (Fed. Reg. 59-5442, 1959; NIST SP 811 B.8)")
print("=" * 78)
check("1 in in mm", F(254, 10), F(127, 5), "exact by definition")
check("1 ft in m", F(3048, 10000), F(381, 1250), "0.3048 exact")
check("1 yd in m", F(9144, 10000), F(1143, 1250), "0.9144 exact")
check("cubic yard -> m3", round(float(F(9144,10000) ** 3), 9), 0.764554858, "SP 811 B.8 gives 7.645549E-01")
print(f"      residual vs published 7.645549E-01: {abs(float(F(9144,10000)**3) - 0.7645549):.3e}")

print()
print("=" * 78)
print("ORACLE 6 — AWG diameter (NBS Handbook 100 §2.1)")
print("=" * 78)
print("'the diameter of No. 0000 is defined as 0.4600 inch and of No. 36 as 0.0050 inch.")
print(" There are 38 sizes between ... ratio = 39th-root(92) = 1.1229322'")
ratio = (0.4600 / 0.0050) ** (1 / 39)
check("39th root of 92, to 7 dp", round(ratio, 7), 1.1229322, "HB100 prints 1.122 932 2")
def awg_d(n): return 0.005 * 92 ** ((36 - n) / 39)
for n, want in [(36, 0.0050), (0, 0.3249), (10, 0.1019)]:
    got = round(awg_d(n), 4)
    print(f"  AWG {n:>3}: d = {got:.4f} in (reference {want})")
print("  ANCHORS: AWG 36 = 0.0050 in and AWG -3 (0000) = 0.4600 in are DEFINED in HB100.")
check("AWG 36 (defined anchor)", round(awg_d(36), 4), 0.0050)
check("AWG 0000 == n=-3 (defined anchor)", round(awg_d(-3), 4), 0.4600)

print()
print("=" * 78)
print("ORACLE 7 — exact-rational invariants the whole app rests on")
print("=" * 78)
a = F(6) + F(1, 2) + F(1, 16)          # 6 9/16"
b = F(2) + F(7, 8)
check("a + b - b == a exactly", (a + b) - b, a)
check("1/3 + 1/3 + 1/3 == 1 exactly", F(1,3) + F(1,3) + F(1,3), F(1))
# The incumbent's reported subtraction defect (2021-07-10 review):
# "subtracting something ending in 11/16 from something ending in 5/8 (10/16)" -> must end 15/16
x = F(10) + F(5, 8)     # ...5/8
y = F(3) + F(11, 16)    # ...11/16
check("10 5/8 - 3 11/16 (incumbent got 13/16)", x - y, F(111, 16), "= 6 15/16, ends in 15/16")

print()
if fails:
    print(f"*** {len(fails)} FAILED: {fails}")
    sys.exit(1)
print("ALL WORKED EXAMPLES REPRODUCED.")
