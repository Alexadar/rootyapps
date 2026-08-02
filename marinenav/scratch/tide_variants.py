#!/usr/bin/env python3
"""Resolve the last ambiguous Schureman rules (M1, S1, LAM2, R2) empirically
against NOAA's published predictions. NOAA generates its predictions from exactly
the 37 published constituents, so with correct V0+u our basis spans the same space
and the least-squares floor is just the published rounding (A to 1e-3, G to 0.1 deg).

Caches NOAA responses in scratch/.cache/ so variants are cheap to try.
Run with conda `fantastic`.
"""
import json, math, os, urllib.request, datetime as dt, hashlib, itertools
import numpy as np

D2R = math.pi/180.0
CACHE = os.path.join(os.path.dirname(os.path.abspath(__file__)), ".cache")
os.makedirs(CACHE, exist_ok=True)

def get(url):
    key = os.path.join(CACHE, hashlib.sha1(url.encode()).hexdigest() + ".json")
    if os.path.exists(key):
        return json.load(open(key))
    with urllib.request.urlopen(url, timeout=180) as r:
        d = json.load(r)
    json.dump(d, open(key, "w"))
    return d

src = open(os.path.join(os.path.dirname(os.path.abspath(__file__)),
                        "tide_full37.py")).read().split("STATION = sys.argv")[0]
exec(src)                                     # astro, nodal, CONST, u_of, f_of, RATE

STATION, UNITS, Y0, NY = "9414290", "metric", 2024, 4
C = {c["name"]: c for c in
     get(f"https://api.tidesandcurrents.noaa.gov/mdapi/prod/webapi/stations/"
         f"{STATION}/harcon.json?units={UNITS}")["HarmonicConstituents"]}
datums = {d["name"]: d["value"] for d in
          get(f"https://api.tidesandcurrents.noaa.gov/mdapi/prod/webapi/stations/"
              f"{STATION}/datums.json?units={UNITS}")["datums"]}
Z0 = datums["MSL"] - datums["MLLW"]
pred = []
for yr in range(Y0, Y0+NY):
    pred += get("https://api.tidesandcurrents.noaa.gov/api/prod/datagetter?"
                "product=predictions&application=rootyapps_oracle_research"
                f"&begin_date={yr}0101&end_date={yr}1231&datum=MLLW"
                f"&station={STATION}&time_zone=gmt&units={UNITS}"
                "&interval=h&format=json")["predictions"]
times = [dt.datetime.strptime(r["t"], "%Y-%m-%d %H:%M").replace(tzinfo=dt.timezone.utc)
         for r in pred]
y = np.array([float(r["v"]) for r in pred])

# precompute astronomy once
PRE = []
for when in times:
    Tang, s, h, p, N, p1 = astro(when)
    ang, f = nodal(N, p)
    PRE.append(({"T": Tang, "s": s, "h": h, "p": p, "p1": p1}, ang, f))
print(f"{len(y)} hourly predictions cached, {times[0]:%Y-%m-%d}..{times[-1]:%Y-%m-%d}\n")

NAMES = [n for n in CONST if n in C]

def run(overrides):
    cons = dict(CONST)
    cons.update(overrides)
    rows, direct = [], []
    for base, ang, f in PRE:
        r = [1.0]; ht = Z0
        for n in NAMES:
            co, const, urule, frule = cons[n]
            V = sum(k*base[v] for k, v in zip(co, ["T","s","h","p","p1"])) + const + u_of(urule, ang)
            fv = f_of(frule, f)
            r += [fv*math.cos(V*D2R), fv*math.sin(V*D2R)]
            ht += fv*C[n]["amplitude"]*math.cos((V - C[n]["phase_GMT"])*D2R)
        rows.append(r); direct.append(ht)
    A = np.array(rows)
    coef, *_ = np.linalg.lstsq(A, y, rcond=None)
    d = np.array(direct) - y
    dG = {}
    for k, n in enumerate(NAMES):
        a, b = coef[1+2*k], coef[2+2*k]
        if C[n]["amplitude"] == 0: continue
        dG[n] = (math.degrees(math.atan2(b, a)) - C[n]["phase_GMT"] + 180) % 360 - 180
    return float(np.sqrt((d**2).mean())), float(np.abs(d).max()), dG

base_rms, base_max, base_dG = run({})
print(f"baseline: rms={base_rms:.5f} max={base_max:.5f}   "
      f"M1 dG={base_dG['M1']:+.2f}  S1 dG={base_dG['S1']:+.2f}  "
      f"LAM2 dG={base_dG['LAM2']:+.2f}  R2 dG={base_dG['R2']:+.2f}\n")

# --- M1: Schureman Table 2 note 1 has two published forms; also test Qu sign ---
print("M1 variants (V0 coeffs, const, u rule):")
for co, const, urule in [
        ((1,-1,1,1,0), -90.0, "-nu-Qu"),   # current
        ((1,-1,1,1,0), -90.0, "-nu+Qu"),
        ((1,-1,1,1,0), +90.0, "-nu-Qu"),
        ((1,-1,1,1,0), +90.0, "-nu+Qu"),
        ((1,-1,1,1,0), -90.0, "xi-nu+Q"),
        ((1,-1,1,1,0), +90.0, "xi-nu+Q"),
]:
    r, m, g = run({"M1": (co, const, urule, "M1")})
    print(f"   const={const:+6.1f} u={urule:<9} rms={r:.5f} max={m:.5f} dG(M1)={g['M1']:+7.2f}")

print("\nS1 variants:")
for co, const in [((1,0,0,0,0), 0.0), ((1,0,0,0,0), 180.0),
                  ((1,0,0,0,0), -90.0), ((1,0,0,0,0), +90.0),
                  ((1,0,-1,0,1), 0.0), ((1,0,-1,0,1), 180.0)]:
    r, m, g = run({"S1": (co, const, "zero", "one")})
    print(f"   coeffs={co} const={const:+6.1f}  rms={r:.5f} dG(S1)={g['S1']:+7.2f}")

print("\nR2 variants:")
for co, const in [((2,0,1,0,-1), 180.0), ((2,0,1,0,-1), 0.0),
                  ((2,0,1,0,-1), +90.0), ((2,0,1,0,-1), -90.0)]:
    r, m, g = run({"R2": (co, const, "zero", "one")})
    print(f"   const={const:+6.1f}  rms={r:.5f} dG(R2)={g['R2']:+7.2f}")

print("\nLAM2 variants:")
for co, const in [((2,-1,0,1,0), 180.0), ((2,-1,0,1,0), 0.0)]:
    r, m, g = run({"LAM2": (co, const, "2xi-2nu", "M2")})
    print(f"   const={const:+6.1f}  rms={r:.5f} dG(LAM2)={g['LAM2']:+7.2f}")
