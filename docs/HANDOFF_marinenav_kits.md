# HANDOFF PROMPT — build the Marine Navigation **Kits only** (oracle-first, web-researched)

> **Paste this whole file into a fresh Claude Code session.** It is self-contained; assume no memory of
> prior chats. Working directory = the `rootyapps` repo root.

---

## 0. What we are doing (read twice — this frames every decision)

We renovate **abandoned-but-demanded** niche apps into **buy-once, offline, no-ads, no-subscription,
no-IAP** tools whose moat is **validated math you can prove** — every displayed number traceable to a
**cited external published authority**, asserted by tests. Trust first, pixels later.

**Why this app, specifically.** An N3 demand scan on 2026-07-26 (`docs/n3_revalidation_2026-07-26.md`)
measured every candidate niche in the portfolio. Marine navigation was one of only two that survived:

- `Tide Charts` (7th Gear) — **111,004 ratings, 4.8★, free, last updated 2022-06-07 → 49.6 months stale.**
- Paid-upfront tide apps already sell: `Tide Graph Pro` $5.99 (3,568 r), `Nautical Charts & Maps` $8.99
  (3,771 r), `My Tide Times Pro` $3.99 (1,171 r).
- Live incumbents are network-dependent and subscription-wounded (`Tides Near Me`, 2026-07 1★:
  _"Here we go again another app becoming a financial blood sucker."_).

**The wedge is therefore: tide & current prediction that works with no signal, computed on-device from
published harmonic constituents, with numbers validated against NOAA's own published predictions.**

**Priority order — this is a tides app with navigation support, not four equal peers:**
1. **Tides** (the product) 2. **Geomag** (declination — every helm needs it)
3. **Geodesy** (distance/bearing) 4. **CelestialNav** (sight reduction — the credibility feature).

## 1. Scope of THIS task — libraries only

**Build ONLY the Foundation-only `*Kit` Swift packages + their oracle test suites.**

✅ In scope: Kits, `Oracles.swift` corpora, integrity guards, tests, a `PLAN.md`, python pre-checks,
web research to source and verify the oracles.

❌ **Hard non-goals:** no app target, no `project.yml`, no SwiftUI, no UI of any kind, no simulator,
no screenshots, no marketing, no App Store Connect, no upload. **No git commit without explicit human
go.** Do not invent an oracle number — if you cannot cite a published source, mark it
`TODO(oracle):` and say so in your report.

## 2. Read first (in this order)

1. `calculators/VALIDATION.md` — the canonical oracle directive. **It governs.**
2. `docs/new_app_blueprint.md` §P1 — the Kit + oracle phase spec.
3. `calculators/ORACLE_SCAFFOLD_PROMPT.md` §3–§6 — the exact Kit pattern, corpus shape, integrity
   guard, `Package.swift` template. **Copy this shape precisely.**
4. `docs/n3_revalidation_2026-07-26.md` — why this niche and not the others.
5. **Prior art to harvest, not re-derive** (both trees already have working math and green tests):
   - `calculators/marine-navigation/{tideline,intercept,geodesic,deviation}/`
   - `calculator_candidates/marinenav.swift/Kits/{Tides,Geodesy,Celestial,Geomag}/` — a previous
     scaffold pass with its own `PLAN.md` listing what was already cited and what was left `TODO`.
