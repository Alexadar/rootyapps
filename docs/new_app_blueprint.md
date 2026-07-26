# NEW APP BLUEPRINT — end-to-end build automation SOP
_For Opus/Fable. Follow this to build each next niche app. Reuse `overtonelab.swift` as the reference implementation. Human-in-the-loop gates are marked 🛑._

---

## 0. Compass (the framing — never violate)
Renovate **abandoned-but-demanded** niche apps → **oracle-first validated math** → **buy-once, no ads, no subscription** (free-to-try + one-time unlock) → **$0 organic + portfolio flywheel**. Target **LLM-resistant** niches (safety/exam/required/pro); skip commodity. Offline, universal, every displayed number validated. _(See memory `app-business-compass`.)_

**The moat is trust, built in this order:** correct math (tested) → clean design → honest positioning. Ship nothing unvalidated.

---

## 1. The workflow at a glance
| Phase | Owner | Output | Gate |
|---|---|---|---|
| **P0** Discover & decide | Agent (N3) + 🛑Human | target + wound + feature blueprint | build-gates pass |
| **P1** Core logic: Kits + oracles | Agent (autonomous) | `*Kit` packages, `swift test` green | all suites green |
| **P2** 🛑 Pick design direction | Agent (throwaway mocks) + 🛑Human | chosen visual direction | tests green first |
| **P3** Design system + visual loop | Agent (Claude Code in sim) | in-place `Views/` design system, screenshot-iterated | matches direction + HIG |
| **P4** Adopt design + build UI | Agent | universal SwiftUI app, UITests | builds + tests pass |
| **P5** 🛑 Visual review | Human | approve design adoption | — |
| **P6** Marketing media | Agent (Mac) | screenshots + reels | captured & framed |
| **P7** ASO metadata | Agent draft + 🛑Human | name/subtitle/keywords/desc | human approves copy |
| **P8** 🛑 Release | Human (+Agent upload) | submitted to review | URLs + rating + price |

**The three human gates that must happen (never skip):** P2 (pick the design direction *after* oracles green), P5 (visual review of the built UI), P7/P8 (ASO approval + URLs/pricing/submit).

---

## 1.5 What's CONSTANT vs what VARIES per app — this is a skeleton, not a mold
**Constant (the frame):** the P0→P8 workflow · the three human gates · the **oracle-first principle** (a testable core before any UI) · the reusable capture/ASO engine · the compass (buy-once/no-ads/$0/portfolio).

**Varies per app — decide these at P0 and let the pipeline adapt:**
| Dimension | Range across the portfolio |
|---|---|
| **Core-logic type** | pure-math calc (Overtone, TrueCourse) · live-data feed + classification (eartharound → NOAA/GFZ) · sidecar/ML (notescan → camera→OMR→MIDI) · procedural/sim |
| **Oracle source** | published formula + URI (FAA/ISO/RBJ) · standard reference tables · **golden fixtures** (recorded known-good outputs) · **known-record parse** (feed apps: assert a known API record → correct classification) |
| **Design language** | studio-matte (audio) · glass-cockpit (aviation) · avionics (space) — *the DesignSystem **shape** is constant; the **aesthetic** is chosen per domain at P2 and realized by Claude Code in the P3 visual loop* |
| **Capability surfaces** | which of the §1.6 menu the app needs (varies wildly — a tuner needs none; a storm tracker needs notifications + widgets) |
| **Sections/tools · ASO · community** | the domain's screens, keywords, and where its users are |

Don't hardcode "calculator." Generalize to **"the app's validated core + the surfaces that present it."**

