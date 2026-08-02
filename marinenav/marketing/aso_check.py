#!/usr/bin/env python3
"""Mechanical checks on a drafted metadata set (marketing/autoaso.md §6, §6.5).

Catches, without judgement:
  * the ABBREVIATION TRAP -- a target phrase whose word is missing as a full atom;
  * duplication across name/subtitle/keywords within a locale;
  * unused characters per field;
  * cross-locale combination errors (keywords never combine across locales).

Apple auto-handles plurals of included singulars and free words ("app", the
category name, stop-words), so those are treated as covered.
"""
import re, sys

LIMITS = {"name": 30, "subtitle": 30, "keywords": 100}
FREE = {"app", "apps", "the", "a", "an", "and", "for", "of", "with", "to", "in", "&"}

def atoms(text):
    """Words a field contributes. CamelCase compounds split into parts AND whole."""
    out = set()
    for raw in re.findall(r"[A-Za-z]+", text or ""):
        out.add(raw.lower())
        parts = re.findall(r"[A-Z]?[a-z]+|[A-Z]+(?![a-z])", raw)
        if len(parts) > 1:
            out.update(p.lower() for p in parts)
    return out

def singularish(w):
    """Cheap stem so 'tides' covers 'tide' and vice versa.

    Strip 'es' only after a sibilant (boxes, churches); otherwise strip a lone
    trailing 's'. Stripping 'es' blindly turned 'tides' into 'tid' and made this
    checker report a false miss.
    """
    if w.endswith("ies") and len(w) > 4:
        return w[:-3] + "y"
    if re.search(r"(ss|ch|sh|x|z)es$", w):
        return w[:-2]
    if w.endswith("s") and not w.endswith("ss") and len(w) > 3:
        return w[:-1]
    return w

def covered(word, pool):
    w = word.lower()
    if w in FREE: return True
    stems = {singularish(p) for p in pool} | pool
    return w in pool or singularish(w) in stems

def check_locale(label, name, subtitle, keywords, targets):
    print(f"\n=== {label}")
    fields = {"name": name, "subtitle": subtitle, "keywords": keywords}
    ok = True
    for f, v in fields.items():
        n, lim = len(v), LIMITS[f]
        flag = "  <== OVER LIMIT" if n > lim else ""
        if n > lim: ok = False
        print(f"  {f:<9} {n:>3}/{lim}{flag}   {v!r}")
    if " ," in keywords or ", " in keywords:
        print("  !! keywords contain a space next to a comma — wastes characters"); ok = False

    a_name, a_sub = atoms(name), atoms(subtitle)
    a_kw = atoms(keywords)
    for x, y, lx, ly in ((a_name, a_sub, "name", "subtitle"),
                         (a_name, a_kw, "name", "keywords"),
                         (a_sub, a_kw, "subtitle", "keywords")):
        dup = {d for d in (x & y) if d not in FREE}
        if dup:
            print(f"  !! DUPLICATION {lx} ∩ {ly}: {sorted(dup)}  (wasted characters)")
            ok = False

    pool = a_name | a_sub | a_kw
    print(f"  atoms ({len(pool)}): {' '.join(sorted(pool))}")
    print(f"  {'target phrase':<26} covered?  missing")
    for t in targets:
        miss = [w for w in t.split() if not covered(w, pool)]
        status = "YES" if not miss else "NO "
        if miss: ok = False
        print(f"    {t:<26} {status}      {' '.join(miss)}")
    return ok

TARGETS = [
    "tide chart", "tide times", "tide tables", "tide predictions",
    "offline tides", "tidal currents", "slack water", "tide clock",
    "marine navigation", "celestial navigation", "sight reduction",
    "magnetic declination", "nautical almanac",
]

# ---- DRAFT (primary locale, en-US) -----------------------------------------
NAME = "Marine Nav: Tides & Currents"
SUBTITLE = "Celestial Navigation Offline"
KEYWORDS = ("sight,reduction,sextant,declination,magnetic,tidal,slack,water,"
            "chart,table,times,clock,almanac,coast")

# ---- DRAFT (secondary locale, es-MX -- must be SELF-SUFFICIENT) -------------
MX_NAME = "Tide Current Navigation"
MX_SUBTITLE = "Offline Tides Prediction"
MX_KEYWORDS = ("marine,celestial,sextant,declination,magnetic,slack,water,clock,"
               "chart,table,tidal,almanac,nautical")

if __name__ == "__main__":
    check_locale("PRIMARY  en-US", NAME, SUBTITLE, KEYWORDS, TARGETS)
    check_locale("SECONDARY  es-MX (self-sufficient: keywords never combine across locales)",
                 MX_NAME, MX_SUBTITLE, MX_KEYWORDS, TARGETS)

    # A phrase only ranks if EVERY word of it sits inside ONE locale. Report which.
    pools = {
        "en-US": atoms(NAME) | atoms(SUBTITLE) | atoms(KEYWORDS),
        "es-MX": atoms(MX_NAME) | atoms(MX_SUBTITLE) | atoms(MX_KEYWORDS),
    }
    print("\n=== CROSS-LOCALE COVERAGE (a phrase must be complete inside one locale)")
    print(f"  {'target phrase':<26} supplied by")
    gaps = []
    for t in TARGETS:
        got = [loc for loc, pool in pools.items()
               if all(covered(w, pool) for w in t.split())]
        if not got:
            gaps.append(t)
        print(f"    {t:<26} {', '.join(got) if got else 'NONE  <== GAP'}")
    print(f"\n  uncovered target phrases: {gaps if gaps else 'none'}")
