# Calculators — offline Liquid Glass calculator apps

A family of single-purpose, **offline** (no network, no account, no analytics) iOS-first universal SwiftUI apps. Each: pure math in a `<App>Kit` SPM package + a Liquid Glass UI, modeled on `../ephemeris.swift` but re-implemented. Correctness is validated against **external oracles** — see [`VALIDATION.md`](VALIDATION.md). Per-app detail lives in each folder's `PLAN.md`. Master plan: `~/.claude/plans/…calculators…md`.

Bundle ids: `oleksandr.aisixteen.<slug>` · Team `LSKNNBG94G` · iOS/macOS 26 · one-time or freemium, **no subscriptions**.

| App | Slug | What it calculates | For whom | Status |
|---|---|---|---|---|
| **Nightfield** | nightfield | Deep-sky astrophoto planner: astro-dark window, Moon rise/set + illumination, NPF sharp-star exposure, FOV/sampling, sub-exposure & integration/SNR | Astrophotographers | ✅ built (22 tests green · runs on sim · screenshots · store-ready, not uploaded) |
| **Tideline** | tideline | Offline worldwide tide & current prediction from harmonic constituents; highs/lows, day/week tables | Boaters, anglers, surfers | ✅ built (8 tests green · runs on sim · screenshots · sample data — needs real NOAA constituents before release) |
| **Intercept** | intercept | Celestial navigation: sight reduction (Marcq St-Hilaire intercept), almanac, sextant corrections, running fix | Offshore sailors, students | ✅ built (11 tests green · runs on sim · screenshots · needs almanac oracle + stars before release) |
| **Traverse** | traverse | Surveying COGO: inverse/forward, traverse + Bowditch balancing, curves, resection, area; UTM/MGRS ↔ lat/long | Surveyors, civil engineers | ✅ built (10 tests green · runs on sim · screenshots · UTM matches real-world · needs textbook-traverse oracle + MGRS) |
| **Swarf** | swarf | Machinist shop math: feeds & speeds (SFM/RPM/chipload/MRR/HP, chip-thinning), thread/tap drills, bolt-circle, sine-bar, true position | Machinists, CNC programmers | ✅ built (10 tests green · runs on sim · screenshots · needs material DB + more MH oracles) |
| **Skywave** | skywave | RF/ham toolkit: link budget (Friis), Fresnel zones, antenna dimensions, coax loss, microstrip impedance, VSWR, dBm↔W | RF engineers, ham operators | ✅ built (10 tests green · runs on sim · screenshots · real-world accurate · needs Pozar oracle + coax DB) |
| **Farfield** | farfield | NEC2 antenna modeling: wire geometry → radiation pattern, impedance, SWR (public-domain NEC2 core; not xnec2c) | Antenna designers | 📋 planned (high effort) |
| **Apogee** | apogee | Model-rocketry design & flight sim: Barrowman stability (CP/CG), altitude/velocity, recovery descent; ThrustCurve motor data | Rocketry hobbyists, educators | 📋 planned |
| **Kerf** | kerf | Woodworking math: board-feet, compound miter/crown (spring angle), segmented turning, wood movement, shelf sag | Woodworkers | 📋 planned |
| **Gauge** | gauge | Knitting/textile math: gauge conversion, pattern grading, increase/decrease shaping schedules, yardage, short-rows | Knitters, crocheters | 📋 planned |
| **Superheat** | superheat | HVAC field toolkit: psychrometrics, superheat/subcool targets, refrigerant P-T, duct friction/sizing, static pressure | HVAC techs | 📋 planned |
| **Parcel** | parcel | Meteorology sounding analysis: CAPE/CIN/LI/LCL/LFC/EL, hodograph/SRH, precipitable water (user-entered sounding) | Storm chasers, forecasters, students | 📋 planned |
| **Thiele** | thiele | Loudspeaker design: Thiele-Small params, sealed/ported box (Vb/Fb/port), response, crossover, room modes/RT60 | Audio DIYers | 📋 planned |
| **Payoff** | payoff | Options analytics: Black-Scholes + Greeks, implied-vol solve, binomial (American), multi-leg payoff/breakeven | Options traders | ✅ built (8 tests green · UI on sim · screenshots · not uploaded) |

**Legend:** 🔨 building · 📋 planned · ✅ built (tests green + runs on sim + screenshots + store-ready, **not uploaded**).

Build order = table order (Nightfield first). Each app is built end-to-end then left for the user to validate; no App Store upload happens automatically.

## ✅ Consolidation — Music category → Overtone Lab (DONE)
To avoid App Store Guideline 4.3 (many thin single-purpose apps), the **10 music-category tools** were merged into one app at repo root: **`/overtonelab.swift/`** ("Overtone Lab"), organized by function into 4 sections (Tuning / Acoustics / Signal / Design). Each tool's `*Kit` (math + oracle tests + fixtures) and glass-card views were copied in verbatim; all 10 oracle suites pass from the merged tree; builds on sim; screenshots done (visual design to be redone).