## 1.6 Capability-surfaces menu — pick per app at P0 (each reuses the same Kits)
Each surface computes in a **validated Kit** and just *presents* it; each gets its own build + test. Choose by domain:
- **watchOS app** — glanceable/input-light tools (E6B wind + timer; Kp now). Kits are Foundation-only → compile on watchOS unchanged; test the watch tools' displayed values.
- **Widgets (WidgetKit)** — current state at a glance (Kp, next tide, last calc). `TimelineProvider` reads the shared Kit via an **App Group**; snapshot-test the widget.
- **Live Activities / Dynamic Island** — an ongoing session (running timer, active storm). Only where a live session exists.
- **Notifications** — **local** (threshold alerts computed by a Kit — e.g. "Kp ≥ 5") and/or **push** (server-driven → adds a backend + breaks pure-offline; only if the domain demands live alerts). **Alerts must fire on validated thresholds (a tested Kit function) — false alarms are the incumbent grievance.**
- **App Intents / Siri / Shortcuts** — expose tools as intents ("Hey Siri, density altitude for…"); the intent → a Kit call. Deterministic, offline, great for pro tools.
- **iCloud / App-Group sync** — saved calcs/favorites across devices (KVStore or CloudKit). Only if state is worth syncing.
- **Share / action extension · camera / sensor input** — domain-specific (notescan camera→OMR).
- **Apple Intelligence (Foundation Models)** — optional on-device "ask in plain English" front door: **LLM proposes params → the Kit computes** (never the LLM); gated on availability, fallback to fields. Also powers marketing caption-gen (§6).

**Rule:** the surface is a shell over the tested Kit — the moat (validated numbers) is identical everywhere; only the presentation differs.

---

## 2. Repo conventions (replicate this exact shape)
```
<app>.swift/
  project.yml                      # XcodeGen; bundle oleksandr.aisixteen.<app>; team LSKNNBG94G;
                                   #   iOS/macOS 26; INFOPLIST_KEY_ITSAppUsesNonExemptEncryption: NO
  Kits/<Section>/<Name>Kit/        # Foundation-only SPM pkg, oracle-tested (see P1)
    Package.swift  Sources/<Name>Kit/<Topic>.swift  Tests/<Name>KitTests/<Topic>Tests.swift
  <App>/Tools/<Section>/<Name>/    # ToolView + ViewModel + sub-screen views
  <App>/Views/                     # DesignSystem primitives live here after adoption
  <App>/Assets.xcassets
  DesignSystem/                    # P2 throwaway direction mocks + DIRECTION.md + P3 primitive staging (kept out of build)
  tools/RecordWindow.swift         # SCK single-window recorder (Mac reels)
  <App>UITests/                    # ValueChecks + FavoritesChecks (deep-link driven)
  marketing/{raw,aso,reels,audio}  # capture inputs + framed outputs (gitignored media)
  <app>.icon/                      # app icon source
```
Reference: `overtonelab.swift/` (26 tools, 16 Kits, 7 sections). `.gitignore`: build/, .build/, *.xcodeproj, marketing media (png/jpg/mp4/mov/wav), tools/recordwindow — **keep app-icon PNGs tracked**.

---

## 3. Phase spec

### P0 — Discover & decide  · Agent + 🛑Human
- Agent: run the N3 v2 method (`marketing/candidate.finder.md`) — keyword sweep → reviews-RSS grievance/liveness score → tier. Pull the incumbent's App Store description = the **feature blueprint**.
- 🛑Human decides, answering: **why abandoned?** (side-app/retailer-deprioritized = go; dying market = skip), the **5 build-gates** (public-math oracle? no copyright-table? no free-mfr-tool? acceptable liability? confirmed grievance via dated reviews?), **not-a-vacuum** check, and **do-I-relate** (for authentic marketing).
- Output: target + one-line wound + the feature/tool list **+ the per-app variables from §1.5** (core-logic type, oracle source, design language, and the chosen **capability surfaces** from §1.6). Everything downstream keys off these.

### P1 — Core logic: validated Kits  · Agent (autonomous) — THE MOAT
- Put the app's **testable core in Foundation-only `*Kit` packages** (no UIKit, no network in the Kit). The **type varies** (§1.5): pure-math functions · feed **parsers + classifiers** (e.g. NOAA JSON → validated index/flare-class) · ML/sidecar wrappers over golden data. Pattern stays: `public enum <Topic>` static namespace (or `struct: Sendable` for data), unit-suffixed labels, guard illegal domains only (**no UI clamp in Kit**), `///` doc + `Pure, stateless.` + `MODEL CAVEAT:`.
- **Oracle suite per Kit** (Swift-Testing) — the **source varies** (§1.5) but the discipline doesn't: `// Oracle = <cited source + URI>` header; assert worked values vs the authority with explicit epsilons. Choose the oracle mode to match the core-type: **formula+URI** (math), **reference tables** (standards), **known-record parse** (feed apps: a real API record → asserted classification), or **golden fixtures** (recorded known-good — Style-B, only if an authoritative corpus exists). For gnarly formulas, **numerically pre-check in python first** (like the ISO 9613 verification) so constants are evidence-based.
- Package.swift: tools 5.9, `platforms: [.macOS(.v13), .iOS(.v16)]`, one `.target` + `.testTarget`, no deps/resources.
- **Verify: `swift test` green in every Kit.** This is where trust is manufactured — do it before any UI.

