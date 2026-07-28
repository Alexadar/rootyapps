#!/usr/bin/env python3
"""Full 37-constituent synthesis vs NOAA's published predictions, with a
per-constituent least-squares diagnostic that localises any remaining error.

Astronomy: Schureman SP-98 Table 1 (p.163).  Nodal angles: Table 6 (p.173+).
Arguments V and u: Table 2 (pp.164-166).  Prediction form: Parker NOS CO-OPS 3
eq. 3.1/3.3.  Ground truth: NOAA CO-OPS published predictions (US-gov, public domain).

Every V0 coefficient set below is checked against NOAA's own published `speed`
field before any synthesis runs -- that is an independent check on the Doodson
combinations (it is how the argument table is verified without trusting OCR).

Run with conda `fantastic` (numpy).
"""
import json, math, urllib.request, datetime as dt, sys
import numpy as np

D2R = math.pi/180.0

import os, hashlib
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

def dms(d, m, s): return d + m/60.0 + s/3600.0

# ---------------- Schureman Table 1 (p.163) ----------------------------------
def astro(when):
    jd = when.timestamp()/86400.0 + 2440587.5
    T  = (jd - 2415020.0)/36525.0
    h  = dms(279,41,48.04) + (129602768.13*T + 1.089*T*T)/3600.0
    s  = dms(270,26,14.72) + 1336.0*360.0*T + (1108411.20*T + 9.09*T*T + 0.0068*T**3)/3600.0
    p  = dms(334,19,40.87) + 11.0*360.0*T + (392515.94*T - 37.24*T*T - 0.045*T**3)/3600.0
    N  = dms(259,10,57.12) - 5.0*360.0*T + (-482912.63*T + 7.58*T*T + 0.008*T**3)/3600.0
    p1 = dms(281,13,15.0) + (6189.03*T + 1.63*T*T + 0.012*T**3)/3600.0
    hour = when.hour + when.minute/60.0 + when.second/3600.0
    return 15.0*hour + 180.0, s % 360, h % 360, p % 360, N % 360, p1 % 360

# hourly rates of T,s,h,p,p1 (deg/solar hour) -- used only for the speed check
RATE = {"T": 15.0,
        "s": 1336.0*360.0/(36525*24) + 1108411.20/3600.0/(36525*24),
        "h": 129602768.13/3600.0/(36525*24),
        "p": 11.0*360.0/(36525*24) + 392515.94/3600.0/(36525*24),
        "p1": 6189.03/3600.0/(36525*24)}

# ---------------- Schureman Table 6 nodal angles ------------------------------
OMEGA, INC = 23.452, 5.145

