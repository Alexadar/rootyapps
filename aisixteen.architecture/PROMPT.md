# BUILD PROMPT — AISixteen Architecture, scaffold (mocks only, model later)

**Start here.** Open this directory in Claude Code, enter **plan mode**, read this file top to
bottom. It assumes you know nothing about this repo.

**This run builds everything except the model.** UI, storage, iCloud, the long-render experience,
Live Activity, platform behaviour — all running end to end against a **mock generator**. The real
diffusion pipeline lands later and must slot in behind a protocol **without the UI changing**.

---

## 1. Where you are

`rootyapps`, a monorepo of standalone iOS/macOS apps by a solo developer.

```
rootyapps/
├── CLAUDE.md                     monorepo rules — read it
├── marketing/                    SHARED library — NEVER fork into an app folder
├── aisixteen.models/             SHARED model work — NEVER fork. See §11.
├── aisixteen.walpapers/          sibling app, IN PROGRESS — see §2
├── aisixteen.studio/             the third sibling — stay visibly distinct, §7
├── uitests.md                    shared UI-test doc
├── storypole/ · overtonelab.swift/   structural references (project.yml, Kits)
└── aisixteen.architecture/       ← you are here
```

**Portfolio rules:** paid-upfront or free + a **single** one-time unlock. Never ads, never
subscription, never consumables, never credits. Draft and stage only.

---

## 2. What the app is

**On-device AI redesign of interiors and exteriors.** The user photographs a room or a facade,
picks a direction, and the app generates a redesign **entirely on their device**.

**No account, no sign-in, no credits, no subscription, no ads, no network — ever.** Identical
behaviour in Airplane Mode.

**Universal: iPhone, iPad, Mac — one app, Universal Purchase.**

### On the wallpaper app — reference, not dependency

`aisixteen.walpapers` is the first app in this family and establishes the shared **Liquid Glass
system**. **It is not finished.** Read its `PROMPT.md` and design bundle for the *system* — glass
API usage, the morph spec, the mock-seam pattern — but **do not depend on its code existing, and do
not wait for it.** Build this app standalone. Where the two disagree, **your own handoff wins**.

---

## 3. ⚠️ The design handoff — read it before anything else

**`marketing/handoff/` in this folder is the authority.**

- **`README.md`** — the spec. Read all of it.
- **`AISixteen Architecture Mockups.dc.html`** — the board; open in a browser, drag the Result handle
- **`Swift/`** — **compilable SwiftUI mockups** of every screen: `RootView`, `CaptureView`,
  `DirectionView`, `GeneratingView`, `ResultView`, `LibraryView`, `RedesignActivity`,
  `DesignSystem`, `GenerationSeam`. **Static state, mock generator — a starting point, not
  production code.** Read them before writing anything.

### ⚠️ Scope decisions in the handoff that override earlier plans

Two capabilities were **deliberately cut** to match what the model can actually do. **Do not build
them and do not imply them in any copy:**

- **No segmentation.** The model redesigns the **whole frame**, conditioned on depth. **No
  region-picking UI anywhere.** No "change only the sofa."
- **No measuring.** **No dimension callouts, no metric claims.** Depth conditioning means only:
  *"walls, windows and proportions stay put."* That is the whole geometry claim.

**Direction is structured presets that seed an editable prompt field** — presets are prompt macros;
free text is optional and never required.

### Tokens

Ink `#1D1A17` · **accent terracotta `#B4552D`, this app only** — drains to neutral during generation
· canvas `#EFEBE4` / `#F4F1EB` · glass white .60–.72, blur 18–24 pt, saturate 1.7 · radii capsule
999 / card 26 / sheet top 34 / preset 18 · SF Pro, px = pt · morph spring response **0.8**, damping
**0.85** · milk veil white .22, blur 26→0 pt.

---

## 4. Liquid Glass — current APIs only

`.glassEffect()` · **`GlassEffectContainer`** · `glassEffectID` + `@Namespace` ·
`.buttonStyle(.glass)`.

⚠️ **Never `.ultraThinMaterial` / `.regularMaterial` / `.thinMaterial`.** The legacy
`aisixteen.studio.old` is built on those — the previous generation, and exactly what not to inherit.

**Shell:** floating glass segment (Redesign · Library) in **one `GlassEffectContainer`** — **not a
`TabView`**.

---

## 5. The seam — mocks now, model later

`marketing/handoff/Swift/GenerationSeam.swift` already defines it: an **`ImageGenerator` protocol
with step-based `GenerationProgress` — never a 0–1 float** — plus a mock. **Start from that file.**

Ship enough mock implementations to exercise every state in §6: a normal multi-minute run with
intermediate previews, a failing run, and an interruptible one (thermal, background, low battery).

---

## 6. ⚠️ The central problem: renders take minutes

**Named stages**, from the handoff: *Reading the space → Composing → Refining → Full resolution*.
Real step counts. The forming image under the milk veil. Scoped cancel. A queue.

**Interruptions are pauses, never errors** — phone call, thermal, low battery, background-suspended.

**Platform honesty, straight from the handoff:**

- **Minutes of background Neural Engine work is not guaranteed; iOS may suspend.** Checkpoint the
  denoising state, resume on foreground, complete via **local notification**.
- **Thermal throttling is observed** (`ProcessInfo.thermalState`), **never predicted.**
- **Time-left is a rolling estimate from measured step duration** — not a fixed guess.
- **Live Activity** (iOS): forming thumbnail, stage, step x/y, queue depth. Suspended reads
  **"Waiting for you"** — **never fake progress.**
- **Mac: no Live Activity** — standard notification, sidebar shell, and **no "Set as Desktop"**.

---

## 7. Staying visibly distinct from Studio