### P2 — 🛑 Pick the design direction (the first back-and-forth) · Agent + 🛑Human
- **Only after every Kit oracle suite is green.** No Claude Design, no Figma — Claude Code drives the whole visual phase in-medium.
- Agent generates **3–4 visually distinct directions** as lightweight **throwaway** mocks — an **Artifact / static HTML** (fast to diverge, cheap to discard) *or* a single SwiftUI `PreviewProvider` screen — from a short **direction brief** (template `tmp/aviacalc_design.md`): app purpose, audience, the sections (for accents), signature visualizations, night/red mode, accessibility, and **Apple HIG for the current OS**. Present them side-by-side.
- 🛑**Human picks one direction** (or grafts elements across them). This is the divergence step Claude Design used to own — done here for $0, in the real stack. Record the pick as `DesignSystem/DIRECTION.md` — the north star the P3 loop iterates against.

### P3 — Design system + the Claude Code visual loop · Agent (Claude Code in the simulator)
- Claude Code authors the design system **directly in SwiftUI** — tokens + components matching overtonelab's shape (`OTLColors/OTLComponents/OTLSegmented/OTLTheme`, section-accent system, matte "instrument" surface, monospaced hero numbers). No external handoff; it writes the primitives into `<App>/Views` (see P4).
- **The visual loop — this is what replaces Claude Design's "secret sauce", and it's stronger for native because it runs in the real medium:** **build → render → SEE → critique → edit → re-render**, repeated:
  1. Render each screen via an **Xcode Preview** or boot the **iOS Simulator** (`xcodebuild` build + `simctl boot`).
  2. **Capture the pixels** — `xcrun simctl io booted screenshot <out.png>` (or a Preview snapshot) — and **read the screenshot back with vision** against `DIRECTION.md` + Apple HIG.
  3. **Critique concretely:** spacing/rhythm, contrast + Dynamic Type, safe-area/notch, SF Symbol weight, **light + dark + night/red** mode, tap-target size, hero-number legibility.
  4. **Edit SwiftUI → re-render → re-capture** until it matches the chosen direction. Do a light/dark pass and a small/large Dynamic-Type pass.
- **Why in-medium beats an HTML mock:** it's the *real* SwiftUI on *real* device metrics (safe areas, SF Symbols, Dynamic Type, your night mode) — zero re-translation gap. _(Apple ships official Xcode ↔ Claude Agent SDK support built for exactly this loop.)_
- **Output:** `DesignSystem/` primitives ready to land in `<App>/Views` at P4, plus a folder of loop screenshots showing before→after convergence (feeds the P5 human review).

### P4 — Adopt design + build UI  · Agent
- Ensure the P3 DesignSystem primitives live **in `<App>/Views` and are compiled by the app target — do NOT also add a `DesignSystem/` folder to project.yml or you double-declare types**. Keep `ColorHex`/`Format` helpers.
- Build per-tool folders using `NumberField(range:)` (min/max on every input), `ResultRow(unit:emphasis:)`, `.glassCard()`, `SubScreenPicker`, `Fmt`.
- Size-class-adaptive root: `NavigationSplitView` on iPad/Mac (regular), grid + `NavigationStack` on iPhone (compact). Catalog enum (sections → tools), favorites store, per-tool accent inherited from section.
- **Deep-link/demo env hooks** `<APP>_TOOL` / `<APP>_SCREEN` (raw-value → tool; needed for capture).
- **Build the chosen capability surfaces (§1.6)** — for each selected surface add its target/extension and wire it to the **same Kits**: watchOS app (input-light tools), WidgetKit (App-Group + TimelineProvider), notifications (local, on a **tested** threshold Kit function), App Intents/Siri (intent → Kit call), Live Activities, iCloud/App-Group sync, extensions. Each surface = its own build + a test (widget snapshot, watch value-check, intent result, alert-trigger logic). Not every app has any — a simple tool may ship phone/iPad/Mac only.
- Tests: **ValueChecks** UITest — launch each tool via the `<APP>_TOOL` deep-link, assert the displayed default-state value (deep-link is far more reliable than catalog scrolling as the app grows). **FavoritesChecks** CRUD+persist (star tiles need an independent `accessibilityIdentifier`, overlaid on the NavigationLink — not nested inside it, or the tap navigates instead of toggling).
- **Verify:** `xcodegen generate` + `xcodebuild` iOS + macOS (+ watchOS) SUCCEEDED; UITests pass.

