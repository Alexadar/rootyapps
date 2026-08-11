# BUILD PROMPT — AirCore 1.0

**Start here.** Open this directory in Claude Code, enter **plan mode**, read this file top to
bottom. It assumes you know nothing about this repo or this app.

This folder currently contains this file and `design/` — a compiling SwiftUI scaffold. There is no
Xcode project yet. Your job is to turn the scaffold into a shipping app.

---

## 1. Where you are

`rootyapps`, a monorepo of standalone iOS/macOS apps by a solo developer.

```
rootyapps/
├── CLAUDE.md            monorepo rules — read it
├── marketing/           SHARED library used by every app
├── docs/                research + runbooks + this app's design brief
├── uitests.md           shared UI-test doc
├── overtonelab.swift/   COPY ITS STRUCTURE — 26 tools, one record, Kits, 4 platforms
├── storypole/           the other recent reference app
└── aircore/             ← you are here
```

**Hard rule from `CLAUDE.md`: never fork anything from `marketing/` into an app folder.** Every app
calls those scripts in place.

**`overtonelab.swift/` is your structural reference.** Same shape as this app: many tools, one
record, `project.yml` (XcodeGen), Kits as local SPM packages, iOS + iPad + Mac + Watch, catalogue
navigation, `DesignShared/ToolCatalog.swift` as the registry.

**Portfolio rules — settled, not up for debate:**
- Paid-upfront utility. **No ads, no subscription, no IAP.**
- **Oracle-first**: computational logic lives in SPM packages whose correctness is proven against
  an independent published reference. No reference → no Kit.
- **Draft and stage only.** Creating an App Store version, submitting, or changing price are the
  owner's decisions. Ask.

---

## 2. What AirCore is

**A psychrometric and air-side engineering calculator for HVAC technicians, designers and
contractors.** Everything computed from published physics, on device, offline, no account, no
network. Must behave identically in Airplane Mode.

**One app, many tools** — not four apps.

**Platforms: iPhone, iPad, Mac, Apple Watch.**

**Full reasoning, market measurement and platform intent: `../docs/DESIGN_BRIEF_hvac.md`. Read it.**

---

## 3. ⚠️ The scope boundary — read before writing a line

Two exclusion classes, both absolute. The scaffold's README repeats them; they are not optional.

### Excluded — licensed data

| Excluded | Why |
|---|---|
| **ASHRAE Duct Fitting Database** — fitting loss coefficients | licensed ASHRAE product |
| **ACCA Manual D** — fitting equivalent lengths | sold by ACCA |
| **ACCA Manual J** — load calculations | sold by ACCA; permit-path output needs their software approval |
| **SMACNA** duct construction standards | copyrighted |

**This app sizes straight duct from friction. It is not a duct *design* tool.** No fitting library,
no total-effective-length. Never use the words "Manual D", "ACCA", "ASHRAE approved", "SMACNA" or
"code compliant" anywhere in UI, metadata or marketing.

### Excluded — life safety

**Flue sizing · vent sizing · combustion air · gas pipe sizing.** NFPA 54 / IFGC territory; the
failure mode is carbon monoxide. Nothing may hint these exist.

---

## 4. What already exists in `design/`

A compiling Swift package plus per-platform views. **Read every file before planning.**

```
design/
├── Package.swift                     name "Airside", iOS 16 / macOS 13 / watchOS 9
├── README.md                         the designer's handoff notes
├── Sources/AirsideKit/               pure physics, no UI, no network
│     Units · Altitude · Psychrometrics · AirSideHeat · DuctSizing · FanLaws · PipeSizing
├── Sources/AirsideUI/                DesignSystem · PsychroChart · Components
├── Apps/iOS/                         HomeView · PsychrometricsView · DuctView
├── Apps/iPadOS/                      ChartWorkspaceView
├── Apps/macOS/                       MacContentView
├── Apps/watchOS/                     WatchView
└── Tests/AirsideKitTests/            4 starter tests
```

