# marinenav — Kit plan (library state only)

> **Status: BUILT, 2026-07-26.** All four Kits are written and green — **101 tests in 27 suites**,
> offline, verified from a clean tree with no build cache and no download cache.
> See §7 for what was delivered and §8 for what is honestly still open.
> Everything below §0–§6 is the plan as approved; it is left intact as the record.

| Kit | tests | oracle corpus | headline result |
|---|---|---|---|
| **TidesKit** | 46 in 12 suites | 16 cited oracles | reproduces NOAA's published predictions to **7.6 mm rms** (SF, 4 yr hourly) |
| **GeomagKit** | 16 in 4 suites | 100 official WMM2025 test points | COF + test values **byte-exact** vs today's NCEI distribution |
| **GeodesyKit** | 15 in 5 suites | 8 (Vincenty line + GeodTest rows) | direct/inverse invert each other to **1e-8°** |
| **CelestialNavKit** | 24 in 6 suites | 3 | Bowditch §805 worked sight pinned — **closes a two-pass TODO** |

Scope of this tree: Foundation-only `*Kit` Swift packages + oracle test suites + research notes.
No app target, no `project.yml`, no SwiftUI, no simulator, no marketing, no ASC, no commit without
an explicit go. Directory is `marinenav/` — **no `.swift` in the app name**, and when an app target
eventually exists its target name and `PRODUCT_NAME` must not contain `Swift` (Guideline 5.2.5).

## 0. What this app is

A **tides app with navigation support**, not four equal peers. The wedge is *tide prediction that
works with no signal*: computed on-device from published harmonic constituents, with every number
validated against NOAA's own published predictions.

Priority: **Tides** (the product) → **Geomag** (declination — every helm needs it) →
**Geodesy** (distance/bearing) → **CelestialNav** (sight reduction — the credibility feature).

## 1. Pre-flight research already done (2026-07-26)

I verified the tides oracle **before** planning around it, because the entire product rests on it.
Scripts are in `scratch/` (`tide_convention_spike.py`, `tide_phase_diagnostic.py`,
`tide_xi_variants.py`).

**The Class-A oracle exists and is live.** For the *same* station NOAA publishes both the harmonic
constants and the official predictions, so we can feed NOAA's constants into our synthesis and
assert agreement with NOAA's own numbers. Verified today against San Francisco (9414290):

| What | Endpoint (verified HTTP 200, 2026-07-26) |
|---|---|
| 37 harmonic constituents (`amplitude`, `phase_GMT`, `speed`) | `mdapi/prod/webapi/stations/{id}/harcon.json?units=metric` |
| Datums (MSL, MLLW, …) | `mdapi/prod/webapi/stations/{id}/datums.json?units=metric` |
| Published predictions (`interval=h` or `hilo`) | `api/prod/datagetter?product=predictions&…&time_zone=gmt&datum=MLLW` |

**Conventions pinned by measurement, not assumption:**

- `phase_GMT` is the Greenwich epoch **G**; synthesis form is `h = Z0 + Σ fᵢ·Aᵢ·cos(V0+u)ᵢ − Gᵢ`.
- **Z0 = MSL − MLLW = 0.951 m** at 9414290 (from the datums endpoint) — predictions are MLLW-referenced,
  constituent amplitudes are about MSL. Getting this wrong is a pure DC offset.
- Mean-solar hour angle **T = 15°·h_UT + 180°** (180° at 00:00 UT).
- My Schureman-form V₀ rates reproduce NOAA's published `speed` field to **≤ 7·10⁻⁷ °/hr** for all
  eight principal constituents — so the Doodson combinations are right.
- Least-squares recovery of (A, G) from **NOAA's own 1-year hourly predictions** returns their
  published amplitudes to **±0.002 m** for M2/S2/K1/O1/P1. That independently confirms the synthesis
  form and the node factors *f*.

**The one real risk, now quantified.** The nodal angle **ξ** has three plausible sign conventions in
circulation, and they are not distinguishable except against real predictions:

| ξ convention | direct-synthesis rms vs NOAA (1 yr hourly) | max error |
|---|---|---|
| `ξ = ½(ξ+ν) + ½(ξ−ν)` (naive) | 0.383 m | 1.09 m |
| `ξ = N − at1 − at2` (pyTMD/Schureman p.156 as coded) | 0.115 m | 0.34 m |
| `ξ = at1 + at2 − N` | **0.080 m** | 0.26 m |