### P5 — 🛑 Visual review · Human
- Human reviews the built-app screenshots from the P3 loop (light/dark/night; phone + iPad + Mac) and approves before spending on marketing. The loop gets it close to the direction + HIG; this is the human taste gate the automated loop can't self-certify.

### P6 — Marketing media  · Agent (Mac)
- **Screenshots:** `make_sim_shots.sh` (iOS/iPad: deep-link each screen via `SIMCTL_CHILD_<APP>_TOOL`, `simctl io screenshot`) + `make_mac_shots.sh` (Mac: launch app, Quartz window-id, `screencapture -o -l`) → `marketing/generate_screenshots.py <params.yaml>` frames them. **Return to home/springboard before the first shot** or you catch a `◄ PrevApp` breadcrumb.
- **Reels:** `marketing/reels/make_reel.sh` (iOS/iPad: XCUITest metronome "reel tour" + `simctl recordVideo` → `frame_reel.py` captions/outro) + `make_mac_reel.sh` (Mac: **`tools/RecordWindow.swift` ScreenCaptureKit single-window recorder** → `mac_frame_reel.py`) → music → `ffmpeg` mux (AAC 256k). Scene captions in `marketing/reels/<app>_scenes*.json`.
- **⛔️ The App Store preview must be UNFRAMED** — screenshots may be framed, previews may not. A gradient bg / device bezel / caption band / outro card is **Guideline 2.3.4** ("framing around the video screen capture", "device images and/or device frames") — it cost Overtone Lab iOS a rejection on 2026-07-09. Upload **`marketing/reels/store_preview.py`** output (full-bleed capture + optional *overlaid* text, which Apple explicitly allows); keep `frame_reel.py` output for the site/socials.
- **Captions:** generate on-device via **Apple Intelligence** (Foundation Models, macOS 26) or hand-write — feed the app's **tool-catalog metadata** (title/subtitle per screen), **not** raw code. Music: Stable Audio (conda `fantastic`) or royalty-free.
- **Mac-capture gotchas (the hard-won moat — memory `mac-window-reel-capture`):** use ScreenCaptureKit `SCContentFilter(desktopIndependentWindow:)` NOT ffmpeg/avfoundation (occlusion); bootstrap `NSApplication.shared.setActivationPolicy(.accessory)` to dodge `CGS_REQUIRE_INIT`; get window-id via Quartz `CGWindowListCopyWindowInfo` NOT AppleScript (blocked); `pkill -9` the single-instance app between deep-linked scenes; grant the Terminal Screen Recording once.

### P7 — ASO metadata  · Agent draft + 🛑Human approve
- Draft per `marketing/autoaso.md`: **Name** (30, front-load head keyword), **Subtitle** (30), **Keywords** (100, comma, no spaces, no dupes vs name/subtitle), **Description** (conversion — NOT indexed for iOS search), **Promo text** (170). Cross-localization overflow across US-indexed locales (§2.3) for extra keyword surface.
- Write via `marketing/logic/update_metadata.py` (raw ASC API + `.p8`; memory `macos-release-via-asc-api`). Media via `upload_screenshots.py` / `upload_previews.py` — **note: `previewType` has NO `APP_` prefix** (memory `aso-media-upload-scripts`).
- 🛑Human approves/tunes keywords + name (the biggest ranking lever).