def nodal(N_deg, p_deg):
    w, i = OMEGA*D2R, INC*D2R
    N = N_deg*D2R
    I = math.acos(math.cos(i)*math.cos(w) - math.sin(i)*math.sin(w)*math.cos(N))
    at1 = math.atan(math.cos((w-i)/2)/math.cos((w+i)/2) * math.tan(N/2))
    at2 = math.atan(math.sin((w-i)/2)/math.sin((w+i)/2) * math.tan(N/2))
    xi = -at1 - at2 + N
    xi = math.atan2(math.sin(xi), math.cos(xi))
    nu = at1 - at2
    nu_p   = math.atan2(math.sin(2*I)*math.sin(nu), math.sin(2*I)*math.cos(nu) + 0.3347)
    nu_pp2 = math.atan2(math.sin(I)**2*math.sin(2*nu), math.sin(I)**2*math.cos(2*nu) + 0.0727)
    # P = mean longitude of lunar perigee reckoned from the lunar intersection
    P = p_deg*D2R - xi
    # Schureman eq. 197 / 202 / 204  (M1)
    Qa = (2.310 + 1.435*math.cos(2*P))**-0.5
    Q  = math.atan2((5*math.cos(I) - 1)*math.sin(P), (7*math.cos(I) + 1)*math.cos(P))
    Qu = P - Q
    # Schureman eq. 213 / 214  (L2)
    Ra = (1.0 - 12*math.tan(I/2)**2*math.cos(2*P) + 36*math.tan(I/2)**4)**-0.5
    Ru = math.atan2(math.sin(2*P), (1.0/math.tan(I/2)**2)/6.0 - math.cos(2*P))
    d = dict(I=I, xi=xi, nu=nu, nu_p=nu_p, nu_pp2=nu_pp2, Qu=Qu, Ru=Ru, Q=Q, P=P)
    ang = {k: v/D2R for k, v in d.items()}
    ang["Qa"], ang["Ra"] = Qa, Ra
    # node factors, Schureman eq. 73-80 / 144 / 215 / 227
    fM2  = math.cos(I/2)**4 / 0.9154
    fO1  = math.sin(I)*math.cos(I/2)**2 / 0.3800
    fK1  = math.sqrt(0.8965*math.sin(2*I)**2 + 0.6001*math.sin(2*I)*math.cos(nu) + 0.1006)
    fK2  = math.sqrt(19.0444*math.sin(I)**4 + 2.7702*math.sin(I)**2*math.cos(2*nu) + 0.0981)
    fJ1  = math.sin(2*I) / 0.7214
    fOO1 = math.sin(I)*math.sin(I/2)**2 / 0.0164
    fMm  = (2.0/3.0 - math.sin(I)**2) / 0.5021
    fMf  = math.sin(I)**2 / 0.1578
    fM3  = math.cos(I/2)**6 / 0.8758
    # Schureman eq. 197 (Qa) and eq. 213 (Ra) are both defined as inverses:
    # f(M1) = f(O1)*(1/Qa), f(L2) = f(M2)*(1/Ra). Using them the other way up made
    # each fitted amplitude ~1.8x the published one -- caught by the diagnostic.
    f = dict(M2=fM2, O1=fO1, K1=fK1, K2=fK2, J1=fJ1, OO1=fOO1,
             Mm=fMm, Mf=fMf, M3=fM3, M1=fO1/Qa, L2=fM2/Ra, one=1.0)
    return ang, f

# ---------------- Schureman Table 2: V0 coefficients, u rule, f rule ----------
# (cT, cs, ch, cp, cp1, const_deg)
CONST = {
 "M2":  ((2,-2, 2, 0,0),   0.0, "2xi-2nu",     "M2"),
 "S2":  ((2, 0, 0, 0,0),   0.0, "zero",        "one"),
 "N2":  ((2,-3, 2, 1,0),   0.0, "2xi-2nu",     "M2"),
 "K1":  ((1, 0, 1, 0,0), -90.0, "-nup",        "K1"),
 "M4":  ((4,-4, 4, 0,0),   0.0, "4xi-4nu",     "M2^2"),
 "O1":  ((1,-2, 1, 0,0), +90.0, "2xi-nu",      "O1"),
 "M6":  ((6,-6, 6, 0,0),   0.0, "6xi-6nu",     "M2^3"),
 "MK3": ((3,-2, 3, 0,0), -90.0, "2xi-2nu-nup", "M2*K1"),
 "S4":  ((4, 0, 0, 0,0),   0.0, "zero",        "one"),
 "MN4": ((4,-5, 4, 1,0),   0.0, "4xi-4nu",     "M2^2"),
 "NU2": ((2,-3, 4,-1,0),   0.0, "2xi-2nu",     "M2"),
 "S6":  ((6, 0, 0, 0,0),   0.0, "zero",        "one"),
 "MU2": ((2,-4, 4, 0,0),   0.0, "2xi-2nu",     "M2"),
 "2N2": ((2,-4, 2, 2,0),   0.0, "2xi-2nu",     "M2"),
 "OO1": ((1, 2, 1, 0,0), -90.0, "-2xi-nu",     "OO1"),
 "LAM2":((2,-1, 0, 1,0), 180.0, "2xi-2nu",     "M2"),
 "S1":  ((1, 0, 0, 0,0),   0.0, "zero",        "one"),
 "M1":  ((1,-1, 1, 1,0), -90.0, "-nu-Qu",      "M1"),
 "J1":  ((1, 1, 1,-1,0), -90.0, "-nu",         "J1"),
 "MM":  ((0, 1, 0,-1,0),   0.0, "zero",        "Mm"),
 "SSA": ((0, 0, 2, 0,0),   0.0, "zero",        "one"),
 "SA":  ((0, 0, 1, 0,0),   0.0, "zero",        "one"),
 "MSF": ((0, 2,-2, 0,0),   0.0, "zero",        "Mm"),
 "MF":  ((0, 2, 0, 0,0),   0.0, "-2xi",        "Mf"),
 "RHO": ((1,-3, 3,-1,0), +90.0, "2xi-nu",      "O1"),
 "Q1":  ((1,-3, 1, 1,0), +90.0, "2xi-nu",      "O1"),
 "T2":  ((2, 0,-1, 0,1),   0.0, "zero",        "one"),
 "R2":  ((2, 0, 1, 0,-1),180.0, "zero",        "one"),
 "2Q1": ((1,-4, 1, 2,0), +90.0, "2xi-nu",      "O1"),
 "P1":  ((1, 0,-1, 0,0), +90.0, "zero",        "one"),
 "2SM2":((2, 2,-2, 0,0),   0.0, "-2xi+2nu",    "M2"),
 "M3":  ((3,-3, 3, 0,0),   0.0, "3xi-3nu",     "M3"),
 "L2":  ((2,-1, 2,-1,0), 180.0, "2xi-2nu-Ru",  "L2"),
 "2MK3":((3,-4, 3, 0,0), +90.0, "4xi-4nu+nup", "M2^2*K1"),
 "K2":  ((2, 0, 2, 0,0),   0.0, "-2nupp",      "K2"),
 "M8":  ((8,-8, 8, 0,0),   0.0, "8xi-8nu",     "M2^4"),
 "MS4": ((4,-2, 2, 0,0),   0.0, "2xi-2nu",     "M2"),
}

