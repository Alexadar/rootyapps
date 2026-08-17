# BUILD PROMPT — AISixteen Studio, scaffold (mocks only, model later)

**Start here.** Open this directory in Claude Code, enter **plan mode**, read this file top to
bottom. It assumes you know nothing about this repo.

**This run builds everything except the model.** UI, the editing model, storage, iCloud, platform
behaviour — all running end to end against a **mock enhancer**. The real diffusion pipeline lands
later and must slot in behind a protocol **without the UI changing**.

---

## 1. Where you are

`rootyapps`, a monorepo of standalone iOS/macOS apps by a solo developer.

```
rootyapps/
├── CLAUDE.md                     monorepo rules — read it
├── marketing/                    SHARED library — NEVER fork into an app folder
├── aisixteen.models/             SHARED model work — NEVER fork. See §11.
├── aisixteen.walpapers/          sibling app, IN PROGRESS — see §2
├── aisixteen.architecture/       the third sibling — stay visibly distinct, §7
├── aisixteen.studio.old/         THE LEGACY BUILD of this same record — see §2
├── uitests.md                    shared UI-test doc
├── storypole/ · overtonelab.swift/   structural references
└── aisixteen.studio/             ← you are here
```

**Portfolio rules:** paid-upfront or free + a **single** one-time unlock. Never ads, never
subscription, never consumables, never credits. Draft and stage only.

---

## 2. What the app is — and what it replaces

**On-device AI photo enhancement.** The user brings a photo they care about; the app improves it
**entirely on their device**.

**No account, no sign-in, no credits, no subscription, no ads, no network — ever.** Identical in
Airplane Mode.

**Universal: iPhone, iPad, Mac — one app, Universal Purchase.**

### `aisixteen.studio.old` is the legacy build of this same record

Same bundle ID, same App Store record. It is a **cloud SaaS** — Firebase, Google Sign-In, SocketIO,
credit packs, login, account modals, an API layer. **This build replaces all of it.**

**Take:** the create-flow rhythm (`Components/CreateItemPopup.swift`) and image presentation
(`FantasticImage.swift`).
**Discard entirely:** `Login`, `AccountModal`, `BuyPacksPopup`, `CreditPack`, `Price`, `User`, `Api`,
`Chat`, `Collection`, and every dependency behind them. **And do not inherit its visual system** —
it is `.ultraThinMaterial` throughout (§4).

### On the wallpaper app — reference, not dependency

`aisixteen.walpapers` establishes the shared **Liquid Glass system** and the mock-seam pattern.
**It is not finished.** Read it for the *system*, but **do not depend on its code existing and do not
wait for it.** Build standalone. Where they disagree, **your own handoff wins**.

---

## 3. ⚠️ The design handoff — read it before anything else

**`marketing/design_handoff_aisixteen_studio/` in this folder is the authority.**

- **`README.md`** — the spec, final values
- **`AISixteen Studio Mockups.html`** — one pan/zoom board, mocks badged **`1a`…`1m`**.
  **HTML px map 1:1 to pt.** SF Pro = system font.

| id | Screen |
|---|---|
| 1a | Import · 1b Edit · 1c Applying · 1d Result · 1e Export sheet · 1f Library |
| 1g | iPad — floating right column, Pencil → Brush |
| 1h | Mac — sidebar, glass toolbar, drag-and-drop, **Space = hold original, ⌘Z = revert** |
| 1i–1j | Specs — strength detents, selection model, comparison gestures, VoiceOver, original-protection pipeline |
| 1k | Reduce Transparency / Reduce Motion · 1l icon · 1m system deltas + **Architecture distinctness test** |

---

## 4. The mental model — editor, not generator

**The user's photo is the subject. There is no prompt field anywhere.** The primary verb is
**Enhance**; the primary dial is **Strength**; the original is one gesture away at all times.

### The original is sacred

**The original file is read-only and never rewritten.** An edit is a **recipe** — masks + strengths
+ seed — producing an **enhanced copy**, which is the only file ever written. **Fully revertible,
forever.**

### Strength — one dial, named detents

