#!/usr/bin/env python3
"""Diagnostic: recover (A, G) for the 8 principal constituents by least-squares
fitting NOAA's OWN published hourly predictions with OUR equilibrium arguments,
then compare against NOAA's OWN published harmonic constants.

If our V0+u convention matched NOAA's, fitted G would equal published phase_GMT.
A constant offset across all constituents => global time-origin error.
A per-constituent offset  => a specific Schureman term is wrong.

Run with an interpreter that has numpy (conda `fantastic`).
"""
import json, math, urllib.request, datetime as dt
import numpy as np

import importlib.util, pathlib
spec = importlib.util.spec_from_file_location(
    "spike", pathlib.Path(__file__).with_name("tide_convention_spike.py"))

STATION = "9414290"
D2R = math.pi / 180.0
DAYS = 60

def get(url):
    with urllib.request.urlopen(url, timeout=60) as r:
        return json.load(r)

def astro(when):
    jd = when.timestamp() / 86400.0 + 2440587.5
    T  = (jd - 2415020.0) / 36525.0
    s  = 277.0248 + 481267.8906 * T + 0.0020 * T*T + 0.0000018 * T**3
    h  = 280.1895 +  36000.7689 * T + 0.0003 * T*T
    p  = 334.3853 +   4069.0340 * T - 0.0103 * T*T - 0.0000125 * T**3
    N  = 259.1560 -   1934.1420 * T + 0.0021 * T*T + 0.0000022 * T**3
    hour = when.hour + when.minute/60 + when.second/3600
    return 15.0 * hour + 180.0, s % 360, h % 360, p % 360, N % 360

def nodal(N_deg):
    i, w = 5.145 * D2R, 23.452 * D2R
    N = N_deg * D2R
    I = math.acos(math.cos(i)*math.cos(w) - math.sin(i)*math.sin(w)*math.cos(N))
    half_sum  = math.atan((math.cos((w-i)/2) / math.cos((w+i)/2)) * math.tan(N/2))
    half_diff = math.atan((math.sin((w-i)/2) / math.sin((w+i)/2)) * math.tan(N/2))
    xi, nu = half_sum + half_diff, half_sum - half_diff
    nu_p  = math.atan2(math.sin(2*I)*math.sin(nu), math.sin(2*I)*math.cos(nu) + 0.3347)
    nu_pp2 = math.atan2(math.sin(I)**2*math.sin(2*nu), math.sin(I)**2*math.cos(2*nu) + 0.0727)
    f = {"M2": math.cos(I/2)**4 / 0.9154, "S2": 1.0,
         "K1": math.sqrt(0.8965*math.sin(2*I)**2 + 0.6001*math.sin(2*I)*math.cos(nu) + 0.1006),
         "O1": math.sin(I)*math.cos(I/2)**2 / 0.3800, "P1": 1.0,
         "K2": math.sqrt(19.0444*math.sin(I)**4 + 2.7702*math.sin(I)**2*math.cos(2*nu) + 0.0981)}
    f["N2"] = f["M2"]; f["Q1"] = f["O1"]
    return {k: v/D2R for k, v in dict(xi=xi, nu=nu, nu_p=nu_p, nu_pp2=nu_pp2).items()}, f

def equilibrium(name, Tang, s, h, p, a):
    xi, nu, nu_p, nu_pp2 = a["xi"], a["nu"], a["nu_p"], a["nu_pp2"]
    return {"M2": 2*Tang - 2*s + 2*h + (2*xi - 2*nu),
            "S2": 2*Tang,
            "N2": 2*Tang - 3*s + 2*h + p + (2*xi - 2*nu),
            "K1": 1*Tang + h - 90.0 + (-nu_p),
            "O1": 1*Tang - 2*s + h + 90.0 + (2*xi - nu),
            "P1": 1*Tang - h + 90.0,
            "Q1": 1*Tang - 3*s + h + p + 90.0 + (2*xi - nu),
            "K2": 2*Tang + 2*h + (-2*nu_pp2)}[name]

USED = ["M2", "S2", "N2", "K1", "O1", "P1", "Q1", "K2"]

harcon = get(f"https://api.tidesandcurrents.noaa.gov/mdapi/prod/webapi/stations/"
             f"{STATION}/harcon.json?units=metric")["HarmonicConstituents"]
C = {c["name"]: c for c in harcon}

start = dt.date(2026, 3, 1)
end   = start + dt.timedelta(days=DAYS - 1)
pred = get("https://api.tidesandcurrents.noaa.gov/api/prod/datagetter?"
           f"product=predictions&application=rootyapps_oracle_research"
           f"&begin_date={start:%Y%m%d}&end_date={end:%Y%m%d}&datum=MLLW"
           f"&station={STATION}&time_zone=gmt&units=metric&interval=h&format=json")["predictions"]
print(f"fitting {len(pred)} hourly NOAA predictions over {DAYS} days\n")

rows, y = [], []
for row in pred:
    when = dt.datetime.strptime(row["t"], "%Y-%m-%d %H:%M").replace(tzinfo=dt.timezone.utc)
    Tang, s, h, p, N = astro(when)
    ang, f = nodal(N)
    r = [1.0]
    for n in USED:
        V = equilibrium(n, Tang, s, h, p, ang) * D2R
        r += [f[n]*math.cos(V), f[n]*math.sin(V)]
    rows.append(r); y.append(float(row["v"]))

A = np.array(rows); y = np.array(y)
coef, *_ = np.linalg.lstsq(A, y, rcond=None)
resid = A @ coef - y
print(f"fit rms = {np.sqrt((resid**2).mean()):.4f} m   Z0(fit) = {coef[0]:.3f} m\n")

print(f"{'name':<5}{'A_noaa':>9}{'A_fit':>9}{'dA':>8}   "
      f"{'G_noaa':>9}{'G_fit':>9}{'dG(deg)':>10}")
dGs = []
for k, n in enumerate(USED):
    a, b = coef[1 + 2*k], coef[2 + 2*k]
    Afit = math.hypot(a, b)
    Gfit = math.degrees(math.atan2(b, a)) % 360
    dG = (Gfit - C[n]["phase_GMT"] + 180) % 360 - 180
    dGs.append(dG)
    print(f"{n:<5}{C[n]['amplitude']:>9.3f}{Afit:>9.3f}{Afit-C[n]['amplitude']:>+8.3f}   "
          f"{C[n]['phase_GMT']:>9.2f}{Gfit:>9.2f}{dG:>+10.2f}")

print(f"\nmean dG = {sum(dGs)/len(dGs):+.2f} deg   spread = "
      f"{max(dGs)-min(dGs):.2f} deg")
print("\nInterpretation:")
print("  dG ~ constant for all  -> single global convention offset (time origin).")
print("  dG ~ proportional to constituent SPEED -> a fixed time shift.")
for n, dG in zip(USED, dGs):
    print(f"   {n:<4} dG={dG:+8.2f}  dG/speed = {dG/C[n]['speed']:+7.4f} h")