def u_of(rule, a):
    xi, nu, nup, nupp, Qu, Ru = a["xi"], a["nu"], a["nu_p"], a["nu_pp2"], a["Qu"], a["Ru"]
    return {"zero": 0.0, "2xi-2nu": 2*xi-2*nu, "4xi-4nu": 4*(xi-nu), "6xi-6nu": 6*(xi-nu),
            "8xi-8nu": 8*(xi-nu), "3xi-3nu": 3*(xi-nu), "-2xi+2nu": -2*xi+2*nu,
            "2xi-nu": 2*xi-nu, "-2xi-nu": -2*xi-nu, "-nu": -nu, "-nup": -nup,
            # `nupp` already holds 2*nu'' (Schureman eq. 232), so u(K2) = -2nu'' = -nupp
            "-2nupp": -nupp,
            "-2xi": -2*xi, "-nu-Qu": -nu-Qu, "-nu+Qu": -nu+Qu,
            "xi-nu+Q": xi-nu+a["Q"], "xi-nu-Q": xi-nu-a["Q"],
            "2xi-2nu-Ru": 2*xi-2*nu-Ru, "2xi-2nu+Ru": 2*xi-2*nu+Ru,
            "2xi-2nu-nup": 2*xi-2*nu-nup, "4xi-4nu+nup": 4*(xi-nu)+nup}[rule]

def f_of(rule, f):
    return {"M2": f["M2"], "one": 1.0, "K1": f["K1"], "O1": f["O1"], "K2": f["K2"],
            "J1": f["J1"], "OO1": f["OO1"], "Mm": f["Mm"], "Mf": f["Mf"], "M3": f["M3"],
            "M1": f["M1"], "L2": f["L2"], "M2^2": f["M2"]**2, "M2^3": f["M2"]**3,
            "M2^4": f["M2"]**4, "M2*K1": f["M2"]*f["K1"], "M2^2*K1": f["M2"]**2*f["K1"]}[rule]

STATION = sys.argv[1] if len(sys.argv) > 1 else "9414290"
UNITS   = sys.argv[2] if len(sys.argv) > 2 else "metric"
YEAR    = sys.argv[3] if len(sys.argv) > 3 else "2026"

C = {c["name"]: c for c in
     get(f"https://api.tidesandcurrents.noaa.gov/mdapi/prod/webapi/stations/"
         f"{STATION}/harcon.json?units={UNITS}")["HarmonicConstituents"]}
datums = {d["name"]: d["value"] for d in
          get(f"https://api.tidesandcurrents.noaa.gov/mdapi/prod/webapi/stations/"
              f"{STATION}/datums.json?units={UNITS}")["datums"]}
Z0 = datums["MSL"] - datums["MLLW"]