All three are "green" against self-consistency and all three are wrong by a margin a mariner would
notice.

**RESOLVED, 2026-07-26** — from Schureman SP-98 directly (see `research/SOURCES.md`):

- The **best-fitting** ξ convention was the **wrong** one. It was compensating for a second bug.
- Two from-memory mean-longitude constants were wrong: **`s` by +6.587°**, **`h` by +0.493°**.
  The diagnostic localised both (δs from M2 and O1, δh from K1) *before* Schureman's Table 1 was
  found — then Table 1 confirmed them exactly. Now taken from **SP-98 Table 1, p. 163**.
- ξ is settled by **SP-98 Table 6** ("positive when N is 0–180°, negative when N is 180–360°"):
  `ξ = N − atan(1.01883·tan(N/2)) − atan(0.64412·tan(N/2))`. Our closed forms reproduce Table 6
  to **0.006°** (the table itself is printed to 0.01°).
- Prediction form and epoch conventions come from **Parker, NOAA Sp. Pub. NOS CO-OPS 3 (2007)**
  eq. 3.1–3.3, including that NOAA holds **f and u constant across each year** (midyear value).
- Free identity oracle found: Parker eq. 3.2 (`g = G − a·S/15`) reproduces NOAA's published
  `phase_local` from its published `phase_GMT` for **all 33 non-zero constituents to ≤0.09°**,
  inside NOAA's own 0.1° publication rounding.

**Achieved residual (this is where the tolerance comes from).** 8,760 hourly NOAA predictions,
station 9414290, synthesised from NOAA's published constants:

| model | rms | max | bias |
|---|---|---|---|
| 8 principal constituents | **0.0604 m** | 0.1965 m | +0.0001 m |
| least-squares noise floor, same 8 | 0.0601 m | — | — |

Those agree to 0.0003 m — the 8-constituent model is **at its theoretical best**, so all remaining
error is the 29 omitted constituents, *not* convention error. Recovered vs published constants:
M2 ΔA +0.000 m / ΔG −0.03°, K1 ΔA +0.000 m / ΔG −0.00°, O1 ΔA +0.000 m / ΔG −0.07°.

**Noise floor.** Therefore **all 37 constituents are required**; 8 will not do. The remaining tides
work is transcribing SP-98 **Table 2** (f and u for all 37) and re-measuring.

## 2. Kits

No inter-Kit dependencies. Each: `// swift-tools-version:5.9`, `platforms: [.macOS(.v13), .iOS(.v16)]`,
one `.target` + one `.testTarget`, Foundation only, **no network inside a Kit**, no resources
(fixtures are Swift string constants — code, not SPM resources — so a fresh clone tests offline).

### 2.1 `Kits/Tides/TidesKit` — the product

| Namespace | Public API | Oracle |
|---|---|---|
| `Astronomy` | `meanLongitudes(at:) -> (T,s,h,p,N,p1)` deg | Schureman SP-98 mean-longitude polynomials (cite page) |
| `Nodal` | `corrections(nodeDeg:) -> (I, xi, nu, nuPrime, twoNuDoublePrime)`; `factor(_ c: ConstituentID, …)` | Schureman SP-98 §nodal, eq. 197/202/204/213/214/224/232 + Table 6 |
| `Constituents` | all **37** NOAA constituents: Doodson V₀ combination, speed, f/u rule | Schureman Table 2 speeds, cross-checked against NOAA `speed` (≤1e-6 °/hr) |
| `Harmonics` | `height(_ station:at:) -> Double`; `extremes(_ station:start:hours:)` | **NOAA published predictions** for the same station |
| Models | `Constituent`, `Station`, `TideEvent`, `TideDatum` | — |

Ported forward from the existing `TidesKit` (models + extremes scanner are sound); the constituent
table, nodal machinery and equilibrium arguments are **new** — the current Kit has `f=1, u=0`
defaults, which is why it was never oracle-tested beyond constituent speeds.

**Oracles to pin:**

| id | source | what is asserted |
|---|---|---|
| `noaa-9414290-harcon` | NOAA CO-OPS harcon (US-gov, public domain), embedded verbatim | the 37 published A/G/speed — the *input* fixture |
| `noaa-9414290-datums` | NOAA CO-OPS datums | Z0 = MSL−MLLW = 0.951 m |
| `noaa-9414290-hourly-<date>` | NOAA published hourly predictions, MLLW, GMT | our synthesis vs NOAA, **rms + max**, tolerance from measured residual |
| `noaa-9414290-hilo-<date>` | NOAA published high/low predictions | extreme **heights** and **times** (time tolerance in minutes, measured) |
| `constituent-speeds` | Schureman SP-98 / NOAA published speeds | 37 speeds ±1e-6 °/hr (kept from prior art, widened to all 37) |
| second station, mixed/diurnal regime | same, e.g. a Gulf or Alaska station | proves it is not tuned to one station |

