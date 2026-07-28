#!/usr/bin/env python3
"""Which xi convention does NOAA's prediction engine use?

The 60-day fit showed nu is correct (K1, whose u = -nu', was off by 1 deg) while
every lunar constituent carrying 2*xi was off by ~-41 deg. Three candidate signs
for xi are tested; the winner is the one that drives dG -> 0 for M2/N2/O1/Q1
simultaneously AND minimises the direct synthesis residual.

Fit window is 1 year so that K1/P1, S2/K2/T2 (separation ~183/365 days) resolve.
Run with conda `fantastic` (needs numpy).
"""
import json, math, urllib.request, datetime as dt
import numpy as np

STATION, D2R = "9414290", math.pi/180.0

def get(url):
    with urllib.request.urlopen(url, timeout=90) as r:
        return json.load(r)

def astro(when):
    jd = when.timestamp()/86400.0 + 2440587.5
    T  = (jd - 2415020.0)/36525.0
    s  = 277.0248 + 481267.8906*T + 0.0020*T*T + 0.0000018*T**3
    h  = 280.1895 +  36000.7689*T + 0.0003*T*T
    p  = 334.3853 +   4069.0340*T - 0.0103*T*T - 0.0000125*T**3
    N  = 259.1560 -   1934.1420*T + 0.0021*T*T + 0.0000022*T**3
    hour = when.hour + when.minute/60
    return 15.0*hour + 180.0, s % 360, h % 360, p % 360, N % 360

def nodal(N_deg, variant):
    i, w = 5.145*D2R, 23.452*D2R
    N = N_deg*D2R
    I = math.acos(math.cos(i)*math.cos(w) - math.sin(i)*math.sin(w)*math.cos(N))
    hs = math.atan((math.cos((w-i)/2)/math.cos((w+i)/2))*math.tan(N/2))
    hd = math.atan((math.sin((w-i)/2)/math.sin((w+i)/2))*math.tan(N/2))
    nu = hs - hd
    xi = {"A_sum": hs + hd,          # (xi+nu)/2 + (xi-nu)/2   [original guess]
          "B_pytides": N - hs - hd,  # -(e1+e2)                 [pytides sign]
          "C_negB": hs + hd - N}[variant]
    nu_p = math.atan2(math.sin(2*I)*math.sin(nu), math.sin(2*I)*math.cos(nu) + 0.3347)
    nu_pp2 = math.atan2(math.sin(I)**2*math.sin(2*nu), math.sin(I)**2*math.cos(2*nu) + 0.0727)
    f = {"M2": math.cos(I/2)**4/0.9154, "S2": 1.0,
         "K1": math.sqrt(0.8965*math.sin(2*I)**2 + 0.6001*math.sin(2*I)*math.cos(nu) + 0.1006),
         "O1": math.sin(I)*math.cos(I/2)**2/0.3800, "P1": 1.0,
         "K2": math.sqrt(19.0444*math.sin(I)**4 + 2.7702*math.sin(I)**2*math.cos(2*nu) + 0.0981)}
    f["N2"] = f["M2"]; f["Q1"] = f["O1"]
    return {k: v/D2R for k, v in dict(xi=xi, nu=nu, nu_p=nu_p, nu_pp2=nu_pp2).items()}, f

def equilibrium(name, Tang, s, h, p, a):
    xi, nu, nu_p, nu_pp2 = a["xi"], a["nu"], a["nu_p"], a["nu_pp2"]
    return {"M2": 2*Tang - 2*s + 2*h + (2*xi - 2*nu),
            "S2": 2*Tang,
            "N2": 2*Tang - 3*s + 2*h + p + (2*xi - 2*nu),
            "K1": Tang + h - 90.0 + (-nu_p),
            "O1": Tang - 2*s + h + 90.0 + (2*xi - nu),
            "P1": Tang - h + 90.0,
            "Q1": Tang - 3*s + h + p + 90.0 + (2*xi - nu),
            "K2": 2*Tang + 2*h + (-2*nu_pp2)}[name]

USED = ["M2", "S2", "N2", "K1", "O1", "P1", "Q1", "K2"]

C = {c["name"]: c for c in
     get(f"https://api.tidesandcurrents.noaa.gov/mdapi/prod/webapi/stations/"
         f"{STATION}/harcon.json?units=metric")["HarmonicConstituents"]}
datums = {d["name"]: d["value"] for d in
          get(f"https://api.tidesandcurrents.noaa.gov/mdapi/prod/webapi/stations/"
              f"{STATION}/datums.json?units=metric")["datums"]}
Z0 = datums["MSL"] - datums["MLLW"]

pred = get("https://api.tidesandcurrents.noaa.gov/api/prod/datagetter?"
           "product=predictions&application=rootyapps_oracle_research"
           "&begin_date=20260101&end_date=20261231&datum=MLLW"
           f"&station={STATION}&time_zone=gmt&units=metric&interval=h&format=json")["predictions"]
times = [dt.datetime.strptime(r["t"], "%Y-%m-%d %H:%M").replace(tzinfo=dt.timezone.utc)
         for r in pred]
y = np.array([float(r["v"]) for r in pred])
print(f"{len(y)} hourly NOAA predictions, {times[0]:%Y-%m-%d} .. {times[-1]:%Y-%m-%d}")
print(f"Z0 = MSL-MLLW = {Z0:.3f} m\n")

for variant in ("A_sum", "B_pytides", "C_negB"):
    rows, direct = [], []
    for when in times:
        Tang, s, h, p, N = astro(when)
        ang, f = nodal(N, variant)
        r = [1.0]; ht = Z0
        for n in USED:
            V = equilibrium(n, Tang, s, h, p, ang)
            r += [f[n]*math.cos(V*D2R), f[n]*math.sin(V*D2R)]
            ht += f[n]*C[n]["amplitude"]*math.cos((V - C[n]["phase_GMT"])*D2R)
        rows.append(r); direct.append(ht)
    A = np.array(rows)
    coef, *_ = np.linalg.lstsq(A, y, rcond=None)
    fit_rms = float(np.sqrt(((A@coef - y)**2).mean()))
    dres = np.array(direct) - y
    dG = []
    for k, n in enumerate(USED):
        a, b = coef[1+2*k], coef[2+2*k]
        dG.append(((math.degrees(math.atan2(b, a)) - C[n]["phase_GMT"] + 180) % 360) - 180)
    print(f"--- xi variant {variant}")
    print(f"    direct synthesis (published A,G):  rms={np.sqrt((dres**2).mean()):.4f} m  "
          f"max={np.abs(dres).max():.4f} m  bias={dres.mean():+.4f} m")
    print(f"    lstsq fit rms={fit_rms:.4f} m")
    print("    dG: " + "  ".join(f"{n}={d:+6.2f}" for n, d in zip(USED, dG)))
    print(f"    max|dG| over lunar terms (M2,N2,O1,Q1) = "
          f"{max(abs(dG[i]) for i in (0,2,4,6)):.2f} deg\n")
