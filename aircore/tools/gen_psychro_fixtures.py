#!/usr/bin/env python3
"""Regenerate PsychroKit's oracle fixtures.

The fixtures in Kits/Air/PsychroKit/Tests/PsychroKitTests/ReferenceStates.swift are produced by
this script and must not be hand-edited: hand-editing an oracle turns it into a record of what the
implementation happened to print.

    python3 -m venv .venv && .venv/bin/pip install CoolProp
    .venv/bin/python tools/gen_psychro_fixtures.py

CoolProp is MIT-licensed and is used here **only at authoring time** — it is not a dependency of
the app, which ships the ideal-gas ASHRAE relations and nothing else. It earns its place as the
oracle by being a genuinely different model (real-gas, ASHRAE RP-1485) fitted by other people:
where it agrees with PsychroKit the implementation is right, and where it disagrees the difference
is the enhancement factor, which the tolerances in ReferenceStates.swift name and bound.
"""
import math

f2c = lambda f: (f - 32) / 1.8

# ASHRAE standard atmosphere, Ch. 1 eq. 3 — the same equation AltitudeKit implements.
def barometric_pressure(feet):
    return 101_325.0 * (1 - 2.25577e-5 * feet * 0.3048) ** 5.2559

SEA_LEVEL = 101_325.0
DENVER = barometric_pressure(5280)
MEXICO_CITY = barometric_pressure(7350)

# (dry bulb °F, RH %, pressure, label)
CASES = [
    (75, 50, SEA_LEVEL, "sea level"), (95, 40, SEA_LEVEL, "sea level"),
    (55, 90, SEA_LEVEL, "sea level"), (20, 60, SEA_LEVEL, "sea level (below freezing)"),
    (0, 70, SEA_LEVEL, "sea level (deep cold)"), (110, 20, SEA_LEVEL, "sea level (hot dry)"),
    (85, 5, SEA_LEVEL, "sea level (frost point below 0 °C)"),
    (60, 100, SEA_LEVEL, "sea level (saturated)"),
    (32, 100, SEA_LEVEL, "sea level (saturated at freezing)"),
    (75, 50, DENVER, "Denver"), (95, 40, DENVER, "Denver"), (55, 90, DENVER, "Denver"),
    (20, 60, DENVER, "Denver (below freezing, at altitude)"),
    (75, 50, MEXICO_CITY, "Mexico City"), (95, 40, MEXICO_CITY, "Mexico City"),
]

SATURATION_TEMPERATURES = (0.01, 5, 10, 20, 25, 30, 40, 50, 60, 80, 100)

# Mixing cases: (dry bulb °F, RH %, CFM) × 2, pressure, label
MIXES = [
    ((75, 50, 7500), (95, 40, 2500), SEA_LEVEL, "summer, sea level"),
    ((75, 50, 7500), (20, 60, 2500), SEA_LEVEL, "winter outdoor air, sea level"),
    ((75, 50, 7500), (95, 40, 2500), DENVER, "summer, Denver"),
]

CFM_TO_M3S = 0.3048 ** 3 / 60


def main():
    from CoolProp.HumidAirProp import HAPropsSI
    from CoolProp.CoolProp import PropsSI

    print(f"    static let seaLevel = {SEA_LEVEL}")
    print(f"    static let denver = {DENVER:.4f}")
    print(f"    static let mexicoCity = {MEXICO_CITY:.4f}\n")

    print("    // saturation pressure over liquid water, IAPWS-95")
    for t in SATURATION_TEMPERATURES:
        print(f"        .init(t: {t:g}, pws: {PropsSI('P', 'T', t + 273.15, 'Q', 0, 'Water'):.4f}),")

    print("\n    // moist-air states, CoolProp HAPropsSI")
    for F, R, P, label in CASES:
        t, rh, T = f2c(F), R / 100, f2c(F) + 273.15
        get = lambda key: HAPropsSI(key, 'T', T, 'P', P, 'R', rh)
        print(f'        .init(name: "{F} °F / {R} % {label}", pressure: {P:.4f},')
        print(f'              dryBulb: {t:.10f}, relativeHumidity: {rh:g},')
        print(f'              wetBulb: {get("B") - 273.15:.6f}, dewPoint: {get("D") - 273.15:.6f},')
        print(f'              humidityRatio: {get("W"):.9f}, enthalpy: {get("H") / 1000:.6f},')
        print(f'              specificVolume: {get("Vda"):.7f}),')

    print("\n    // adiabatic mixing, mass-weighted on dry air")
    for (Fa, Ra, cfmA), (Fb, Rb, cfmB), P, label in MIXES:
        streams = []
        for F, R, cfm in ((Fa, Ra, cfmA), (Fb, Rb, cfmB)):
            T, rh = f2c(F) + 273.15, R / 100
            v = HAPropsSI('Vda', 'T', T, 'P', P, 'R', rh)
            streams.append((cfm * CFM_TO_M3S / v,
                            HAPropsSI('W', 'T', T, 'P', P, 'R', rh),
                            HAPropsSI('H', 'T', T, 'P', P, 'R', rh) / 1000))
        total = sum(m for m, _, _ in streams)
        w = sum(m * w for m, w, _ in streams) / total
        h = sum(m * h for m, _, h in streams) / total
        # Dry bulb from the ideal-gas enthalpy relation, the one PsychroKit inverts.
        t = (h - 2501.0 * w) / (1.006 + 1.86 * w)
        print(f"    // {label}: W {w:.9f}  h {h:.6f}  t {t:.6f} °C")


if __name__ == "__main__":
    main()
