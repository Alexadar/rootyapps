#!/usr/bin/env python3
"""Feasibility spike: can we reproduce NOAA's OWN published tide predictions from
NOAA's OWN published harmonic constituents?

This is a convention test, not a completeness test. It synthesises only the 8
principal constituents (whose Schureman equilibrium arguments and node factors we
are confident about) and compares against NOAA's published hourly predictions.

Interpretation:
  * residual small (few cm) and unbiased  -> conventions (T origin, phase sign,
    nodal f/u, datum, timezone) are RIGHT; remaining error is the 29 omitted
    minor constituents.
  * residual large or phase-shifted       -> a convention is wrong; fix before
    committing to a tolerance in PLAN.md.

Sources:
  Schureman, Manual of Harmonic Analysis and Prediction of Tides,
    USC&GS Special Publication 98 (US-gov, public domain) - Tables 2 & 6.
  NOAA CO-OPS harmonic constituents + published predictions + datums (US-gov).
"""
import json, math, urllib.request, datetime as dt

STATION = "9414290"          # San Francisco, CA
DAY     = "20260301"
D2R     = math.pi / 180.0

def get(url):
    with urllib.request.urlopen(url, timeout=40) as r:
        return json.load(r)

# ---------------------------------------------------------------- astronomy
def astro(when):
    """Schureman's mean longitudes (deg) at UTC datetime `when`.
    T = Julian centuries from 1900 Jan 0.5 UT (JD 2415020.0)."""
    jd = when.timestamp() / 86400.0 + 2440587.5
    T  = (jd - 2415020.0) / 36525.0
    s  = 277.0248 + 481267.8906 * T + 0.0020 * T*T + 0.0000018 * T**3
    h  = 280.1895 +  36000.7689 * T + 0.0003 * T*T
    p  = 334.3853 +   4069.0340 * T - 0.0103 * T*T - 0.0000125 * T**3
    N  = 259.1560 -   1934.1420 * T + 0.0021 * T*T + 0.0000022 * T**3
    # mean-solar hour angle: 180 deg at 00:00 UT
    hour = when.hour + when.minute/60 + when.second/3600
    Tang = 15.0 * hour + 180.0
    return Tang, s % 360, h % 360, p % 360, N % 360

def nodal(N_deg):
    """Schureman xi, nu, nu', 2nu'' (deg) and the node factors f."""
    i, w = 5.145 * D2R, 23.452 * D2R          # lunar orbit incl., obliquity
    N = N_deg * D2R
    cosI = math.cos(i)*math.cos(w) - math.sin(i)*math.sin(w)*math.cos(N)
    I = math.acos(cosI)
    # exact half-angle relations for xi and nu
    tan_sum  = (math.cos((w-i)/2) / math.cos((w+i)/2)) * math.tan(N/2)
    tan_diff = (math.sin((w-i)/2) / math.sin((w+i)/2)) * math.tan(N/2)
    half_sum, half_diff = math.atan(tan_sum), math.atan(tan_diff)
    xi = half_sum + half_diff          # (xi+nu)/2 + (xi-nu)/2
    nu = half_sum - half_diff
    # K1 / K2 corrections
    nu_p  = math.atan2(math.sin(2*I)*math.sin(nu),
                       math.sin(2*I)*math.cos(nu) + 0.3347)
    nu_pp2 = math.atan2(math.sin(I)**2 * math.sin(2*nu),
                        math.sin(I)**2 * math.cos(2*nu) + 0.0727)
    f = {
        "M2": math.cos(I/2)**4 / 0.9154,
        "S2": 1.0,
        "K1": math.sqrt(0.8965*math.sin(2*I)**2 + 0.6001*math.sin(2*I)*math.cos(nu) + 0.1006),
        "O1": math.sin(I)*math.cos(I/2)**2 / 0.3800,
        "P1": 1.0,
        "K2": math.sqrt(19.0444*math.sin(I)**4 + 2.7702*math.sin(I)**2*math.cos(2*nu) + 0.0981),
    }
    f["N2"] = f["M2"]
    f["Q1"] = f["O1"]
    return {k: v/D2R for k, v in
            dict(xi=xi, nu=nu, nu_p=nu_p, nu_pp2=nu_pp2).items()}, f, I/D2R