# ---- independent check: our V0 coefficients vs NOAA's published speeds -------
print(f"=== station {STATION} ({UNITS}), Z0 = MSL-MLLW = {Z0:.3f}")
worst_speed, worst_name = 0.0, ""
for n, (c, _, _, _) in CONST.items():
    spd = sum(k*RATE[v] for k, v in zip(c, ["T","s","h","p","p1"]))
    d = abs(spd - C[n]["speed"])
    if d > worst_speed: worst_speed, worst_name = d, n
print(f"V0 coefficients vs NOAA published speeds: max |diff| = {worst_speed:.2e} deg/hr ({worst_name})")
if worst_speed > 1e-5:
    print("!! argument table disagrees with NOAA -- fix before trusting anything below")

NYEARS = int(sys.argv[4]) if len(sys.argv) > 4 else 1
# S1/T2/R2 beat against P1/S2 with an exactly-annual period, so a 1-year window
# cannot separate them. Concatenate consecutive years to resolve them.
pred = []
for yr in range(int(YEAR), int(YEAR) + NYEARS):
    pred += get("https://api.tidesandcurrents.noaa.gov/api/prod/datagetter?"
                "product=predictions&application=rootyapps_oracle_research"
                f"&begin_date={yr}0101&end_date={yr}1231&datum=MLLW"
                f"&station={STATION}&time_zone=gmt&units={UNITS}"
                "&interval=h&format=json")["predictions"]
times = [dt.datetime.strptime(r["t"], "%Y-%m-%d %H:%M").replace(tzinfo=dt.timezone.utc)
         for r in pred]
y = np.array([float(r["v"]) for r in pred])

NAMES = [n for n in CONST if n in C]
rows, direct = [], []
for when in times:
    Tang, s, h, p, N, p1 = astro(when)
    ang, f = nodal(N, p)
    base = {"T": Tang, "s": s, "h": h, "p": p, "p1": p1}
    r = [1.0]; ht = Z0
    for n in NAMES:
        co, const, urule, frule = CONST[n]
        V = sum(k*base[v] for k, v in zip(co, ["T","s","h","p","p1"])) + const + u_of(urule, ang)
        fv = f_of(frule, f)
        r += [fv*math.cos(V*D2R), fv*math.sin(V*D2R)]
        ht += fv*C[n]["amplitude"]*math.cos((V - C[n]["phase_GMT"])*D2R)
    rows.append(r); direct.append(ht)

A = np.array(rows)
coef, *_ = np.linalg.lstsq(A, y, rcond=None)
d = np.array(direct) - y
print(f"\n{len(y)} hourly NOAA predictions, {times[0]:%Y-%m-%d}..{times[-1]:%Y-%m-%d}")
print(f"FULL-37 direct synthesis vs NOAA published predictions:")
print(f"    rms = {np.sqrt((d**2).mean()):.4f}   max = {np.abs(d).max():.4f}   bias = {d.mean():+.4f}")
print(f"    lstsq floor = {np.sqrt(((A@coef-y)**2).mean()):.4f}")
print(f"\nper-constituent diagnostic (dG should be ~0; large dG => wrong u or V0):")
print(f"{'name':<6}{'A_noaa':>9}{'A_fit':>9}{'dA':>9}{'G_noaa':>8}{'G_fit':>8}{'dG':>8}")
flag = []
for k, n in enumerate(NAMES):
    a, b = coef[1+2*k], coef[2+2*k]
    if C[n]["amplitude"] == 0:
        continue
    Afit, Gfit = math.hypot(a, b), math.degrees(math.atan2(b, a)) % 360
    dG = (Gfit - C[n]["phase_GMT"] + 180) % 360 - 180
    dA = Afit - C[n]["amplitude"]
    mark = ""
    if abs(dG) > 2.0 and C[n]["amplitude"] > 0.005:
        mark = "  <== CHECK"; flag.append(n)
    print(f"{n:<6}{C[n]['amplitude']:>9.3f}{Afit:>9.3f}{dA:>+9.3f}"
          f"{C[n]['phase_GMT']:>8.1f}{Gfit:>8.1f}{dG:>+8.2f}{mark}")
print(f"\nflagged: {flag if flag else 'none'}")