Palette is **"water-breeze"**, defined in `AirsideUI/DesignSystem.swift`. Correlations used:
Hyland–Wexler saturation pressure via a Magnus form; barometric pressure vs elevation for altitude.

The designer's own note: *"compiles as a starting point; wire persistence (state restoration on
backgrounding), VoiceOver labels on every computed value and chart node, and Dynamic Type before
shipping."* Those three are yours.

### ⚠️ Rename: the scaffold says "Airside", the app is **AirCore**

Rename package, targets, types and files — `AirsideKit` → `AirCoreKit`, `AirsideUI` → `AirCoreUI`.
Keep `design/` itself **unmodified** as the reference artifact; build into a fresh source tree.

---

## 5. Task A — Kits and oracles

Restructure the scaffold's single `AirsideKit` into **house-pattern Kits**, matching
`overtonelab.swift/Kits/`:

```
Kits/<Domain>/<Name>Kit/
├── Package.swift
├── Sources/<Name>Kit/*.swift
└── Tests/<Name>KitTests/*OracleTests.swift
```

Proposed split — refine it in your plan and justify any change:

| Kit | Covers | Oracle |
|---|---|---|
| **PsychroKit** | dry bulb, wet bulb, dew point, RH, humidity ratio, enthalpy, specific volume; any two known → the rest | published reference states at sea level **and** at altitude |
| **AltitudeKit** | barometric pressure vs elevation; altitude-corrected 1.08 / 4840 / 4.5 constants | standard atmosphere; Denver ≈ 0.89 sensible constant |
| **DuctKit** | Colebrook/Darcy friction sizing, velocity, round↔rect equivalent, material roughness | published friction-chart points; `De = 1.30(ab)^0.625/(a+b)^0.25` |
| **HeatKit** | Qs / Ql / Qt, solvable in any direction | hand-computed cases, both unit systems |
| **FanKit** | affinity laws + density correction | cube/square relations, exact |
| **PipeKit** | Darcy or Hazen–Williams, velocity limits | published head-loss points |
| **UnitsKit** | IP ↔ SI throughout | exact conversion factors |

### Oracle rules

**A Kit ships only if its correctness is provable against an independent published reference.**
No reference → the logic moves into app code and you say so in your report.

**Reference values are facts and fine to use as test fixtures. Do not bulk-copy a copyrighted
table** — a handful of cited reference points per Kit is what an oracle needs.

⚠️ **The scaffold's four starter tests are placeholders and their expected values are unverified.**
`testPsychroAtSeaLevel` asserts wet bulb 62.5 °F and dew point 55.1 °F at 75 °F / 50 % RH.
**Verify every one against a real published source before trusting it**, and widen coverage:

- **Both unit systems**, not just IP
- **Altitude**: sea level, Denver, and one high case — altitude is where competitors are wrong
- **Boundary conditions**: saturation (RH = 100 %), very dry air, below freezing, out-of-range input
- **Round-trip identities**: solve for wet bulb from RH, then RH back from wet bulb
- **Invalid input must fail loudly**, never return a plausible wrong number

**If a number appears on screen, a Kit must be able to prove it.** That is the product.

---

## 6. Task B — implement the design on all four platforms

Each platform is designed for its own use context. **Do not scale one layout three ways.**

### iPhone — the field tool
Crawlspace, roof, plant room. One hand, possibly gloves, possibly bright sun.
Large targets, high contrast, primary inputs in the lower half. Recent tools one tap from launch.
**State must survive backgrounding mid-calculation** — the designer flagged persistence as unwired.

### iPad — the chart workspace
`ChartWorkspaceView` is the starting point. Chart and inputs side by side, process lines visible,
multiple state points comparable.

### Mac — desk work and export
Keyboard entry, tab between fields, and **getting results out**: copy a value, copy a table, export
a state set. Should feel like a desk tool, not a phone app in a window.

