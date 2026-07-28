#!/usr/bin/env python3
"""Tidal CURRENT synthesis vs NOAA's published current predictions.

Same Schureman machinery as tide_full37.py, but the current-station harcon has a
different schema: constituentName / majorAmplitude (cm/s) / majorPhaseGMT / azi,
and no `speed` field -- speeds come from our own Table 2 argument coefficients.

Velocity along the major axis:  V(t) = V0_mean + SUM f_i A_i cos((V0+u)_i - G_i)

Run with conda `fantastic`.  Usage: current_full37.py [station] [bin] [year] [ndays]
"""
import json, math, os, sys, hashlib, urllib.request, datetime as dt
import numpy as np

D2R = math.pi/180.0
HERE = os.path.dirname(os.path.abspath(__file__))
CACHE = os.path.join(HERE, ".cache"); os.makedirs(CACHE, exist_ok=True)

def get(url):
    key = os.path.join(CACHE, hashlib.sha1(url.encode()).hexdigest() + ".json")
    if os.path.exists(key):
        return json.load(open(key))
    with urllib.request.urlopen(url, timeout=180) as r:
        d = json.load(r)
    json.dump(d, open(key, "w"))
    return d

src = open(os.path.join(HERE, "tide_full37.py")).read().split("STATION = sys.argv")[0]
exec(src)                                    # astro, nodal, CONST, u_of, f_of, RATE

STATION = sys.argv[1] if len(sys.argv) > 1 else "ACT1616"
BIN     = sys.argv[2] if len(sys.argv) > 2 else "1"
YEAR    = sys.argv[3] if len(sys.argv) > 3 else "2026"
NDAYS   = int(sys.argv[4]) if len(sys.argv) > 4 else 30

hc = get(f"https://api.tidesandcurrents.noaa.gov/mdapi/prod/webapi/stations/"
         f"{STATION}/harcon.json?units=metric&type=currentpredictions&bin={BIN}")
C = {c["constituentName"]: c for c in hc["HarmonicConstituents"]}
print(f"=== current station {STATION} bin {BIN}: {len(C)} constituents, units={hc['units']}")

# NOAA caps a currents_predictions request; fetch in chunks
start = dt.date(int(YEAR), 1, 1)
cp = []
d0 = start
while (d0 - start).days < NDAYS:
    d1 = min(d0 + dt.timedelta(days=29), start + dt.timedelta(days=NDAYS-1))
    cp += get("https://api.tidesandcurrents.noaa.gov/api/prod/datagetter?"
              "product=currents_predictions&application=rootyapps_oracle_research"
              f"&begin_date={d0:%Y%m%d}&end_date={d1:%Y%m%d}&station={STATION}"
              f"&bin={BIN}&time_zone=gmt&units=metric&interval=30&format=json"
              )["current_predictions"]["cp"]
    d0 = d1 + dt.timedelta(days=1)

times = [dt.datetime.strptime(r["Time"], "%Y-%m-%d %H:%M").replace(tzinfo=dt.timezone.utc)
         for r in cp]
y = np.array([float(r["Velocity_Major"]) for r in cp])
print(f"{len(y)} predictions, {times[0]:%Y-%m-%d}..{times[-1]:%Y-%m-%d}, "
      f"meanFloodDir={cp[0].get('meanFloodDir')} meanEbbDir={cp[0].get('meanEbbDir')}")

NAMES = [n for n in CONST if n in C]
rows, direct = [], []
for when in times:
    Tang, s, h, p, N, p1 = astro(when)
    ang, f = nodal(N, p)
    base = {"T": Tang, "s": s, "h": h, "p": p, "p1": p1}
    r = [1.0]; v = 0.0
    for n in NAMES:
        co, const, urule, frule = CONST[n]
        V = sum(k*base[q] for k, q in zip(co, ["T","s","h","p","p1"])) + const + u_of(urule, ang)
        fv = f_of(frule, f)
        r += [fv*math.cos(V*D2R), fv*math.sin(V*D2R)]
        v += fv*C[n]["majorAmplitude"]*math.cos((V - C[n]["majorPhaseGMT"])*D2R)
    rows.append(r); direct.append(v)

A = np.array(rows)
coef, *_ = np.linalg.lstsq(A, y, rcond=None)
direct = np.array(direct) + coef[0]          # mean (non-tidal) flow from the fit
d = direct - y
print(f"\nFULL-37 current synthesis vs NOAA published current predictions (cm/s):")
print(f"    mean flow = {coef[0]:+.2f} cm/s")
print(f"    rms = {d.std():.3f}   max = {np.abs(d).max():.3f}   bias = {d.mean():+.3f}")
print(f"    lstsq floor = {np.sqrt(((A@coef-y)**2).mean()):.3f}")
print(f"    signal rms = {y.std():.2f} cm/s   -> relative error {d.std()/y.std()*100:.2f}%")
print(f"\n{'name':<6}{'A_noaa':>10}{'A_fit':>10}{'dA':>9}{'G_noaa':>9}{'G_fit':>9}{'dG':>8}")
for k, n in enumerate(NAMES):
    a, b = coef[1+2*k], coef[2+2*k]
    if C[n]["majorAmplitude"] == 0: continue
    Afit, Gfit = math.hypot(a, b), math.degrees(math.atan2(b, a)) % 360
    dG = (Gfit - C[n]["majorPhaseGMT"] + 180) % 360 - 180
    mark = "  <== CHECK" if abs(dG) > 2.0 and C[n]["majorAmplitude"] > 1.0 else ""
    print(f"{n:<6}{C[n]['majorAmplitude']:>10.2f}{Afit:>10.2f}"
          f"{Afit-C[n]['majorAmplitude']:>+9.2f}{C[n]['majorPhaseGMT']:>9.1f}{Gfit:>9.1f}{dG:>+8.2f}{mark}")