**The 10 standalone source folders have been DELETED** (verified fully ported first — Kit trees byte-identical, views identical modulo intended renames):
`{sabine,bernoulli,butterworth,webster,partch,comma,mersenne,fletcher,benchmark,thiele}.swift` → now live only inside `overtonelab.swift/`.
(Utilities & Navigation groupings TBD; the 3 singletons — Payoff, Gauge, Nightfield — stay standalone.)

**Expanded to 20 tools / 6 sections** (competitor gap-fill vs Audiofile Calc — all oracle-tested from cited docs): added **Timing** (Tempo, Delay, SMPTE Timecode, Pitch) and **Utility** (Levels/dB, File/Nyquist, Pan) sections, plus **Formant** & **SPL** (Acoustics) and **Passive** RC/LC (Signal). 6 new Kits (TimingKit, PitchKit, AudioUtilKit, FormantKit, SPLKit, PassiveKit), all `swift test` green against pinned oracles (¼@120=500 ms, A4=440, +6.02 dB, 16-bit=98.09 dB, drop-frame 1 h=107892, formants 500/1500/2500).

## Beyond the original 14 — oracle-validated Kits + UI status
Music/technical apps built after the oracle-first pivot (each: `<App>Kit` validated against an external oracle, gitignored fixtures, fail-loud tests):
- ✅ **Payoff** (options) — Kit + UI, on sim, screenshots.
- ✅ **Comma** (microtonal tuning) — Kit (Scala oracle) + UI, on sim, screenshots.
- ✅ **Sabine** (room acoustics — Sabine/Eyring RT60, Schroeder, modes) — Kit + UI, on sim, screenshots.
- ✅ **Bernoulli** (pipe/air-column resonance, end correction) — Kit + UI, on sim, screenshots.
- ✅ **Butterworth** (filter + Linkwitz-Riley crossover response) — Kit + UI, on sim, screenshots.
- ✅ **Webster** (exponential horn cutoff + Helmholtz resonance) — Kit + UI, on sim, screenshots.
- ✅ **Partch** (just intonation — cents, nearest just ratio, Tenney) — Kit + UI, on sim, screenshots.
- ✅ **Deviation** (magnetic declination — official WMM, COF bundled) — Kit (0.0007 nT vs 100 pts) + UI, on sim, screenshots.
- ✅ **Syzygy** (moon phase + next new/full + eclipse seasons) — Kit + UI (matches published lunar calendar), on sim, screenshots.
- ✅ **Sectional** (section Iₓ/modulus + beam deflection) — Kit + UI, on sim, screenshots.
- ✅ **Benchmark** (ITU-R BS.1770 integrated LUFS + targets) — Kit + UI (−20 dBFS tone → −19.99 LUFS), on sim, screenshots.
- ✅ **Geodesic** (Vincenty inverse — distance/bearing) — Kit + UI, on sim, screenshots.
- ✅ **Mersenne** (string tension/frequency + fret spacing) — Kit + UI, on sim, screenshots.
- ✅ **Fletcher** (A/C/Z frequency weighting) — Kit + UI, on sim, screenshots.
- 🟢 UI pending (Kit green): _none — all validated Kits now have shipping UI._

### Original-14 greenfield apps completed (Kit + oracle tests + UI, this program)
- ✅ **Kerf** (woodworking — board feet, compound crown miter, segmented rings, wood movement) — 7 tests: crown tables ±0.1°, Wood Handbook coefficients.
- ✅ **Gauge** (knitting — gauge, re-gauge, even shaping, yardage) — 6 tests: re-gauge worked example, exact even-distribution invariant.
- ✅ **Thiele** (loudspeaker box — sealed Qtc/Fc/F3, vented port length) — 4 tests: Butterworth alignment, port length vs classic Small/JBL formula.
- ✅ **Superheat** (HVAC — ASHRAE psychrometrics, superheat/subcool, ductulator) — 5 tests: ASHRAE worked point, duct sizing. P-T refrigerant table deferred (needs verified saturation data).
- ✅ **Apogee** (rocketry — Barrowman stability, RK4 flight, recovery) — 6 tests: Barrowman hand-worked, RK4 vs kinematics. ThrustCurve library a future add.
- ✅ **Parcel** (meteorology — CAPE/CIN/LI, LCL/LFC/EL, PW) — 4 tests: Bolton LCL + Espy, CAPE integrator hand-verified. Hodograph/SRH (wind data) a planned addition.
- ⏸️ **Farfield** (NEC2 method-of-moments antenna solver) — still deferred: large solver, out of scope for this pass.

**Program status:** every app except Farfield is built end-to-end — validated Kit, Liquid Glass UI, runs on the iOS Simulator, screenshots generated, App Store metadata drafted. **Nothing uploaded; no ASC records created.**
- ⏸️ Delayed: Helmholtz (>1 GB data), Farfield (NEC2 solver).
- ❌ Dropped: Overpass (offline-incompatible), Tidewell (→ Tideline), Ephemerion (→ Nightfield).
