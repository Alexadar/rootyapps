#!/usr/bin/env python3
"""Schureman-authoritative synthesis vs NOAA's own published predictions.

Everything here is now traceable to Schureman, Manual of Harmonic Analysis and
Prediction of Tides, USC&GS Special Publication 98 (1958) -- US-gov, public domain
(https://tidesandcurrents.noaa.gov/publications/SpecialPubNo98.pdf):

  * Table 1 (p.163) "Fundamental astronomical data" -- mean-longitude polynomials,
    T = Julian centuries (36525 d) from Greenwich mean noon, 31 Dec 1899.
    THESE CONSTANTS REPLACE THE FROM-MEMORY ONES THAT THE 2026-07-26 DIAGNOSTIC
    CAUGHT: s was +6.587 deg wrong, h was +0.493 deg wrong.
  * Table 6 (p.173+) "Values of I, v, xi, v', 2v'' for each degree of N",
    header: "Positive when N is between 0 and 180 deg; negative when N is between
    180 and 360 deg".  Used here as an independent check on the closed forms.
  * omega = 23.452 deg, i = 5.145 deg (Table 1).

Prediction form is Parker, Tidal Analysis and Prediction, NOAA Sp. Pub. NOS
CO-OPS 3 (2007) eq. 3.1/3.3:  h(t) = H0 + SUM f_i H_i cos(a_i t + {V0+u}_i - kappa_i)

Run with conda `fantastic` (numpy).
"""
import json, math, urllib.request, datetime as dt
import numpy as np

D2R = math.pi/180.0

def get(url):
    with urllib.request.urlopen(url, timeout=90) as r:
        return json.load(r)

# ---- Schureman Table 1 (p.163), arcsec -> deg -------------------------------
def dms(d, m, s):
    return d + m/60.0 + s/3600.0

def astro(when):
    """Schureman Table 1 mean longitudes (deg). T = Julian centuries from
    Greenwich mean noon 1899-12-31 = JD 2415020.0."""
    jd = when.timestamp()/86400.0 + 2440587.5
    T  = (jd - 2415020.0)/36525.0
    # h: 279d 41' 48.04" + 129,602,768.13"T + 1.089"T^2
    h = dms(279, 41, 48.04) + (129602768.13*T + 1.089*T*T)/3600.0
    # s: 270d 26' 14.72" + (1336 rev + 1,108,411.20")T + 9.09"T^2 + 0.0068"T^3
    s = dms(270, 26, 14.72) + 1336.0*360.0*T + (1108411.20*T + 9.09*T*T + 0.0068*T**3)/3600.0
    # p: 334d 19' 40.87" + (11 rev + 392,515.94")T - 37.24"T^2 - 0.045"T^3
    p = dms(334, 19, 40.87) + 11.0*360.0*T + (392515.94*T - 37.24*T*T - 0.045*T**3)/3600.0
    # N: 259d 10' 57.12" - (5 rev + 482,912.63")T + 7.58"T^2 + 0.008"T^3
    N = dms(259, 10, 57.12) - 5.0*360.0*T + (-482912.63*T + 7.58*T*T + 0.008*T**3)/3600.0
    # p1: 281d 13' 15.0" + 6,189.03"T + 1.63"T^2 + 0.012"T^3
    p1 = dms(281, 13, 15.0) + (6189.03*T + 1.63*T*T + 0.012*T**3)/3600.0
    hour = when.hour + when.minute/60.0 + when.second/3600.0
    return 15.0*hour + 180.0, s % 360, h % 360, p % 360, N % 360, p1 % 360

# ---- Schureman nodal angles (checked against Table 6) ------------------------
OMEGA, INC = 23.452, 5.145