### P8 — 🛑 Release · Human (+ Agent upload)
- **Agent can:** bump `CURRENT_PROJECT_VERSION`, archive → `-exportArchive` (method app-store-connect) → upload, attach build to version, set primary category — via `.p8`, no MCP. _(For an unreleased first version, bump the **build number**, not MARKETING_VERSION, to keep it debuting at 1.0.0.)_
- **Human only (can't be faked):** Support URL, Privacy-Policy URL, **App Privacy = Data Not Collected**, age rating, **pricing**, and **Submit for Review**.

---

## 4. Monetization & distribution (compass, operationalized)
- **Price:** single tool **$5.99**, suite **$9.99**; model = **free-to-try + one-time unlock**; **never ads/subscription**. Frame: _"Buy once. Own it forever. Less than one month of [subscription competitor]."_
- **Distribution is the #1 risk — a theory is REQUIRED before building:** AEO landing page (static → Cloudflare Pages; `SoftwareApplication`+`FAQPage` JSON-LD + `/llms.txt`; per-intent pages), **portfolio cross-promotion** (your own apps seed each other — the flywheel), catch the **one-time launch discovery window** (ship fully-optimized metadata), and a **one-hour launch seed** into the niche community (not a community you maintain). First 1–2 apps carry the cold-start alone; after that the portfolio carries.

---

## 5. The reels/screenshot generator — containerization theory (asked)
The pipeline built here is the **reusable per-app marketing engine** — and it's also a potential standalone product. Two halves, very different:
- **CAPTURE** (deep-link driving + SCK/simctl recording) → **needs macOS + Xcode + Simulator + windowserver**. **NOT containerizable** (no Simulator/SCK in Linux Docker). Ships as a **direct-distribution notarized Mac CLI/app** — **not Mac App Store** (the sandbox forbids spawning `xcrun`/`simctl`/`xcodebuild` + driving another app). Or run on rented **cloud-Mac runners** (expensive; needs SOC-2 + ephemeral single-use VMs + egress lockdown to safely run uploaded builds).
- **ASSEMBLY** (`frame_reel.py`/`generate_screenshots.py` PIL framing + music + `ffmpeg` mux) → **fully containerizable (Linux/Docker)**. This is the clean SaaS: _raw screenshots/recording in → framed App-Store set + captioned preview reel out._ No Mac, **no build upload, no LLM.**
- **Does it need an LLM?** No — it's deterministic. Only **captions** optionally use **Apple Intelligence on-device** (free, private); feed tool-catalog metadata, **don't scan code**.
- **Product verdict (if ever sold):** containerize the **assembly** half (Model A: upload raw → frame); ship **capture** as a companion Mac CLI (build/pixels never leave the user's Mac → sidesteps both the trust and the isolation problem). Reserve "upload build → cloud-Mac auto-capture" for a serious infra play only.
- **For our purposes:** keep it as the internal engine (per-app scripts). It's already the automation — this blueprint *is* how each app reuses it.

---

## 6. Reusable assets to copy from `overtonelab.swift`
`project.yml` (packages+deps pattern) · Kit template (Package.swift + Sources + Tests, Style-A oracle) · `make_sim_shots.sh` / `make_mac_shots.sh` / `make_all_reels.sh` / `make_mac_reel.sh` · `tools/RecordWindow.swift` · `marketing/aso/*/params.yaml` + `marketing/reels/*_scenes*.json` templates · `marketing/generate_screenshots.py` + `reels/frame_reel.py` + `mac_frame_reel.py` · `marketing/logic/*.py` (ASC) · `overtonelab.swift/DesignSystem/` shape (tokens/components/theme) to regenerate against in the P3 visual loop.

## 7. Definition of done
Kit oracle suites green · iOS + macOS build SUCCEEDED · **each chosen capability surface (§1.6) built + tested** (watch value-check / widget snapshot / intent result / alert-trigger) · ValueChecks + FavoritesChecks pass · DesignSystem adopted (P5 approved) · screenshots + reels generated · ASO metadata written + approved · build uploaded & VALID · 🛑Human: URLs + age rating + price + **Submit**.

---
_This SOP encodes what shipped `overtonelab.swift` and is queued for `truecourse.swift`. Each next app = P0→P8 with the three human gates (design direction, visual review, ASO/release). The engine is reused; only the domain Kits, the design direction, and the ASO copy change per app._
