#!/usr/bin/env python3
"""
Independent ground-truth oracle for kerfcalc feet-inch-fraction arithmetic (calc #1).

This is a SECOND, INDEPENDENT implementation, written with Python's exact-rational
`fractions.Fraction`. It shares no code with the Swift `Rational`/`FeetInch` types under test.
Its printed outputs are transcribed into FeetInchOracleTests.swift as the expected values, each
cited to this file. Per kerfcalc oracle discipline, the values under test are NOT authored by the
same implementation that produced them.

Run:  python3 feetinch_oracle.py
Every printed value is an EXACT fraction of inches (numerator/denominator), reduced.
"""
from fractions import Fraction as F


def parse_ft_in(feet=0, inch=0, num=0, den=1):
    """Feet-inch-fraction -> exact inches, matching a carpenter's reading."""
    return F(feet) * 12 + F(inch) + F(num, den)


def round_to_denom(x: F, d: int) -> F:
    """Nearest multiple of 1/d, ties away from zero (symmetric carpentry rounding)."""
    p = x * d                      # want nearest integer k to p, then k/d
    # round-half-away-from-zero on the rational p
    from math import floor
    fl = floor(p)
    frac = p - fl                  # 0 <= frac < 1
    if frac < F(1, 2):
        k = fl
    elif frac > F(1, 2):
        k = fl + 1
    else:                          # exactly .5 -> away from zero
        k = fl + 1 if p > 0 else fl
    return F(k, d)


def show(label, v: F):
    print(f"{label:30s} = {v.numerator}/{v.denominator}   (= {float(v):.6f} in)")


print("# ---- exact arithmetic battery (oracle: CPython fractions.Fraction) ----")
a = parse_ft_in(6, 2, 1, 2)      # 6' 2 1/2"
b = parse_ft_in(2, 7, 3, 4)      # 2' 7 3/4"
show("6'2-1/2\" + 2'7-3/4\"", a + b)     # published: = 8' 10 1/4"
show("6'2-1/2\" - 2'7-3/4\"", a - b)
show("6'2-1/2\" * 3", a * 3)
show("6'2-1/2\" / 2", a / 2)

c = parse_ft_in(12, 6, 1, 2)     # 12' 6 1/2"
d = parse_ft_in(0, 3, 3, 8)      # 3 3/8"
show("12'6-1/2\" + 3-3/8\"", c + d)
show("12'6-1/2\" - 3-3/8\"", c - d)
show("(12'6-1/2\") / (3-3/8\")", (c / d))   # pure ratio (dimensionless)

e = parse_ft_in(0, 1, 1, 3)      # 1 1/3"
show("1-1/3\" * 3", e * 3)                    # exact -> 4"
show("1-1/3\" + 1-1/3\" + 1-1/3\"", e + e + e)

f = parse_ft_in(0, 0, 1, 3)      # 1/3"
show("(1/3\") rounded to 1/16", round_to_denom(f, 16))   # 1/3 in sixteenths = 5.33.. -> 5/16
show("(1/3\") rounded to 1/32", round_to_denom(f, 32))   # -> 11/32
g = parse_ft_in(0, 0, 7, 32)     # exactly 7/32 = 3.5/16, tie
show("(7/32\") rounded to 1/16 (tie)", round_to_denom(g, 16))   # away from zero -> 4/16 = 1/4
show("(-7/32\") rounded to 1/16 (tie)", round_to_denom(-g, 16)) # -> -1/4

# A division that does not land on a clean fraction, then rounded to 1/16:
h = parse_ft_in(10, 0, 0, 1)     # 120"
show("120\" / 7 (exact)", h / 7)
show("120\" / 7 rounded to 1/16", round_to_denom(h / 7, 16))