def equilibrium(name, Tang, s, h, p, ang):
    """V0+u in degrees (Schureman Table 2)."""
    xi, nu, nu_p, nu_pp2 = ang["xi"], ang["nu"], ang["nu_p"], ang["nu_pp2"]
    return {
        "M2": 2*Tang - 2*s + 2*h + (2*xi - 2*nu),
        "S2": 2*Tang,
        "N2": 2*Tang - 3*s + 2*h + p + (2*xi - 2*nu),
        "K1": 1*Tang + h - 90.0 + (-nu_p),
        "O1": 1*Tang - 2*s + h + 90.0 + (2*xi - nu),
        "P1": 1*Tang - h + 90.0,
        "Q1": 1*Tang - 3*s + h + p + 90.0 + (2*xi - nu),
        "K2": 2*Tang + 2*h + (-2*nu_pp2),
    }[name]

USED = ["M2", "S2", "N2", "K1", "O1", "P1", "Q1", "K2"]

# ---------------------------------------------------------------- data
harcon = get(f"https://api.tidesandcurrents.noaa.gov/mdapi/prod/webapi/stations/"
             f"{STATION}/harcon.json?units=metric")["HarmonicConstituents"]
datums = {d["name"]: d["value"] for d in
          get(f"https://api.tidesandcurrents.noaa.gov/mdapi/prod/webapi/stations/"
              f"{STATION}/datums.json?units=metric")["datums"]}
pred = get("https://api.tidesandcurrents.noaa.gov/api/prod/datagetter?"
           f"product=predictions&application=rootyapps_oracle_research&begin_date={DAY}"
           f"&end_date={DAY}&datum=MLLW&station={STATION}&time_zone=gmt"
           "&units=metric&interval=h&format=json")["predictions"]

C  = {c["name"]: c for c in harcon}
Z0 = datums["MSL"] - datums["MLLW"]          # MLLW-referenced mean water level
print(f"station {STATION}  Z0 = MSL-MLLW = {Z0:.3f} m   "
      f"speeds checked against NOAA's own 'speed' field:")
for n in USED:
    print(f"   {n:<3} A={C[n]['amplitude']:.3f} m  G={C[n]['phase_GMT']:7.2f}deg  "
          f"NOAA speed={C[n]['speed']}")

# ---------------------------------------------------------------- speed check
SPEEDS = {"M2": 2*15 - 2*0.54901653 + 2*0.04106864,
          "S2": 30.0,
          "N2": 2*15 - 3*0.54901653 + 2*0.04106864 + 0.00464183,
          "K1": 15 + 0.04106864,
          "O1": 15 - 2*0.54901653 + 0.04106864,
          "P1": 15 - 0.04106864,
          "Q1": 15 - 3*0.54901653 + 0.04106864 + 0.00464183,
          "K2": 30 + 2*0.04106864}
print("\nspeed residuals (our V0 derivative vs NOAA published speed):")
for n in USED:
    print(f"   {n:<3} {SPEEDS[n]-C[n]['speed']:+.3e} deg/hr")

# ---------------------------------------------------------------- synthesis
print(f"\n{'UTC':<6}{'NOAA':>9}{'ours':>9}{'resid':>9}")
resid = []
for row in pred:
    when = dt.datetime.strptime(row["t"], "%Y-%m-%d %H:%M").replace(tzinfo=dt.timezone.utc)
    Tang, s, h, p, N = astro(when)
    ang, f, I = nodal(N)
    ht = Z0
    for n in USED:
        V = equilibrium(n, Tang, s, h, p, ang)
        ht += f[n] * C[n]["amplitude"] * math.cos((V - C[n]["phase_GMT"]) * D2R)
    noaa = float(row["v"])
    resid.append(ht - noaa)
    print(f"{when:%H:%M}{noaa:>9.3f}{ht:>9.3f}{ht-noaa:>+9.3f}")

rms  = math.sqrt(sum(r*r for r in resid)/len(resid))
bias = sum(resid)/len(resid)
print(f"\nN={len(resid)}  bias={bias:+.4f} m  rms={rms:.4f} m  "
      f"max|resid|={max(abs(r) for r in resid):.4f} m")
print(f"lunar node N={N:.2f}deg  I={I:.3f}deg  f(M2)={f['M2']:.5f}  f(K1)={f['K1']:.5f}")
print("\n(29 minor constituents omitted from this spike -- their combined "
      "amplitude at this station is the expected residual floor.)")