### Watch — receive and convert
`WatchView` implements one crown-driven conversion. **Digital Crown is the primary input.** Keep it
to that; do not attempt the chart at this size.

### The chart is the hard part
`PsychroChart.swift` exists. A psychrometric chart is a dense 2-D nomogram. **Both directions must
work**: type values and the point moves; drag the point and values update. Neither is second-class.

### Not yet designed — ask the owner, do not invent
Dynamic Type XXXL grid layout · VoiceOver ordering for the chart · the app icon.

---

## 7. Project setup

Match `overtonelab.swift`: `project.yml` (XcodeGen) → `aircore.xcodeproj`, Kits as local SPM
packages, a `DesignShared/` with the tool catalogue and string catalog.

- `MARKETING_VERSION` starts **1.0.0**
- **`PRODUCT_NAME` must be `AirCore`.** App Review **5.2.5** rejects Apple trademarks in shipped
  names; with `GENERATE_INFOPLIST_FILE` the generator takes `CFBundleName` from `PRODUCT_NAME`.
  This has caused a real rejection in this repo — see the comment in
  `overtonelab.swift/project.yml`.
- Targets: app (iOS/iPad/Mac), watch app, unit tests, UI tests
- **Deployment target is a decision to raise in your plan.** The scaffold says iOS 16 / macOS 13 /
  watchOS 9. Nothing here needs a modern API, so a low target widens the market — but Overtone Lab
  ships at 26.0. Recommend one and say why.

---

## 8. Tests

Per `../uitests.md` and the rules behind it:

- **Test the state space** — every toggle both directions, every operator pair. The axes here are
  **IP ↔ SI**, **sea level ↔ altitude**, and **which two variables are the known pair** in the
  psychrometric solver. A dead toggle shipped once in this repo because tests only saw default state.
- UI tests run on the **Simulator**, never a physical device
- **One dedicated simulator for this app, deleted when the run ends** — never touch another app's
- In a fix loop, re-run **only** failed + new/changed tests; full suite once at the end
- Watch: crown input is scriptable via `rotateDigitalCrown(delta:)` — write the regression test
- Don't ship red tests without saying so

**Accessibility floor:** Dynamic Type throughout; VoiceOver on every computed value **and on the
chart** (state points need labels and rotor navigation — a chart invisible to VoiceOver is a failed
screen); nothing conveyed by colour alone.

---

## 9. ASO — and one measured risk to surface, not to solve

App Store name must carry a head noun: **`AirCore: HVAC Calculator`** or similar. `AirCore` alone
is the Kerf Calc mistake — that app shipped with no head noun in any indexed field and was invisible.

Measured terms in this space: `duct calculator`, `hvac calculator`, `psychrometric`.
`AirCore` itself has **zero** autocomplete presence, so the head noun does all the discovery work.

⚠️ **Surface this to the owner rather than deciding it:** measurement on 2026-08-10 found that of
132 calculator apps released since 2023, **none that were paid-upfront cleared 100 ratings** —
every new entrant that broke through was free. The intended price is $29.99–39.99 paid-upfront.
That tension is the owner's call, not yours. Build for paid-upfront; do not design an IAP.

Do not write final store metadata without the owner.

---

## 10. 🛑 Stop and ask

**Creating an App Store version, submitting for review, or changing price are the owner's
decisions.** Build, test, stage — then ask.

Also stop if:

- a Kit has no independent published reference — say so rather than writing a test that asserts the
  implementation back at itself
- a scaffold test value cannot be verified against a real source
- §6's "not yet designed" items are needed
- anything here conflicts with what the code or the physics actually supports — flag it, don't
  quietly design around it

---

## 11. Deliver a plan first

Before code: the Kit list with each oracle and its cited reference; which scaffold test values you
verified and which you could not; the screen list per platform; project and target layout; the
deployment-target recommendation; the test matrix including the IP/SI and altitude axes; and every
open question needing the owner's answer.