`0–100` rail. **Whisper 15** (noise / micro-contrast, pixel-faithful) · **Subtle 35 — the default** ·
**Balanced 55** (reconstructs fine detail) · **Strong 80** (full re-render, inline warning *"may
alter fine details"*).

⚠️ **After the pass, the dial becomes a live blend** — `0` is the original bit-for-bit, and **backing
off never re-runs the model.** Each scope holds its own strength; scopes compose into one recipe:
`original + (mask × strength × pass)`.

### Selection

**Whole photo / Subject / Background / Brush.** On iPad, **Pencil → Brush**.

### Comparison — three ways, always available

1. **Press-and-hold** anywhere shows the original (Mac: **hold Space**); release snaps back
2. **Split handle** — persistent, draggable edge to edge, **present during Applying**
3. **Strength → 0**

**VoiceOver:** the handle is **one adjustable element** — *"Comparison. Showing enhanced.
Adjustable."* Swipe up/down = 10% steps announcing *"70 percent enhanced."* Double-tap-and-hold
speaks *"Showing original"* while held. The strength slider announces **detent names, not numbers**.
Hit targets ≥ **44 pt**; handle grip 38 pt visual on a 56 pt target.

---

## 5. Liquid Glass and the morph

`.glassEffect()` · **`GlassEffectContainer`** · `glassEffectID` + `@Namespace` ·
`.buttonStyle(.glass)`. ⚠️ **Never `.ultraThinMaterial` / `.regularMaterial` / `.thinMaterial`.**

**The capsule morph — same object, same spec as Wallpapers**, spring response **0.8**, damping
**0.85**, **one `glassEffectID` in one `GlassEffectContainer`**:

Enhance capsule → widens into the progress capsule (tint drains to neutral, **Cancel appears
inside**) → morphs into **Save…** on completion. **Failure stops the capsule, drains tint, morphs
into the failure card.** Cancel plays it in reverse and **the photo returns untouched.**

---

## 6. Applying — design the wait honestly

**Tens of seconds, single pass.** Progress is **steps, not a percentage** — *"Enhancing · step 9 of
20."* The image resolves live under the **milk veil** (white `rgba(255,255,255,.22)`, blur 26→0 pt)
against the original split. **Cancel is always present.**

---

## 7. Staying visibly distinct from Architecture

Both take a photo and return a modified photo — Guideline **4.3** risk. Board **`1m`** carries the
distinctness test; satisfy it.

| | |
|---|---|
| **Studio** | **images** — strength dial, scoped masks, original preserved, tens of seconds, **no prompt field** |
| **Architecture** | **spaces** — depth-preserved geometry, style presets, minutes-long renders |

**If a screen would sit equally well in Architecture, it is wrong.**

---

## 8. The seam — mocks now, model later

Everything talks to a protocol, never a model.

```swift
protocol PhotoEnhancer {
    func enhance(photo: CGImage, strength: Double, mask: CGImage?, seed: UInt32?,
                 progress: @escaping (EnhanceProgress) -> Void) async throws -> EnhancedPhoto
    func cancel()
}
```

**`EnhanceProgress` carries step, total steps and an optional intermediate image — never a 0–1
float.** Ship a realistic mock (tens of seconds, intermediate previews) and a failing one.
**`strength` and `mask` must be wired through now** even though the mock ignores them — they are the
product.

---

## 9. Storage

Edits live in the app's **iCloud ubiquity container**, visible in Files, synced. Declare
`NSUbiquitousContainers`.

**Never modify the user's original in Photos.** Persist the recipe — source reference, masks,
per-scope strengths, seed — so any edit re-runs or reverts. **Handle iCloud disabled** with a local
fallback, and files not yet downloaded (board `1f` shows the download-on-demand state).

**Export (`1e`):** Save as new **(default)** / Replace in Photos / Share — with **literal
fate-of-the-original copy.** Never ambiguous.

⚠️ **User-owned storage language only.** iCloud is not a server.

---

## 10. Tests — write both, run only the unit tests

- **Write unit tests and UI tests.**
- **Execute the unit tests.** They must pass before you report done.
- **Do NOT execute the UI tests.** Write them, leave them; the owner runs them.

**Test the state space.** Axes: **strength at each detent (15/35/55/80) plus 0 and 100** · **scope
whole / subject / background / brush** · **scopes composed** · job **idle / running / complete /
failed / cancelled** · **iCloud available / unavailable** · **Reduce Transparency on/off** ·
**Dynamic Type**.

⚠️ **"The original survives" must never break.** Assert it on **every** exit path — cancel, failure,
export-as-new, replace-in-photos, delete, app kill. And assert **strength 0 returns the original
bit-for-bit** after a pass.

---

## 11. The model — later, and it lives in `aisixteen.models/`

**Do not convert, download or commit any model in this run.**

`../aisixteen.models/` is the **shared** model folder for all three AISixteen apps — conversion
scripts, asset-pack manifests, and which model version each app is on. **Never fork it into this
app**, same rule as `marketing/`.

Weights are **never committed** and never end up in a build: each app ships its model as an
**Apple-hosted Background Assets asset pack**. Artefacts are build outputs, out of git.

**Leave a clean seam** (§8) so the pack drops in later with no UI change.

---

## 12. Project setup and ASO

**The App Store record exists and is being prepared for submission. Do not create one.**

| | |
|---|---|
| App name | **AISixteen Studio** (16/30) |
| Bundle identifier | **`oleksandr.aisixteen.studio`** |
| Apple ID | **1659835815** · SKU `0000006` |
| Versions | **iOS · macOS · visionOS 1.0**, all `PREPARE_FOR_SUBMISSION`, `AFTER_APPROVAL` |

### ⚠️ ASO is empty — and it is load-bearing

| Field | State |
|---|---|
| Name | ✅ set — but **16/30, so 14 characters are unused** |
| **Subtitle** | **EMPTY** (0/30) |
| **Keywords** | **EMPTY** (0/100) |
| **Description** | **EMPTY** |
| Category · age rating | **NOT SET** |

**The sibling shows the target.** `AISixteen Wallpapers` (1662226479) has subtitle *"On-device
wallpaper maker"* (25/30), keywords 89/100 —
`wallpaper,background,offline,ai art,generator,image,4k,lock screen,desktop,no ads,private` — and a
1,891-character description. **Match that completeness.**

⚠️ **`AISixteen Studio` carries no head noun** — nothing in it says what the app does. That is the
Kerf Calc mistake, which shipped invisible. The **subtitle must carry the searchable terms**.

**Draft** subtitle, keywords and description and **put them in your report** — **do not write them
to App Store Connect.** Never repeat a term across name/subtitle/keywords; **authority does not
stack.** Keywords comma-separated, **no spaces after commas**.

### Build config

- `PRODUCT_NAME = AISixteen Studio`. **Never name a target `*.swift`** — Review **5.2.5** rejects
  "Swift" in a shipped product name. The legacy folder is exactly why this one is not so named.
- Match `storypole/`: `project.yml` (XcodeGen). **This record has shipped before — check the live
  version and bump the patch.**
- Targets: one universal app (iPhone/iPad/Mac) + unit tests + UI tests.
- ⚠️ **visionOS version exists on the record but is out of scope.** Flag it; do not build it.
- ⚠️ **No territory availability** — on sale nowhere. Owner's call; flag, don't set.

---

## 13. 🛑 Stop and ask

**Creating an App Store version, submitting, price, territory availability, category, age rating,
and writing metadata to App Store Connect are the owner's decisions.**

Also stop for: the **visionOS** version · **monetization** (undecided — **do not build an IAP**) ·
whether anything from the legacy build carries over beyond §2.

---

## 14. Deliver a plan first

The `PhotoEnhancer` protocol and `EnhanceProgress` shape; the recipe model and exactly how the
original is protected at every step; the strength-as-live-blend behaviour after a pass; the scope
composition model; the always-available comparison including VoiceOver; per-platform layouts (`1g`
iPad, `1h` Mac); the storage and export model; the test matrix marking which tests you run and which
you only write; your drafted ASO copy; a short list of what you took from the legacy build and what
you discarded; and the §13 questions.

**Then build it so the mock runs end to end** — import a photo, set strength, brush a region, apply,
hold to compare, drop strength to 0 and confirm the original returns bit-for-bit, export as new, and
verify the original is untouched.
