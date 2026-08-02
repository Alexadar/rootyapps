# HANDOFF PROMPT — scaffold oracle-first calculator candidates (Kits + match-checkers only)

> **Paste this whole file into a fresh Claude Code session** (it is self-contained; assume no memory of prior chats).
> Working dir = the `rootyapps` repo root. Reference material lives in `calculators/` and `overtonelab.swift/`.

---

## 0. MISSION & SCOPE (read this twice)

Build a set of **oracle-first, universal SwiftUI apps** into a new `calculator_candidates/` folder, in **two gated phases**. Finish and get Phase 1 **all-green** before touching Phase 2.

**PHASE 1 — the validated core (do first):**
1. **The validated core** — Foundation-only `*Kit` Swift Package(s) with the domain math.
2. **The oracle tests ("match-checkers")** — Swift-Testing suites asserting every computed number against a **cited external published value**, via an `Oracles.swift` corpus + enforcement guard.
3. **A universal SwiftUI app shell** (iPhone + iPad + Mac) that compiles and links the Kits — placeholder `ContentView`, **no real UI**.

**PHASE 2 — generate the UI, WITHOUT running a simulator (§10):** once Phase 1 is green **and the human says go**, build the real per-tool SwiftUI UI on the established design system. **Verify by build (iOS + macOS) + authored Xcode `#Preview`s ONLY.** Do **not** boot the Simulator, run `simctl`, capture screenshots, or run any visual loop — the human does the on-device visual review afterward.

**This is trust-manufacturing first, presentation second.** The moat is *validated math you can prove*. Nothing ships. No marketing, no release.

**Hard non-goals (never):**
- ❌ **No simulator run / no `simctl` / no screenshot capture / no visual loop** — Phase 2 is build-and-`#Preview` only.
- ❌ No marketing media, ASO, screenshots, reels.
- ❌ No App Store Connect, no archive, no upload, no bundle-id creation.
- ❌ Do not invent oracle numbers. If you can't cite a published source for an expected value, the test is invalid — mark it TODO, don't fake it.
- ❌ Do not start Phase 2 until Phase 1 is green and the human approves.

**Efficiency rule:** the apps in `calculators/` are **prior art that already has working math + oracle tests**. **Harvest** the formulas and the cited oracle values from there — port and consolidate, do **not** re-derive from scratch.

---

## 1. READ FIRST (before writing anything)

- `calculators/GROUPING.md` — the candidate apps and which existing folders merge into each.
- `calculators/VALIDATION.md` — the canonical oracle directive (the discipline below is a summary; that file governs).
- `calculators/README.md` — what each prior calculator computes + its status.
- **One exemplar Kit end-to-end** — open a *built, green* one, e.g. `calculators/marine-navigation/intercept.swift/InterceptKit/` (Sources + Tests) and `overtonelab.swift/` Kits. Copy their shape exactly.
- `docs/new_app_blueprint.md` §P1 — the Kit + oracle phase spec.

---

## 2. THE CANDIDATE APPS (the "tens apps list")

Scaffold these into `calculator_candidates/<app>.swift/`. Each row = one universal app; its Kits merge/port from the listed `calculators/` folders. **Cited oracle source is mandatory** — it's the whole point.

