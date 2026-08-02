# calculators/ — folder sort → imaginary "supercalc" apps (merge map)

_17 single-domain calculator folders sorted into **11 imaginary apps**. 4 are **merge-groups** (several folders → one app, à la the music→Overtone Lab consolidation); 7 are already-coherent **standalones** (1 folder = 1 app). Nothing here is git-tracked; each app's value is its oracle-tested `*Kit`(s). Guideline 4.3: ship these as ~11 suites, never 17 thin apps._

**Physical layout (sorted 2026-07-07):** each app now lives under its category folder — `calculators/<category>/<app>.swift`. Categories: `marine-navigation/` · `astronomy/` · `survey-structural/` · `rf-antenna/` · `machinist/` · `hvac/` · `woodworking/` · `knitting/` · `rocketry/` · `meteorology/` · `options/`. Shared `tools/` + the 3 `.md` files stay at `calculators/` root.

**Shared-engine signal (why some group):** `intercept` · `nightfield` · `syzygy` all share a **`SkyMath`/`Angles`/`Models`** celestial core. `geodesic`'s **`Vincenty`** = the same primitive as `traverse`'s **`Geodesy`**. Those overlaps are the "one supercalc" tell.

---

## A. MERGE-GROUPS — several folders → one app

### 1. 🧭 Marine / Blue-Water Navigation
**Merge:** `intercept` + `tideline` + `geodesic` + `deviation`
| Folder | Kit topics | Role in the app |
|---|---|---|
| intercept | Angles · Models · Navigation · SkyMath | Celestial sight reduction (Marcq St-Hilaire), running fix |
| tideline | Constituents · Harmonics · Models | Offline harmonic tide/current prediction |
| geodesic | Vincenty | Great-circle distance/bearing *(shared primitive — see Survey)* |
| deviation | WMM | Magnetic declination *(also useful to Aviation/TrueCourse)* |
- **Audience:** offshore sailors, navigators. **Compass fit: strong** — LLM-resistant (safety at sea), *offline is the wedge* (most tide/nav apps need network). Realizes the v3 marine adjacency.

### 2. 🌌 Astronomy / Night Sky
**Merge:** `nightfield` + `syzygy`
| Folder | Kit topics | Role |
|---|---|---|
| nightfield | Angles · Camera · Models · Session · SkyMath | Deep-sky astrophoto planner (astro-dark, NPF, FOV, integration/SNR) |
| syzygy | Angles · Models · SkyMath · Syzygy | Moon phase, next new/full, eclipse seasons |
- Shared **SkyMath** core → natural single app. **Audience:** astrophotographers + amateur astronomers. ⚠ **Check overlap with the existing `ephemeris.swift` app** before building — could be a 4.3 pair or a merge into ephemeris.

### 3. 📐 Survey & Structural (Civil)
**Merge:** `traverse` + `sectional` (+ `geodesic` shared)
| Folder | Kit topics | Role |
|---|---|---|
| traverse | COGO · Geodesy | Inverse/forward, Bowditch balancing, curves, resection, area, UTM/MGRS |
| sectional | Sections | Beam deflection, section modulus / Iₓ |
| geodesic | Vincenty | *(shared with Marine Nav — pick one home, reuse the Kit)* |
- **Audience:** surveyors, civil engineers. **Compass fit: strong** — pro paying niche, v3 survey seeds.

### 4. 📡 RF & Antenna
**Merge:** `skywave` + `farfield`
| Folder | Kit topics | Role |
|---|---|---|
| skywave | RF | Link budget (Friis), Fresnel, antenna dims, coax loss, microstrip, VSWR, dBm↔W |
| farfield | *(planned — NEC2 solver)* | Method-of-moments radiation pattern / impedance (advanced section) |
- **Audience:** RF engineers, hams. skywave = everyday field tools; farfield = the heavy modeling section. **Fit: good** (hobby-pro). farfield is high-effort — ship skywave first, add farfield as a section later.

---

## B. STANDALONES — already one coherent domain (1 folder = 1 app)

| App | Folder | Kit topics | Audience | Compass fit |
|---|---|---|---|---|
| ⚙️ **Machinist** | swarf | Machining | Machinists, CNC | **Strong** — compass names machinist; already a full suite (feeds/speeds, threads, bolt-circle, sine-bar, true-position) |
| ❄️ **HVAC / Mechanical** | superheat | Air · Charge · Psychrometrics | HVAC techs | **Strong** — trades niche, v3 seed |
| 🪵 **Woodworking** | kerf | Angles · Movement · Segmented · Species · Stock | Woodworkers | Good — distinct from published `kerfcalc` (construction); only CompoundMiter overlaps |
| 🧶 **Knitting / Fiber Arts** | gauge | GaugeMath · Shaping · Yardage | Knitters, crocheters | Good — v3 textiles seed; smaller but clean niche |
| 🚀 **Rocketry** | apogee | Barrowman · Flight | Rocketry hobbyists, educators | OK — distinct hobby/education niche |
| ⛈️ **Meteorology** | parcel | Parcel · Thermo | Storm chasers, forecasters | Niche — distinct from `eartharound` (space weather); park or low-priority |
| 📈 **Options / Trading** | payoff | BlackScholes · Binomial | Options traders | ⚠ **Off-compass** — trading is crowded + LLM-doable; park unless you specifically want it |

---

## Summary
- **17 folders → 11 imaginary apps.** Merge-groups collapse 10 folders → 4 apps (Marine Nav, Astronomy, Survey/Structural, RF/Antenna); 7 stay standalone.
- **Shared Kits to factor out on merge:** `SkyMath`/`Angles`/`Models` (Marine Nav + Astronomy), `Vincenty`/`Geodesy` (Marine Nav + Survey).
- **Build priority by compass fit:** Marine Nav · Survey · Machinist · HVAC (strong) → RF · Astronomy · Woodworking · Knitting · Rocketry (good) → Meteorology · Options (park).
- **Flags before merging:** Astronomy ↔ ephemeris overlap; geodesic's home (Nav vs Survey — it's a shared primitive either way); payoff off-strategy.