def nodal(N_deg):
    w, i = OMEGA*D2R, INC*D2R
    N = N_deg*D2R
    I = math.acos(math.cos(i)*math.cos(w) - math.sin(i)*math.sin(w)*math.cos(N))
    at1 = math.atan(math.cos((w-i)/2)/math.cos((w+i)/2) * math.tan(N/2))
    at2 = math.atan(math.sin((w-i)/2)/math.sin((w+i)/2) * math.tan(N/2))
    xi = -at1 - at2 + N
    xi = math.atan2(math.sin(xi), math.cos(xi))        # wrap to (-pi, pi]
    nu = at1 - at2
    nu_p   = math.atan2(math.sin(2*I)*math.sin(nu), math.sin(2*I)*math.cos(nu) + 0.3347)
    nu_pp2 = math.atan2(math.sin(I)**2*math.sin(2*nu), math.sin(I)**2*math.cos(2*nu) + 0.0727)
    f = {"M2": math.cos(I/2)**4/0.9154,
         "S2": 1.0,
         "K1": math.sqrt(0.8965*math.sin(2*I)**2 + 0.6001*math.sin(2*I)*math.cos(nu) + 0.1006),
         "O1": math.sin(I)*math.cos(I/2)**2/0.3800,
         "P1": 1.0,
         "K2": math.sqrt(19.0444*math.sin(I)**4 + 2.7702*math.sin(I)**2*math.cos(2*nu) + 0.0981)}
    f["N2"] = f["M2"]; f["Q1"] = f["O1"]
    return {k: v/D2R for k, v in
            dict(I=I, xi=xi, nu=nu, nu_p=nu_p, nu_pp2=nu_pp2).items()}, f

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

# ---- check the closed forms against Schureman Table 6 ------------------------
# Transcribed from SP-98 Table 6 (right-hand N column => negative sign per header)
TABLE6 = {  # N_deg: (I, nu, xi, nu', 2nu'')
    339: (28.31, -3.88, -3.50, -2.77, -5.87),
    336: (28.23, -4.42, -3.98, -3.15, -6.68),
    333: (28.13, -4.95, -4.46, -3.53, -7.47),
    330: (28.02, -5.48, -4.94, -3.90, -8.25),
    327: (27.90, -5.99, -5.41, -4.26, -9.00),
    324: (27.77, -6.50, -5.86, -4.62, -9.74),
    320: (27.58, -7.15, -6.46, -5.08, -10.69),
}
print("closed forms vs Schureman Table 6 (deg):")
print(f"{'N':>5}{'I err':>9}{'nu err':>9}{'xi err':>9}{'nu1 err':>9}{'2nu2 err':>10}")
worst = 0.0
for Nd, (I_t, nu_t, xi_t, nup_t, nupp_t) in sorted(TABLE6.items()):
    a, _ = nodal(Nd)
    errs = [a["I"]-I_t, a["nu"]-nu_t, a["xi"]-xi_t, a["nu_p"]-nup_t, a["nu_pp2"]-nupp_t]
    worst = max(worst, max(abs(e) for e in errs))
    print(f"{Nd:>5}" + "".join(f"{e:>+9.3f}" for e in errs[:4]) + f"{errs[4]:>+10.3f}")
print(f"max |err| vs Table 6 = {worst:.3f} deg  (table is printed to 0.01 deg)\n")

# ---- NOAA fixture -----------------------------------------------------------
STATION = "9414290"
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

rows, direct = [], []
for when in times:
    Tang, s, h, p, N, p1 = astro(when)
    ang, f = nodal(N)
    r = [1.0]; ht = Z0
    for n in USED:
        V = equilibrium(n, Tang, s, h, p, ang)
        r += [f[n]*math.cos(V*D2R), f[n]*math.sin(V*D2R)]
        ht += f[n]*C[n]["amplitude"]*math.cos((V - C[n]["phase_GMT"])*D2R)
    rows.append(r); direct.append(ht)

A = np.array(rows)
coef, *_ = np.linalg.lstsq(A, y, rcond=None)
dres = np.array(direct) - y
print(f"station {STATION}, {len(y)} hourly NOAA predictions, Z0={Z0:.3f} m")
print(f"direct synthesis (NOAA's published A,G) vs NOAA's published predictions:")
print(f"    rms={np.sqrt((dres**2).mean()):.4f} m   max={np.abs(dres).max():.4f} m   "
      f"bias={dres.mean():+.4f} m")
print(f"lstsq noise floor (8 of 37 constituents) rms={np.sqrt(((A@coef-y)**2).mean()):.4f} m\n")
print(f"{'name':<5}{'A_noaa':>9}{'A_fit':>9}{'dA':>8}{'G_noaa':>9}{'G_fit':>9}{'dG':>8}")
for k, n in enumerate(USED):
    a, b = coef[1+2*k], coef[2+2*k]
    Afit, Gfit = math.hypot(a, b), math.degrees(math.atan2(b, a)) % 360
    dG = (Gfit - C[n]["phase_GMT"] + 180) % 360 - 180
    print(f"{n:<5}{C[n]['amplitude']:>9.3f}{Afit:>9.3f}{Afit-C[n]['amplitude']:>+8.3f}"
          f"{C[n]['phase_GMT']:>9.2f}{Gfit:>9.2f}{dG:>+8.2f}")
