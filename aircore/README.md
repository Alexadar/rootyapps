# AirCore

A psychrometric and air-side engineering calculator for HVAC technicians, designers and
contractors. iPhone, iPad, Mac and Apple Watch. Everything computed on the device from published
physics — no account, no network, identical in Airplane Mode.

**App Store name: `AirCore: HVAC Calculator`.** Launch price $9.99, paid upfront, no IAP.

```
aircore/
├── PROMPT.md              the build brief
├── design/                the original SwiftUI handoff scaffold — reference only, unmodified
├── project.yml            XcodeGen → aircore.xcodeproj
├── Kits/                  every computation, as oracle-tested SPM packages
├── DesignShared/          tokens, formatting, catalogue, settings, watch transport
├── AirCore/               the iPhone / iPad / Mac app
├── AirCoreWatch/          the watch app
├── aircore*Tests/         view-model, UI and watch-crown suites
├── tools/                 the oracle fixture generator, and the icon generator
└── run_tests.sh           Kits, then iPhone + iPad + watch in parallel
```

## Running the tests

```bash
./run_tests.sh              # everything
./run_tests.sh --kits-only  # just the oracle suites, no simulator
./run_tests.sh --only ipad  # one destination
```

Throwaway `AIRC-*` simulators are created with the locale pinned to `en_US` and deleted when the
run ends. macOS is excluded on purpose — it seizes the screen — so run it deliberately:

```bash
xcodebuild -project aircore.xcodeproj -scheme aircore -destination 'platform=macOS' test
```

## The Kits, and what proves each one

A Kit ships only if its correctness can be checked against an **independent published reference**.
Every number the app displays comes through one of these.

| Kit | Covers | Oracle |
|---|---|---|
| `PsychroKit` | Hyland–Wexler saturation pressure (water **and** ice), any-two-knowns solver over 7 properties, mass-weighted mixing | **CoolProp** `HAPropsSI` (real-gas, MIT) and **IAPWS-95**, both independent of the ideal-gas relations implemented; plus published psychrometric-table anchors in IP |
| `AltitudeKit` | ASHRAE standard atmosphere | the published standard-atmosphere table, to its printed precision |
| `FluidKit` | Colebrook–White, Darcy–Weisbach | the **Moody chart**, both analytic asymptotes, and back-substitution into Colebrook itself |
| `DuctKit` | duct sizing with real roughness and density, round ⇄ rectangular | the published friction-chart equation `Δp = 0.109136 Q^1.9/D^5.02`, agreeing within 2 % |
| `HeatKit` | sensible / latent / total, solvable in any direction | the trade's own **1.08, 4840 and 4.5**, all three recovered from the SI relations at standard air |
| `FanKit` | affinity laws + density correction | exact algebra, asserted as exponents |
| `PipeKit` | Darcy **and** Hazen–Williams, velocity limits | the SI and IP forms of Hazen–Williams cross-checking each other to 2 %; published copper erosion limits |
| `UnitsKit` | IP ⇄ SI throughout | **NIST SP 811** and the exact defining relations |

`FluidKit` is the one cross-Kit dependency in the app. Colebrook–White is the same equation for air
in a duct and water in a pipe, and two copies of an implicit numerical solve would drift apart —
this repository already has a scar from that shape of duplication.

Regenerate `PsychroKit`'s fixtures with `tools/gen_psychro_fixtures.py`; do not hand-edit them.

## What the scaffold got wrong

The `design/` handoff compiles and looks right. Verifying it turned up one correctness bug and
several pieces of decoration:

- **It does not implement Hyland–Wexler.** `satPressure` is a Magnus form using over-water
  coefficients at every temperature. Error: −0.29 % at 75 °F, **+19.3 % at 0 °F**. At 20 °F / 60 %
  it reports a dew point of 8.3 °F against a true 6.9 °F. Winter outdoor air is a normal use of
  this app.
- **The duct material picker was dead.** Four materials with published roughness values, none of
  them passed to the sizing routine. Selecting flex duct changed nothing.
- **The rectangular equivalent inverted nothing** — it returned `0.85 × diameter`.
- **Mixing was CFM-weighted**, which is wrong wherever the two streams differ in density, i.e.
  exactly the case the tool exists for.
- **Nothing validated.** 150 % relative humidity returned a plausible number.
- Pipe sizing was a velocity checker; there was no head-loss calculation at all.
- The solver took one pair of knowns, not any two.

## Findings worth knowing

- **Wet bulb and enthalpy cannot be used as a pair.** Their lines on the chart are near-coincident.
  Measured: 0.05 °C of wet-bulb entry error moves the answer **5.2 °C**; 0.5 kJ/kg of enthalpy error
  moves it **16.8 °C**. The solver refuses the pair and the picker greys it out.
- **Enthalpy conversion carries a datum.** SI puts zero at 0 °C, IP at 0 °F. `Btu/lb → kJ/kg` is
  `× 2.326 + 17.88`, and dropping the offset is a **27 % error** at room temperature that looks
  entirely plausible on screen.
- **The trade's 1.08 and 1.10 are both right.** 1.08 pairs dry-air specific heat with dry-air
  density; 1.10 pairs moist-air specific heat with the same density. This app uses the specific
  heat and density of the air that is actually there.
- **Hazen–Williams runs 2–20 % above Darcy** for copper across the small-bore range, and has no
  viscosity term so it cannot see water temperature. Both methods are offered; the app always says
  which produced a number and what the other one says.
- **A `ScrollView` on watchOS eats the Digital Crown.** The crown regression test caught this; it
  is invisible in a screenshot.
- **The saturation curve has a step at 0 °C** — Hyland–Wexler changes equation there and the two
  branches disagree by 9.7 × 10⁻⁵. A saturated state at exactly freezing is therefore accepted
  within that band rather than rejected on which side of zero a root find landed.

## Scope boundary — not negotiable

**Excluded, licensed:** ASHRAE Duct Fitting Database, ACCA Manual D and Manual J, SMACNA. This app
sizes **straight duct from friction**. There is no fitting library, no equivalent length and no
total effective length. The words "Manual D", "ACCA", "ASHRAE approved", "SMACNA" and "code
compliant" appear nowhere in the UI, metadata or marketing.

**Excluded, life safety:** flue sizing, vent sizing, combustion air, gas pipe sizing. NFPA 54 /
IFGC territory where the failure mode is carbon monoxide. Nothing in the UI hints these exist.

Velocity limits are the **user's own numbers** with published defaults, never embedded code limits:
per-application velocity tables are licensed.

## The icon

The saturation curve of a psychrometric chart: dark above it, where air cannot go, lit below it,
where it can, and one state point at 24 °C / 50 % sitting on the constant-humidity line through it.

It is drawn from the physics rather than sketched — `tools/make_icon.swift` evaluates the same
Hyland–Wexler correlation `PsychroKit` ships and traces the result. Regenerate with:

```bash
swift tools/make_icon.swift
```

Do not hand-edit the PNGs. Nothing in the mark implies certification or any standards body.

## Still the owner's call

1. **Store metadata** beyond the name: subtitle, keywords, description.
2. Creating the App Store version, submitting, and setting the price. Nothing has been staged.