**Tolerance policy: the target is ±0.03 m rms / ±0.10 m max and ±10 min on extremes, but the number
committed to the corpus is whatever the python pre-check actually achieves**, recorded with its
residual. If the achieved residual is worse, the plan is wrong and I report that rather than widen
the tolerance quietly.

**Currents** (flood/ebb/slack) — **in scope this pass** (decided 2026-07-26). NOAA publishes
current-station harmonic constants and published current predictions, so currents get the same
Class-A treatment: `Currents.velocity(_:at:)` + `slacks/maxima`, asserted against NOAA's published
`currents_predictions` for the same current station. Current stations have their own conventions
(flood/ebb direction, `velocity_major`, bin/depth) — these get pinned by measurement the same way
the height conventions were, and recorded in `research/SOURCES.md`.

**Units — carry both metres and feet** (decided 2026-07-26). `Station` carries its `TideUnit`;
`Harmonics.height` returns in station units with explicit conversion accessors. The payoff: the
feet path is asserted against **NOAA's own English-unit predictions**, not against our own
conversion — so a unit bug cannot hide behind a self-consistent round-trip. Both unit fixtures are
embedded verbatim.

### 2.2 `Kits/Geomag/GeomagKit`

`WMM.field(latDeg:lonDeg:altKm:date:) -> (D,I,H,X,Y,Z,F)` — spherical-harmonic synthesis, WMM2025
`.COF` embedded verbatim as a Sources string constant with a **valid-to-2030** expiry comment.
Port from the existing Kit, but **re-verify** the coefficients and the official test-value table are
still the current ones at NOAA/NCEI and BGS before re-embedding. Tolerances D/I ±0.05°, H/X/Y/Z/F ±5 nT
(prior green thresholds — re-confirmed, not assumed).

### 2.3 `Kits/Geodesy/GeodesyKit`

`Vincenty.inverse/direct` on WGS-84. Oracles: Vincenty (1975) worked line + a regime-spread subset of
Karney's `GeodTest` (short, mid, long, near-polar, near-meridional, near-equatorial). **Near-antipodal
excluded** — Vincenty's documented non-convergence; the limitation is stated in the `///` docs, not
hidden. ±0.001 m / ±1e-3°.

### 2.4 `Kits/Celestial/CelestialNavKit`

`Navigation` (GHA/Dec, dip, Bennett refraction, observed altitude, Marcq Saint-Hilaire intercept) +
`SkyMath`. Existing oracles are Meeus 25.b / 47.a. **The open TODO from two prior passes is a
Nautical Almanac daily-page GHA/Dec worked sight** — I will source a citable worked example
(Nautical Almanac daily page, and/or Bowditch *American Practical Navigator*, US-gov public domain)
rather than synthesise one. If I cannot source one, it stays `TODO(oracle):` and I say so.

## 3. Licensing

Formulas and procedures are not copyrightable. NOAA, USC&GS (Schureman), NGA, USNO, Bowditch and WMM
are **US-government public domain** — embeddable verbatim. No copyrighted commercial almanac or chart
tables get embedded; where a dataset is proprietary, design for **user input** instead.

## 4. Order of work (after ✅)

1. Schureman SP-98 → pin ξ/ν/ν′/2ν″, all *f*, all V₀, with page+equation citations.
2. Python pre-check: full 37-constituent synthesis vs NOAA, 1 year hourly, ≥2 stations →
   **record achieved rms/max**; those become the Swift tolerances.
3. Write TidesKit + corpus + integrity guard + tests.
4. Port/re-verify Geomag, Geodesy, CelestialNav.
5. `swift test` green in all four Kits, offline, on a fresh clone.
6. `research/SOURCES.md` complete; stop and report, including every remaining `TODO(oracle):`.

## 5. Done gate

- [x] `swift test` green in all 4 Kits **with no network access** — 101 tests / 27 suites, re-run
      from a clean copy with no `.build` and no download cache
- [x] **TidesKit reproduces NOAA's published predictions** from that station's published
      constituents, within a stated, evidence-based tolerance — 4 stations, 2 unit systems