6. One green exemplar end-to-end: `overtonelab.swift/Kits/…` (a shipped app's Kit + Style-A oracle suite).

   *(Those two paths really are named `…​.swift/` on disk — that is the legacy convention. Read them,
   do not imitate the name; see §3.)*

## 3. Where it goes

Create **`marinenav/`** at the repo root (shipped apps live at root; `calculator_candidates/` is
the scratch tier we are promoting out of). Store name is an ASO decision for later — do not agonise.

**Naming rule — no `.swift` anywhere in this app's name.** Older trees in this repo use a `<name>.swift/`
directory convention; **do not copy it here.** The directory is `marinenav/`, and when an app target
eventually exists (not in this task) its target name and `PRODUCT_NAME` must not contain `Swift` or
`.swift` in any form. Apple rejects under Guideline 5.2.5 when the shipped binary/menu-bar name reads
`marinenav.swift`. Kit names are unaffected — `TidesKit` etc. stay as they are.

```
marinenav/
  PLAN.md                              # write this FIRST, get human ✅ before coding
  Kits/Tides/TidesKit/                 # Package.swift · Sources/TidesKit/*.swift · Tests/TidesKitTests/{Oracles.swift,*Tests.swift}
  Kits/Geomag/GeomagKit/
  Kits/Geodesy/GeodesyKit/
  Kits/Celestial/CelestialNavKit/
  scratch/                             # python numeric pre-checks (gitignored)
  research/SOURCES.md                  # every web source you used: URI + retrieval date + licence
```

Each Kit: `// swift-tools-version:5.9`, `platforms: [.macOS(.v13), .iOS(.v16)]`, one `.target` + one
`.testTarget`, **no dependencies, no resources**. Foundation only — no UIKit, no SwiftUI, **no network
inside a Kit**.

## 4. The web research you must do (this is the new part)

Prior scaffolds inherited tolerances and citations. **This time, verify them against the live sources
and close the open TODOs.** For each source record in `research/SOURCES.md`: full citation, URI,
retrieval date, **licence/public-domain status**, and exactly which oracle IDs it backs.

**Tides — the critical path.**
- NOAA CO-OPS publishes, for the same station, **both the harmonic constituents and the official
  predictions**. That is a Class-A oracle: feed the published constituents into our synthesis and assert
  agreement with NOAA's published predicted heights/times. Find the current endpoints and response
  shapes (the API has moved before — do not trust a remembered URL, verify it).
- Research and pin down: constituent **amplitude/phase (H, κ)** conventions, **nodal corrections
  f and u**, **equilibrium arguments (V₀+u)**, epoch/time-zone and **datum (MLLW)** handling, and the
  station's stated **units and reference meridian**. Getting these conventions wrong is the classic
  failure mode and it is silent.
- **Schureman, *Manual of Harmonic Analysis and Prediction of Tides* (USC&GS Special Publication 98)** is
  the public-domain authority for constituent speeds, f/u and equilibrium arguments — locate it and cite
  page/table numbers.
- Also research **currents** (flood/ebb, slack) — NOAA publishes current-station harmonic data too.
- **Embed a small fixture verbatim** (one or two stations' constituents + a day of NOAA published
  predictions) as Swift string constants or test-corpus data so `swift test` is **green offline on a
  fresh clone**. US-government output is public domain — confirm and record that in `SOURCES.md`.

**Geomag.** NOAA/NCEI + BGS publish the **WMM2025 coefficients (.COF) and an official test-value table**.
Verify both are current (WMM2025 is valid to 2030 — record the expiry in a code comment) and re-embed
them verbatim. Target tolerances: D/I ±0.05°, H/X/Y/Z/F ±5 nT.

**Geodesy.** **Vincenty (1975)** worked line + **Karney's GeodTest** set (GeographicLib). Embed a
regime-spread subset verbatim (short, mid, long, near-polar, near-meridional, near-equatorial; exclude
near-antipodal — Vincenty's documented non-convergence, and scope the claim in the docs).

**Celestial.** The still-open TODO from the last pass: **a Nautical Almanac daily-page GHA/Dec worked
sight**, plus **Bowditch, *The American Practical Navigator*** (US-gov, public domain) for sight-reduction
worked examples, dip, refraction and limb corrections. Find a citable worked example — do not
synthesise one.

**Licensing guardrail.** Formulas and procedures are not copyrightable; **US-government publications
(NOAA, USC&GS, NGA, USNO, Bowditch, WMM) are public domain**. **Do not embed copyrighted commercial
tables or chart/almanac products.** If a needed dataset is proprietary, design for **user input**
instead of shipping it, and say so in `PLAN.md`.

## 5. The oracle discipline (non-negotiable)

Per `VALIDATION.md` + `ORACLE_SCAFFOLD_PROMPT.md` §4:

- **`Oracles.swift` corpus per test target.** Expected numbers exist **only** there, each as
  `Oracle { id, source, inputs, values, tolerances }` with a **non-empty cited `source` including a URI**.
- **Integrity guard suite** — fails on an empty `source`, a value without a matching tolerance, or a
  duplicate id.
- **Reference tests pull values through `Oracles.require(id)`** — they cannot hardcode a number.
- **Label every suite** `// Oracle = <cited source + URI>. <oracle-backed | identity | invariant>`.
- **Test what the domain breaks on**, not the happy path: E/W and N/S sign conventions, the
  antimeridian, LHA wrap in east longitude, datum ≠ MLLW, nodal-cycle (18.6 yr) boundaries, leap years,
  slack-water sign changes, polar and equatorial degenerate cases, limb-correction sign.
- **Python pre-check** any gnarly formula in `scratch/*.py` first — reproduce the published value,
  record the **achieved residual**, and set the Swift tolerance from that evidence. Keep the script and
  cite it if it derived a value.
- `///` docs on every public symbol; add `Pure, stateless.` and `MODEL CAVEAT:` wherever a model
  (not an identity) is involved — the compact tide/celestial series especially.
- Guard **illegal domains only** (`precondition`/throwing). Never clamp for UI.

## 6. Order of work

1. **Write `PLAN.md` first** — per Kit: the `<Topic>` namespaces and public functions, and **per
   function the cited oracle + the specific worked value(s) you will pin**, plus the open TODOs you
   could not source. **Stop and get human ✅ on the plan before writing Kit code.**
2. Do the web research (§4) and fill `research/SOURCES.md`.
3. Harvest the math from the prior art (§2.5); consolidate — do not re-derive.
4. Python pre-checks for the tide synthesis and anything else non-trivial.
5. Write the Kits + corpora + guards + tests.
6. `cd Kits/<Section>/<Kit> && swift test` → **green in every Kit**, offline, on a fresh clone.
7. **Stop and report** (§7).

## 7. Definition of done

- [ ] `PLAN.md` approved by the human before coding began.
- [ ] `research/SOURCES.md`: every source with URI, retrieval date, licence, and the oracle IDs it backs.
- [ ] 4 Kits, Foundation-only, `public enum` namespaces, unit-suffixed labels, `///` + MODEL CAVEATs.
- [ ] Each Kit: `Oracles.swift` (every entry cited with a URI), integrity guard, and oracle-backed +
      identity + invariant suites, each labelled.
- [ ] **`swift test` green in all four Kits with no network access.**
- [ ] **TidesKit reproduces NOAA's own published predictions** for at least one real station from that
      station's published constituents, within a stated, evidence-based tolerance.
- [ ] Everything lives under `marinenav/` — **no `.swift` in the app/directory name** (§3).
- [ ] No app target, no UI, no marketing, no ASC, nothing committed without explicit human go.

## 8. Report back with

Per Kit: number of oracles, the sources cited, `swift test` result, and every remaining
`TODO(oracle):` stated plainly. Per open question: what you could not source on the web and what you
need a human to decide. **Be honest about gaps — a green suite with an uncited number is worse than a
red one.**