| App (`slug`) | Kit(s) | Merge from `calculators/` | **Cited oracle authority** |
|---|---|---|---|
| **Marine Nav** (`marinenav`) | CelestialNav, Tides, Geodesy, Geomag | marine-navigation/{intercept,tideline,geodesic,deviation} | **Bowditch – American Practical Navigator** (US gov, public domain) + **Nautical Almanac** worked sight-reductions; **NOAA** published tide-station predictions + harmonic constituents; **Vincenty (1975)** + GeographicLib test lines; **NOAA/NCEI WMM** coefficients + official WMM test values |
| **Astronomy** (`astro`) | SkyMath, Camera, Syzygy | astronomy/{nightfield,syzygy} | **Meeus, *Astronomical Algorithms*** worked examples; **USNO** rise/set; NPF sharp-star rule (published); **Espenak/NASA** eclipse dates |
| **Survey/Structural** (`survey`) | COGO, Geodesy, Sections | survey-structural/{traverse,sectional} (+geodesic) | **Ghilani & Wolf, *Elementary Surveying*** traverse examples (published closures); **NGA** UTM/MGRS; **Gere, *Mechanics of Materials*** / **Roark's Formulas** worked beam cases |
| **RF/Antenna** (`rf`) | RF (Farfield/NEC2 later) | rf-antenna/{skywave,farfield} | **Friis** (public) + **Pozar, *Microwave Engineering*** worked values; VSWR definition; **NEC2** validation cases |
| **Machinist** (`machinist`) | Machining | machinist/swarf | Formula-derived: **SFM = πDN/12**, chipload/MRR (hand-worked); **Unified/ISO** thread geometry. ⚠ Machinery's Handbook *tables* are copyrighted — pin to **formulas**, not table transcriptions |
| **HVAC** (`hvac`) | Psychrometrics, Charge, Air | hvac/superheat | **ASHRAE Handbook — Fundamentals** worked psychrometric point; published saturation P-T points (cite the source; avoid licensed REFPROP data) |
| **Woodworking** (`woodworking`) | Stock, Angles, Segmented, Movement, Species | woodworking/kerf | **USDA FPL *Wood Handbook*** (public domain) shrinkage coefficients; board-foot definition; compound-miter trig (identity) |
| **Knitting** (`knitting`) | GaugeMath, Shaping, Yardage | knitting/gauge | Gauge definition (stitches/in); worked re-gauge example; even-distribution invariant (pure math) |
| **Rocketry** (`rocketry`) | Barrowman, Flight, Recovery | rocketry/apogee | **Barrowman** original paper worked example; RK4 vs analytic kinematics; ISA standard atmosphere |
| **Meteorology** (`weather`) | Thermo, Parcel | meteorology/parcel | **Bolton (1980)** LCL formula; hand-verified CAPE integral; published sounding indices |
| **Options** (`options`) *(low priority; off-compass)* | BlackScholes, Binomial | options/payoff | **Hull, *Options, Futures & Other Derivatives*** solved Black-Scholes case; put-call parity invariant |