Both apps take a photo and return a modified photo — Guideline **4.3** risk. The separation must
show in the UI and the screenshots.

| | |
|---|---|
| **Architecture** | **spaces** — depth-preserved geometry, structured style presets, minutes-long renders, before/after proposal |
| **Studio** | **images** — strength dial, scoped masks, the original preserved, tens of seconds |

**If a screen would sit equally well in Studio, it is wrong.**

---

## 8. Screens

Per the handoff: **Capture** (live coach line — level/distance/light; Interior·Exterior segment;
library import) · **Direction** (photo header with depth badge + Retake, preset cards, prompt field,
variation count, CTA priced in minutes) · **Generating** (§6) · **Result** — **wipe slider
recommended**, tap-to-flip and hold-to-peek secondary; VoiceOver treats it as **one adjustable
element** · **Library** — grouped by space, variations under each.

---

## 9. Storage

Projects live in the app's **iCloud ubiquity container**, visible in Files, synced. Declare
`NSUbiquitousContainers`. Store source photo, depth, preset, prompt, seed and every variation.
**Handle iCloud disabled** with a local fallback, and files not yet downloaded from another device.

⚠️ **User-owned storage language only.** iCloud is not a server; nothing may imply an account.

---

## 10. Tests — write both, run only the unit tests

- **Write unit tests and UI tests.**
- **Execute the unit tests.** They must pass before you report done.
- **Do NOT execute the UI tests.** Write them, leave them; the owner runs them.

**Test the state space** — the house rule; a dead toggle shipped once here because tests only saw
default state.

Axes: job **queued / running / paused (each interruption cause) / resumed / complete / failed /
cancelled** · **iCloud available / unavailable** · **interior vs exterior** · **preset vs edited
prompt** · **variation count** · **Reduce Transparency on/off** · **Dynamic Type to AX5**.

**Checkpoint-and-resume is the one most likely to be broken.** Cover it explicitly.

**Accessibility floor:** Dynamic Type to **AX5** (grids reflow to one column), VoiceOver on every
control and the comparison, hit targets ≥ **44 pt**, **Reduce Transparency → opaque `#F6F3ED`** with
hairline borders and identical layout, **Reduce Motion → morph becomes cross-fade**, intermediates
as stepped stills.

---

## 11. The model — later, and it lives in `aisixteen.models/`

**Do not convert, download or commit any model in this run.**

`../aisixteen.models/` is the **shared** model folder for all three AISixteen apps — conversion
scripts, asset-pack manifests, and the record of which model version each app is on. **Never fork it
into this app**, same rule as `marketing/`.

Weights are **never committed** and never end up in a build: each app ships its model as an
**Apple-hosted Background Assets asset pack**. Artefacts (`*.mlpackage`, `*.mlmodelc`,
`*.safetensors`, packed `.aar`) are build outputs and stay out of git.

**Your job is to leave a clean seam** (§5) so that pack drops in later with no UI change.

---

## 12. Project setup and ASO

**The App Store record exists and is being prepared for submission. Do not create one.**

| | |
|---|---|
| App name | **AISixteen Architecture** (22/30) |
| Bundle identifier | **`oleksandr.aisixteen.architecture`** |
| Apple ID | **6475354624** · SKU `0000008` |
| Versions | **iOS · macOS · visionOS 1.0**, all `PREPARE_FOR_SUBMISSION`, `AFTER_APPROVAL` |

### ⚠️ ASO is empty — and it is load-bearing

| Field | State |
|---|---|
| Name | ✅ set |
| **Subtitle** | **EMPTY** (0/30) |
| **Keywords** | **EMPTY** (0/100) |
| **Description** | **EMPTY** |
| Category · age rating | **NOT SET** |

**The sibling shows the target.** `AISixteen Wallpapers` (1662226479) has subtitle
*"On-device wallpaper maker"* (25/30), keywords 89/100 —
`wallpaper,background,offline,ai art,generator,image,4k,lock screen,desktop,no ads,private` — and a
1,891-character description. **Match that level of completeness.**

**Draft** subtitle, keywords and description and **put them in your report for the owner** —
**do not write them to App Store Connect.** Rules: the name already carries the head noun; never
repeat a term across name/subtitle/keywords, because **authority does not stack**; keywords are
comma-separated with **no spaces after commas**.

### Build config

- `PRODUCT_NAME = AISixteen Architecture`. **Never name a target `*.swift`** — Review **5.2.5**
  rejects "Swift" in a shipped product name; with `GENERATE_INFOPLIST_FILE` the generator takes
  `CFBundleName` from `PRODUCT_NAME`. This has caused a real rejection here.
- Match `storypole/`: `project.yml` (XcodeGen). `MARKETING_VERSION` 1.0.0.
- Targets: one universal app (iPhone/iPad/Mac) + unit tests + UI tests.
- ⚠️ **A visionOS version exists on the record but is out of scope.** Flag it; do not build it.
- ⚠️ **No territory availability** — on sale nowhere. Owner's call; flag, don't set.

---

## 13. 🛑 Stop and ask

**Creating an App Store version, submitting, price, territory availability, category, age rating,
and writing metadata to App Store Connect are the owner's decisions.**

Also stop for: the **visionOS** version · **monetization** (undecided — **do not build an IAP**) ·
anything in the handoff the platform will not support.

---

## 14. Deliver a plan first

The seam as you will extend `GenerationSeam.swift`; the multi-minute experience including
checkpoint/resume, Live Activity and every interruption; the storage model including
iCloud-unavailable; the screen list mapped to the handoff's Swift files; the test matrix with which
tests you will run and which you will only write; your drafted ASO copy; and the §13 questions.

**Then build it so the mock runs end to end** — capture a photo, pick a preset, start a render,
leave the app, get a notification, come back, and wipe between before and after.