- [x] Every expected number traceable to a cited source with a URI; integrity guard enforces it
      (empty source, missing URI, missing tolerance, duplicate id all fail the suite)
- [x] `research/SOURCES.md`: citation, URI, retrieval date, licence, oracle IDs backed
- [x] No app target, no UI, no marketing, no ASC, **nothing committed**

## 6. Decisions taken (2026-07-26)

1. **Stations** — San Francisco 9414290 (mixed semidiurnal, long record, already spiked) **plus one
   contrasting regime** (diurnal / large-range) so the result is not tuned to one place.
2. **Currents** — **in scope this pass**, with their own NOAA Class-A oracle (§2.1).
3. **Units** — **both metres and feet**, with the feet path asserted against NOAA's own English-unit
   predictions (§2.1).

---

## 7. What was actually built (2026-07-26)

```
marinenav/
  PLAN.md                       research/SOURCES.md
  Kits/Tides/TidesKit/          Astronomy · Nodal · Constituents · Harmonics · Currents · Epoch · Models
  Kits/Geomag/GeomagKit/        WMM (degree-12 synthesis) + WMM2025 COF embedded verbatim
  Kits/Geodesy/GeodesyKit/      Vincenty inverse + direct (WGS-84)
  Kits/Celestial/CelestialNavKit/  Navigation · SkyMath · Sextant (index-correction conventions)
  scratch/                      6 python pre-checks (kept and cited; their NOAA cache is gitignored)
```

Every Kit: Foundation-only, `swift-tools-version:5.9`, `[.macOS(.v13), .iOS(.v16)]`, one target +
one test target, **no dependencies, no SPM resources, no network**. Verified by grep: no
`URLSession`, no `Bundle.module`, no `resources:`.

**Measured accuracy** (full table with least-squares floors in `research/SOURCES.md`):

| what | result |
|---|---|
| SF tides, 4 yr hourly, metric | 7.6 mm rms · 35 mm max (floor 5.3 mm) |
| SF tides, feet, vs NOAA's own English output | 0.0256 ft rms (floor 0.0170 ft) |
| Galveston (diurnal) · Honolulu · Boston | 2.6 · 2.8 · 8.8 mm rms — each within 1 mm of its floor |
| Currents, ACT1616, 1 yr 30-min | 1.185 cm/s rms on a 66.8 cm/s signal (floor 1.129) |
| Slack / max flood / max ebb vs NOAA MAX_SLACK | ≤ 4.6 min, ≤ 4.1 cm/s |
| Nodal angles vs Schureman Table 6 | 0.006° (table printed to 0.01°) |
| WMM2025 vs 100 official test points | < 5 nT, < 0.05° |

Each Kit's tolerances were set **from the measured residual**, not chosen first. Where a measured
residual would have failed a target, the finding is reported (§8) rather than the tolerance widened.

## 8. Honestly still open

1. **M1, S1 and R2** keep per-constituent phase offsets (~20°, ~19°, ~41°) against NOAA at 9414290.
   Every discrete alternative convention was tested (`scratch/tide_variants.py`) and all made the
   overall residual **worse**, so the current rules are the best available. Together they carry
   < 0.02 m, inside the stated tolerance. Probable cause: NOAA infers rather than analyses these
   minor constituents. **Unresolved.**
2. **Schureman Table 1 and Table 6 numbers were read from archive.org OCR**, because NOAA's own
   SP-98 scan has no text layer. Both are strongly corroborated (Table 1 by the diagnostic that
   predicted its two errors independently; Table 6 by 0.006° agreement across five rows) but have
   **not** been re-read against the scan page images. Worth doing before release.
3. **Anchorage-class stations.** Where NOAA's own predictions use more constituents than it
   publishes, no 37-constituent synthesis can match them (0.22 m rms at 9455920, though within
   0.6 mm of the optimal 37-constituent fit). Documented as a MODEL CAVEAT on `Harmonics`; the app
   should not imply chart-datum accuracy at such stations.
4. **CelestialNavKit's ephemeris is compact-series** (≈0.1–0.25°), coarser than a Nautical Almanac
   daily page. Fine for identification and for demonstrating the reduction; **not** what a real fix
   should be worked from. Stated as a MODEL CAVEAT.
5. **Currents are major-axis (rectilinear) only** — the rotary minor-axis component is not modelled.

## 9. Not done, by design