**Licensing guardrail (bake into every choice):** formulas & rules are **not copyrightable**; **US-gov publications are public domain** (Bowditch, Wood Handbook, WMM, USNO, NOAA, FAA). **Avoid copyrighted *tables/datasets*** (Machinery's Handbook tables, proprietary refrigerant data, course-rating DBs) — pin to formula-derived or public-domain values; where a proprietary dataset is unavoidable, design for **user input**, don't embed it.

**Ask the human before starting** which subset to scaffold first (recommend the compass-strong four: `marinenav`, `survey`, `machinist`, `hvac`). Don't blindly do all 11.

---

## 3. THE ORACLE-FIRST KIT PATTERN (copy exactly)

Foundation only. No UIKit, no SwiftUI, no network **in the Kit**.

```swift
// Sources/<Kit>/<Topic>.swift
import Foundation

/// <Topic> math. Pure, stateless. Every public number is oracle-tested.
/// MODEL CAVEAT: <state any modeling assumption / validity range, if applicable>
public enum <Topic> {
    /// Surface feet per minute → spindle RPM.  RPM = 12·SFM / (π·D_in)
    /// - Parameters unit-suffixed; guard only *illegal* domains (no UI-style clamping).
    public static func rpm(sfm: Double, diameterInch d: Double) -> Double {
        precondition(d > 0, "diameter must be > 0")
        return 12.0 * sfm / (.pi * d)
    }
}
```

Rules:
- `public enum <Topic>` as a static namespace (or `struct: Sendable` for data records).
- **Unit-suffixed** parameter/label names (`diameterInch`, `speedMS`, `angleDeg`).
- **Guard illegal domains only** (`precondition`/throwing) — never clamp for UI. UI clamping is a later-phase concern.
- `///` doc on every public symbol; add `Pure, stateless.` and `MODEL CAVEAT:` where a model (not an exact identity) is involved.
- For gnarly formulas, **numerically pre-check in Python first** (see §5) so constants are evidence-based.

---

## 4. THE MATCH-CHECKER DISCIPLINE (this is the deliverable's core)

From `VALIDATION.md`, condensed — the machinery that makes it self-enforcing:

**(a) Oracle corpus as data** — each `<Kit>Tests` target has an `Oracles.swift`: expected numbers exist **only** here, each tied to a cited external `source`.

```swift
// Tests/<Kit>Tests/Oracles.swift
struct Oracle {
    let id: String
    let source: String          // MUST be non-empty: citation + URI/edition/page
    let inputs: [String: Double]
    let values: [String: Double]
    let tolerances: [String: Double]
}
enum Oracles {
    static let all: [Oracle] = [
        Oracle(id: "vincenty_flinders_buninyong",
               source: "Vincenty 1975; GeographicLib test set (Flinders Peak↔Buninyong)",
               inputs: ["lat1": -37.951033, "lon1": 144.424867, "lat2": -37.652821, "lon2": 143.926495],
               values: ["distance_m": 54972.271, "azi1_deg": 306.868, "azi2_deg": 127.108],
               tolerances: ["distance_m": 0.001, "azi1_deg": 1e-3, "azi2_deg": 1e-3]),
        // …one entry per worked example, EACH with a real citation…
    ]
    static func require(_ id: String) -> Oracle {
        guard let o = all.first(where: { $0.id == id }) else { fatalError("no oracle \(id)") }
        return o
    }
}
```

**(b) Enforcement guard** — a suite that fails if any oracle has an empty `source`, a value without a matching tolerance, or a duplicate id:

```swift
import Testing
@Suite("Oracle corpus integrity")
struct OracleIntegrity {
    @Test func everyOracleIsCitedAndComplete() {
        var ids = Set<String>()
        for o in Oracles.all {
            #expect(!o.source.isEmpty, "oracle \(o.id) has no cited source")
            #expect(ids.insert(o.id).inserted, "duplicate oracle id \(o.id)")
            for k in o.values.keys { #expect(o.tolerances[k] != nil, "\(o.id).\(k) missing tolerance") }
        }
    }
}
```

**(c) Reference tests** — pull expected values *through* the corpus (they cannot hardcode a number without a citation):

```swift
@Suite("Geodesy — oracle-backed")
struct GeodesyOracles {
    @Test func vincentyInverseMatchesPublished() {
        let o = Oracles.require("vincenty_flinders_buninyong")
        let r = Geodesy.inverse(lat1: o.inputs["lat1"]!, lon1: o.inputs["lon1"]!,
                                lat2: o.inputs["lat2"]!, lon2: o.inputs["lon2"]!)
        #expect(abs(r.distanceM  - o.values["distance_m"]!) <= o.tolerances["distance_m"]!)
        #expect(abs(r.azi1Deg    - o.values["azi1_deg"]!)   <= o.tolerances["azi1_deg"]!)
    }
}
```

**(d) Test what the domain BREAKS on**, not the happy path: sign conventions (E/W, N/S), antimeridian, altitude/pressure ≠ sea level, saturation, end-corrections, retrograde/negative rates, leap/year boundaries. Add *identity/definition* tests (pure math) and *invariant/physics* tests (bounds, monotonicity, round-trips, conservation) alongside the oracle-backed ones — label each.

**Style-A header** on each suite:
```swift
// Oracle = <cited source + URI/edition>.  <what class: oracle-backed | identity | invariant>
```

---

## 5. PYTHON NUMERIC PRE-CHECK (for any non-trivial formula)

Before finalizing tolerances/constants, prototype in `calculator_candidates/<app>.swift/scratch/*.py`: implement the formula, reproduce the published worked value, record the **achieved residual** → set the Swift tolerance from evidence, not wishful thinking. (This is how ISO-9613 / SRA constants were locked in prior work.) Keep the script; cite it in the oracle `source` if it derived the value.

---

## 6. PROJECT SHAPE per candidate (+ the "no-UI" universal shell)

```
calculator_candidates/<app>.swift/
  project.yml                         # XcodeGen; bundle oleksandr.aisixteen.<slug>; team LSKNNBG94G; iOS/macOS 26;
                                      #   INFOPLIST_KEY_ITSAppUsesNonExemptEncryption: NO; universal (iphone/ipad/mac)
  Kits/<Section>/<Kit>/               # Foundation-only SPM pkg
    Package.swift                     # tools 5.9; platforms [.macOS(.v13), .iOS(.v16)]; 1 target + 1 testTarget; no deps/resources
    Sources/<Kit>/<Topic>.swift
    Tests/<Kit>Tests/{Oracles.swift, <Topic>Tests.swift}
  <App>/
    <App>App.swift                    # @main universal SwiftUI App
    ContentView.swift                 # PLACEHOLDER ONLY — see below
    Assets.xcassets                   # AccentColor + AppIcon stub
  scratch/                            # python pre-checks (gitignored)
```

**Package.swift** (per Kit):
```swift
// swift-tools-version:5.9
import PackageDescription
let package = Package(
    name: "<Kit>",
    platforms: [.macOS(.v13), .iOS(.v16)],
    products: [.library(name: "<Kit>", targets: ["<Kit>"])],
    targets: [
        .target(name: "<Kit>"),
        .testTarget(name: "<Kit>Tests", dependencies: ["<Kit>"]),
    ]
)
```

**Placeholder shell — NO real UI.** Just prove the app is universal, links the Kit(s), and builds:
```swift
// <App>App.swift
import SwiftUI
@main struct <App>App: App { var body: some Scene { WindowGroup { ContentView() } } }

// ContentView.swift
import SwiftUI
import <Kit>            // import each Kit so linkage is verified at compile time
struct ContentView: View {
    var body: some View {
        // Intentionally UI-less. Proves the Kit links & the universal target builds.
        // A tiny sanity readout is fine; a designed UI is NOT (later phase).
        Text("‹App› — oracle core ready. UI pending.")
            .padding()
    }
}
#Preview { ContentView() }
```
Wire each Kit into `project.yml` `packages:` + the app target `dependencies:` so `import <Kit>` compiles. Run `xcodegen generate`.

---

## 7. WORKFLOW (do in this order, per app)

1. **Plan first.** For the chosen app, write `calculator_candidates/<app>.swift/PLAN.md`: the Kits, each Kit's `<Topic>` functions, and — per function — the **cited oracle** and the specific worked value(s) you will pin. Get human ✅ on the plan before coding.
2. **Harvest** the math + oracle values from the matching `calculators/` folder(s); consolidate into the new Kit(s).
3. **Python pre-check** any non-trivial formula (§5); record residuals.
4. **Write the Kit** (§3) + **the oracle corpus, integrity guard, and match-checker tests** (§4).
5. **`swift test`** in each Kit → **green**. This is the gate. (`cd Kits/<Section>/<Kit> && swift test`.)
6. **`xcodegen generate`** + `xcodebuild -scheme <app> -destination 'generic/platform=iOS' build` **and** `platform=macOS` → BUILD SUCCEEDED with the placeholder shell.
7. **STOP at Phase 1.** Report: per Kit, #oracles, sources cited, `swift test` result; per app, iOS+macOS build result. **Await human go before Phase 2 (UI, §10).**

---

## 8. DEFINITION OF DONE — Phase 1 (per app)
- [ ] `PLAN.md` approved (Kits + cited oracles listed).
- [ ] Every Kit: Foundation-only, `public enum` math, `///` docs, MODEL CAVEAT where apt.
- [ ] Every Kit: `Oracles.swift` (each entry cited), integrity guard, oracle-backed + identity + invariant tests.
- [ ] `swift test` **green** in every Kit; **no** expected value lacks a cited `source`.
- [ ] Universal SwiftUI app builds on **iOS and macOS** with the placeholder shell (Kits linked).
- [ ] **No** UI, marketing, ASC, or upload. Nothing committed without explicit human go.

---

## 9. THE COMPASS (why this matters — one paragraph)
These are renovations of abandoned-but-demanded pro/technical niches. The moat is **validated math you can trust** — the antidote to ad-ridden incumbents and hallucinating LLMs. Buy-once, no ads, no subscription. Oracle-first means: **a testable, cited core before any pixel of UI.** You are building exactly that core. Get the numbers provably right; the UI comes in **Phase 2** (§10) — build-verified, not simulator-verified.

---

## 10. PHASE 2 — Generate the UI (build + `#Preview` only, NO simulator)

Start only **after Phase 1 is green and the human says go**. Build the real per-tool UI for each app. **Verification is `xcodebuild build` (iOS + macOS) + authored `#Preview`s — never a booted Simulator or screenshot.**

### 10.1 Adopt an existing design system (do NOT invent one, do NOT run a visual loop)
Port the design-system primitives from a shipped app — `overtonelab.swift/` (studio-matte glass) or `truecourse.swift/DesignSystem` — into `<App>/Views/`. Replace **in place**; do **not** add a separate `DesignSystem/` folder to `project.yml` or you double-declare types. Bring:
- **Color + section-accent system** (per-section accent; pick one accent per section for this app).
- **`.glassCard()`** surface modifier + matte "instrument" background.
- **`NumberField(range:)`** — numeric input with an explicit **min…max on EVERY input** (non-negotiable; the Kit guards illegal domains, the field prevents illegal entry).
- **`ResultRow(unit:emphasis:)`** — labeled, unit-suffixed result; monospaced hero numbers for emphasized outputs.
- **`SubScreenPicker`** — segmented control for multi-screen tools.
- **`Fmt`** formatting helpers; keep `ColorHex`/`Format`.

### 10.2 Catalog + navigation (universal, size-class-adaptive)
- A `ToolSection` enum (sections) → `Tool` enum (tools); each `Tool` → `section`, `title`, `subtitle`, SF `symbol`, sample value; per-tool accent inherited from its section.
- **Root:** `NavigationSplitView` on iPad/Mac (regular width) · grid + `NavigationStack` on iPhone (compact). Iterate `ToolSection.allCases` (a single-tool section renders fine).
- Optional favorites store: star **overlaid** on the `NavigationLink` (its own `accessibilityIdentifier`) — not nested, or the tap navigates instead of toggling.

### 10.3 Per-tool view + view-model (presentation only — ZERO math in the view)
- `@MainActor final class <Tool>ViewModel: ObservableObject` with `@Published` inputs and **computed** outputs that call the `*Kit` statics. **All math stays in the Kit**; the view/VM only formats + displays.
- `<Tool>ToolView` composes `NumberField(range:)` inputs → `ResultRow` outputs inside `.glassCard()`; `SubScreenPicker` when multi-screen.
- Put an `accessibilityIdentifier` on each input + emphasized result (for a *future* UI-test phase — do **not** write or run UI tests now; they need a sim).

### 10.4 Verify WITHOUT a simulator
- **Author an Xcode `#Preview` for every tool view** — default state at minimum, plus a dark-mode preview (`.preferredColorScheme(.dark)`). Previews compile + render the view statically **without booting a sim** — they are your visual self-check surface.
- `xcodegen generate` → `xcodebuild -scheme <app> -destination 'generic/platform=iOS' build` **and** `-destination 'platform=macOS' build` → **BUILD SUCCEEDED**.
- That's the gate. Do **not** `simctl boot`, `xcrun simctl io … screenshot`, or run the app.

### 10.5 Stop
Report per app: sections/tools built · design system adopted · iOS + macOS **BUILD SUCCEEDED** · previews authored. Hand to the human for the on-device visual review (their gate). No UI tests, no capture, no upload.

---

## 11. DEFINITION OF DONE — Phase 2 (per app)
- [ ] Design-system primitives adopted into `<App>/Views` (not a separate package; no double-declared types).
- [ ] `ToolSection`/`Tool` catalog + size-class-adaptive root (SplitView iPad/Mac · grid iPhone).
- [ ] Every tool: view + `@MainActor` view-model; **all math via the Kit**, none in the view.
- [ ] **Min…max on every `NumberField`**; unit-suffixed `ResultRow`s; `accessibilityIdentifier`s set.
- [ ] An Xcode `#Preview` (light + dark) for every tool view.
- [ ] iOS **and** macOS **BUILD SUCCEEDED**.
- [ ] **No** simulator run, screenshot, UI test, marketing, ASC, or upload. Nothing committed without explicit human go.
