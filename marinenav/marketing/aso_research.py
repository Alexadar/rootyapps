#!/usr/bin/env python3
"""ToS-clean incumbent research for marinenav, per marketing/autoaso.md §2.1.

Uses ONLY the officially sanctioned iTunes Search API. No scraping, no
grey-market keyword tools. Throttled to well under the ~20 calls/min limit and
cached for 24 h, per §2.1.

Records, per target query, the ranked incumbents with the signal-detector fields:
userRatingCount, averageUserRating, formattedPrice, currentVersionReleaseDate.
Apple publishes no search volumes to anyone — nothing here is a volume estimate.
"""
import json, os, sys, time, hashlib, datetime as dt
from urllib.request import Request, urlopen
from urllib.parse import quote

HERE = os.path.dirname(os.path.abspath(__file__))
CACHE = os.path.join(HERE, ".cache"); os.makedirs(CACHE, exist_ok=True)
THROTTLE = 3.5          # seconds between live calls (autoaso.md §2.1)
NOW = dt.datetime(2026, 7, 26, tzinfo=dt.timezone.utc)

TARGETS = [
    "tide chart", "tide times", "tide tables", "tide predictions",
    "offline tide", "tidal current", "slack water", "tide clock",
    "marine navigation", "celestial navigation", "sight reduction",
    "magnetic declination",
]

_last = [0.0]

def search(term, limit=200, country="US"):
    key = os.path.join(CACHE, hashlib.sha1(f"{term}|{limit}|{country}".encode()).hexdigest() + ".json")
    if os.path.exists(key) and time.time() - os.path.getmtime(key) < 86_400:
        return json.load(open(key))
    wait = THROTTLE - (time.time() - _last[0])
    if wait > 0:
        time.sleep(wait)
    url = (f"https://itunes.apple.com/search?term={quote(term)}"
           f"&media=software&entity=software&country={country}&limit={limit}")
    req = Request(url, headers={"User-Agent": "rootyapps-aso-research/1.0"})
    d = json.loads(urlopen(req, timeout=45).read().decode("utf-8"))
    _last[0] = time.time()
    json.dump(d, open(key, "w"))
    return d

def months_stale(iso):
    if not iso:
        return None
    try:
        d = dt.datetime.fromisoformat(iso.replace("Z", "+00:00"))
    except ValueError:
        return None
    return (NOW - d).days / 30.44

def row(app):
    ms = months_stale(app.get("currentVersionReleaseDate"))
    return {
        "name": app.get("trackName", "")[:38],
        "id": app.get("trackId"),
        "ratings": app.get("userRatingCount") or 0,
        "stars": app.get("averageUserRating"),
        "price": app.get("formattedPrice", "?"),
        "stale_months": None if ms is None else round(ms, 1),
        "seller": (app.get("sellerName") or "")[:24],
    }

def signal(r):
    """The KerfCalc signal detector (autoaso.md §2.1)."""
    flags = []
    if r["stale_months"] is not None and r["stale_months"] > 18:
        flags.append(f"STALE {r['stale_months']:.0f}mo")
    if r["ratings"] < 30:
        flags.append("LOW-REVIEW")
    if r["stars"] is not None and r["stars"] < 3.5 and r["ratings"] >= 10:
        flags.append(f"POOR {r['stars']:.1f}")
    return ", ".join(flags)

def main():
    out = {}
    for t in TARGETS:
        d = search(t)
        results = d.get("results", [])
        rows = [row(a) for a in results[:10]]
        out[t] = {"count": d.get("resultCount", 0), "top": rows}
        print(f"\n=== {t!r}  ({d.get('resultCount', 0)} results)")
        print(f"    {'#':<3}{'app':<40}{'ratings':>9}{'★':>6}{'price':>9}{'stale':>8}  signal")
        for i, r in enumerate(rows, 1):
            stars = f"{r['stars']:.1f}" if r["stars"] is not None else "—"
            stale = f"{r['stale_months']:.0f}mo" if r["stale_months"] is not None else "—"
            print(f"    {i:<3}{r['name']:<40}{r['ratings']:>9}{stars:>6}{r['price']:>9}{stale:>8}  {signal(r)}")
    # Derived research data is a cache artifact, not a deliverable: it is
    # regenerable from this script and is gitignored with the raw responses.
    out_path = os.path.join(CACHE, "aso_research.json")
    json.dump(out, open(out_path, "w"), indent=1)
    print(f"\nwrote {out_path}")

if __name__ == "__main__":
    main()