No app target, no `project.yml`, no SwiftUI, no simulator, no screenshots, no marketing, no App
Store Connect. **Nothing has been committed** — the tree is untracked and awaiting review.

---

## 10. Structural UI (2026-07-26)

**Purpose: hand this to the design pass.** The information architecture, navigation and
Kit wiring are done and verified against NOAA; the styling is deliberately absent.

```
project.yml                     XcodeGen; bundle oleksandr.aisixteen.marinenav; iOS/macOS 26
marinenav-macOS.entitlements    sandbox
MarineNav/
  MarineNavApp.swift            @main, universal
  ContentView.swift             NavigationSplitView root + ResultRow / NumberField / ProvenanceFooter
  Catalog.swift                 Tool enum: title, subtitle, symbol, backing Kit, cited oracle
  StationCatalog.swift          GENERATED — 12 tide + 6 current stations, offline
  Tools/                        Tides · Currents · Declination · DistanceBearing · SightReduction
```

**Target is `marinenav`, `PRODUCT_NAME` is "Marine Nav"** — no `.swift` anywhere in the shipped
name (Guideline 5.2.5).

**The app is genuinely offline.** `StationCatalog.swift` carries NOAA's published constants for
12 tide stations (SF, San Diego, Seattle, Anchorage, Boston, The Battery, Virginia Key, Galveston,
Honolulu, Philadelphia, Beaufort, Charleston) and 6 harmonic current stations (Golden Gate,
Pollock Rip, Hell Gate, Deception Pass, Tampa Bay, San Diego Bay). Regenerate with
`scratch/make_station_catalog.py`. The Kits stay data-free and network-free.

**Verified against NOAA through the running app**, not just in tests:

| screen | app | NOAA | agreement |
|---|---|---|---|
| Tides, SF 26 Jul 2026 | L 04:34 −0.11 ft · H 11:58 +4.58 · L 16:08 +3.39 | L 04:35 −0.11 · H 12:00 +4.56 · L 16:05 +3.40 | ≤ 3 min, ≤ 0.02 ft |
| Currents, Golden Gate | Ebb 03:36 · Flood 09:29 | 03:37 · 09:30 | ≤ 1 min |
| Sight Reduction | Ho 34° 49.0′ · Hc 35° 13.6′ · Zn 340.4°T · 24.5 nm Away | Bowditch §805 | exact |
| Distance & Bearing | SF→Honolulu 2080.9 nm, 251.8°T | — | — |

### Two real bugs the on-device check caught (tests alone would not have)

1. **Times were shown in the device's time zone.** San Francisco tides read ~10 h out on a
   Kyiv-set simulator while every *height* looked perfect. Stations now carry an IANA zone and
   all times are reckoned and formatted in **station-local** time, labelled with the zone (PDT).
2. **The picked day resolved to the previous day at the station**, because the date picker hands
   back device-zone midnight. The app was showing 25 July's tides under a "26 Jul" heading —
   matching NOAA's 25 July to 2 min. Now the picked y/m/d is resolved against the station calendar.
3. *(Also found)* **`majorMeanSpeed` was being ignored** — NOAA publishes each current station's
   non-tidal mean flow, and omitting it shifted Golden Gate by 0.49 kn. Now carried in the catalog,
   and the TidesKit oracle uses the **published** value instead of deriving it from NOAA's own
   predictions, removing a mildly self-referential step.

A Kit performance fix came out of the same pass: `Astronomy.elements` built a `Calendar` per call,
which dominated cost when finding slack water (thousands of samples). It now derives the UT hour
from epoch seconds — exact, since Unix time ignores leap seconds.

### For the design pass

- Every screen is a plain `Form` with `ToolSection` / `ResultRow` / `NumberField` — obvious seams
  to replace. **Do not move math into views**: all of it is in the Kits, and that must survive.
- Every input has an explicit `range:`; every input and emphasised result has an
  `accessibilityIdentifier` already, ready for UI tests.
- `ProvenanceFooter` names the backing Kit and the cited authority on each screen — the moat is
  validated math, so provenance is product surface, not a footnote.
- `#Preview`s exist per tool (Tides has light + dark).
- **Not done, deliberately:** no design system, no colour/type system, no app icon (placeholder
  `AppIcon.appiconset` with no images), no launch screen art, no onboarding, no station search or
  favourites, no map, no per-station "nearest to me".
- Known rough edges: number fields inherit the locale decimal separator (shows `54,6` on a
  European locale); the tide curve is a bare `Path` with no axes or labels.
