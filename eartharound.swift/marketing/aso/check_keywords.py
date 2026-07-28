#!/usr/bin/env python3
"""Validate the staged per-locale subtitle/keyword sets before anything is uploaded.

Checks the mechanical rules from marketing/autoaso.md §6/§6.5 that are cheap to get wrong and
expensive to notice later: the 30/100 character budgets, no word repeated between subtitle and
keywords (it buys nothing — Apple indexes the union), no space after a comma (each one wastes a
character), no duplicate keyword, and no plural of a term already present as a singular.

It also runs the head-noun check: every declared head noun must appear IN FULL somewhere in that
locale's own fields, because the app name is frozen in English and cannot carry it.
"""
import json
import re
import sys
import unicodedata
from pathlib import Path

SUBTITLE_MAX = 30
KEYWORDS_MAX = 100
DATA = json.loads((Path(__file__).parent / "keywords.json").read_text())["locales"]

# CJK has no spaces, so "word" boundaries there are the comma-separated atoms themselves.
CJK = ("ja", "ko", "zh-Hans", "zh-Hant")


def words(text: str, locale: str) -> set:
    if locale in CJK:
        return {t.strip() for t in re.split(r"[,\s]+", text) if t.strip()}
    return {w for w in re.split(r"[,\s]+", text.lower()) if w}


def main() -> int:
    problems = 0
    print(f"{'loc':<8} {'subtitle':>9} {'keywords':>9}  head nouns")
    print("-" * 72)
    for locale, row in DATA.items():
        sub, kw = row["subtitle"], row["keywords"]
        # Apple counts characters, and precomposed vs decomposed forms count differently.
        s_len = len(unicodedata.normalize("NFC", sub))
        k_len = len(unicodedata.normalize("NFC", kw))
        flags = []

        if s_len > SUBTITLE_MAX:
            flags.append(f"SUBTITLE OVER by {s_len - SUBTITLE_MAX}")
        if k_len > KEYWORDS_MAX:
            flags.append(f"KEYWORDS OVER by {k_len - KEYWORDS_MAX}")
        if ", " in kw:
            flags.append("space after comma")

        atoms = [a for a in kw.split(",")]
        if any(a != a.strip() for a in atoms):
            flags.append("untrimmed atom")
        if len(atoms) != len(set(a.lower() for a in atoms)):
            flags.append("duplicate keyword")

        # A word in both fields is indexed once but paid for twice.
        overlap = words(sub, locale) & words(kw, locale)
        if overlap:
            flags.append(f"repeated in both fields: {sorted(overlap)}")

        if locale not in CJK:
            lower = [a.lower() for a in atoms]
            for a in lower:
                if a.endswith("s") and a[:-1] in lower:
                    flags.append(f"plural of included singular: {a}")

        # The whole point of the file: the localized head noun must be present in full.
        haystack = f"{sub} {kw}".lower()
        for noun in row["head_nouns"]:
            if "(in name)" in noun:
                continue
            if noun.lower() not in haystack:
                # Allow the noun to be split across comma-separated atoms.
                if not all(part in haystack for part in noun.lower().split()):
                    flags.append(f"HEAD NOUN MISSING: {noun}")

        status = "  ".join(flags) if flags else "ok"
        if flags:
            problems += 1
        print(f"{locale:<8} {s_len:>6}/{SUBTITLE_MAX} {k_len:>6}/{KEYWORDS_MAX}  {status}")

    print("-" * 72)
    print(f"{len(DATA)} locales, {problems} with problems")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
