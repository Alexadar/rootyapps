# BUILD PROMPT — AI wallpaper generator, scaffold (no model yet)

**Start here.** Open this directory in Claude Code, enter **plan mode**, read this file top to
bottom. It assumes you know nothing about this repo.

**This run builds everything except the model.** UI, storage, iCloud sync, progress plumbing,
platform behaviour — all of it, running end to end against a **mock generator**. The real
Stable Diffusion pipeline arrives in a later pass and must drop in behind a protocol without the
UI changing.

---

## 1. Where you are

`rootyapps`, a monorepo of standalone iOS/macOS apps by a solo developer.

```
rootyapps/
├── CLAUDE.md                          monorepo rules — read it
├── marketing/                         SHARED — NEVER fork into an app folder
├── docs/DESIGN_BRIEF_wallpaper.md     ← THE DESIGN BRIEF. Read it first.
├── uitests.md                         shared UI-test doc
├── aisixteen.studio.old/            the predecessor — inspiration, mostly to discard
├── storypole/ · overtonelab.swift/    structural references (project.yml, Kits)
└── aisixteen.walpapers/               ← you are here
```

**Portfolio rules:** paid-upfront or free + a **single** one-time unlock. Never ads, never
subscription, never consumables. Draft and stage only — creating an App Store version, submitting,
or changing price are the owner's decisions.

---

## 2. What the app is

**An on-device AI wallpaper generator.** User types a prompt (or taps *Surprise me*), the image is
generated **entirely on device**, and saved to the app's **iCloud folder**.

**No account. No sign-in. No credits. No subscription. No ads. No network — ever.** The app must
behave identically in Airplane Mode.

**Two screens — Create and Gallery — plus a one-time first-run gate.** Resist a third.

**Universal: iPhone, iPad, Mac.**

---

## 2a. ⚠️ The design bundle — read it before anything else

**`design_handoff_aisixten_wallpapers/` in this folder is the authority.** It is
**high-fidelity**: colours, type sizes, spacing, radii and copy are **final**. HTML px map **1:1 to
pt**. SF Pro = system font.

- **`README.md`** — the spec. Screens, states, tokens, interactions. Read all of it.
- **`AISixten Wallpapers Mockups.dc.html`** — open in a browser; one pan/zoom board, turns stacked
  newest-first, each mock badged (`2a`, `4a`, …)

### ⚠️ Canonical vs archive — get this wrong and you build the wrong app

**Canonical design = WHITE GLASS, turns 2–4.**

**Turn 1 is dark glass and is archive/reference only — with five exceptions** whose layouts and
annotations still apply but must be **re-skinned in white glass**:

| Keep from turn 1 | What it is |
|---|---|
| **1b** | the morph spec |
| **1c** | gallery layouts |
| **1d** | iPad |
| **1f** | tokens |
| **1h** | reduced-motion / reduced-transparency modes |

`../docs/DESIGN_BRIEF_wallpaper.md` is the earlier brief and remains valid on principle — where it
and the bundle disagree, **the bundle wins**.

---

## 3. The seam — this is the point of this run

**Everything talks to a protocol, never to a model.**

```swift
protocol ImageGenerator {
    func generate(prompt: String,
                  aspect: AspectRatio,
                  seed: UInt32?,
                  progress: @escaping (GenerationProgress) -> Void) async throws -> GeneratedImage
    func cancel()
}
```

Ship **two** implementations in this run:

- **`MockImageGenerator`** — waits realistically (**10–30 s**, matching real on-device diffusion),
  emits **step-based progress**, and produces placeholder images. It must also emit **intermediate
  previews** so the "image emerging from noise" UI (design brief §4) can be built and judged now.
  Simulate that with progressive blur/noise reduction over a bundled sample image.
- **`FailingImageGenerator`** — for building and testing the error path.

**Design `GenerationProgress` to carry what real diffusion actually provides**: current step, total
steps, and an optional intermediate image. **Do not model it as a 0–1 float.** Getting this
interface right now is the whole reason for the mock — the real pipeline must slot in with no UI
change.

This is the same mock/sidecar seam pattern used elsewhere in this repo (see NoteScan's
MagicService). Follow it.

### The morph is specified — build it exactly (bundle `1b`)

One glass object, `glassEffectID("job")`, all inside a single `GlassEffectContainer`:

Create capsule → **widens into the progress capsule** (0→0.45 s, spring response **0.8**, damping
**0.85**; tint drains to neutral, cancel appears inside) → at **~step 5** the capsule **grows into
the picture frame** as the first latent decodes → final step: frame expands **full-bleed** (0.5 s
spring), capsule morphs once more into *Save for Wallpaper*.

**Cancel plays it in reverse. Failure stops the capsule, drains tint, morphs into the failure card.**

Your mock must emit intermediate previews on a cadence that makes this work — the bundle specifies
latents decoded **every 2–3 steps**, under a **milk veil** (white overlay `rgba(255,255,255,.22)`,
blur easing 26→0 pt).

---

## 3a. The first-run gate — in scope for this run

**The model arrives as an Essential asset pack via Apple-Hosted Background Assets** (2.6 GB;
`BAEssentialDownloadAllowance` / `BAEssentialMaxInstallSize` set to real values). The 200 GB
per-app allowance is free with Developer Program membership.

**Four states, specified in bundle `4a`:** Consent · Downloading · Interrupted · Ready.

Three rules from the spec that are not negotiable:

- **There is no skip.** The app does not work without the model.
- **Download progress is real bytes from `BADownloadManager` — never simulated.** (The *generation*
  progress is mocked in this run; the *download* progress is not.)
- **Interrupted state carries its meaning in words, not colour alone** — the bar desaturates to 25%
  ink, and the text says what happened. Two actions: *Use cellular this once* (scoped override) and
  *Keep waiting*.

**The gate never reappears once the model is installed.**

⚠️ **Decide and propose:** without a real 2.6 GB pack to download yet, how do you exercise these four
states? A small stand-in asset pack is probably right — but the `BADownloadManager` code path must
be the real one, not a mock, because the spec forbids simulated byte progress.

### `RootView` structure

If model not installed → **FirstRunGate**. Otherwise a **two-screen shell with a floating glass
segment control** (Create · Gallery) — **not a `TabView`** — inside **one `GlassEffectContainer`**.

---

## 4. Storage — iCloud app folder

Generated images live in the app's **iCloud ubiquity container**, visible in the Files app and
synced across the user's devices.

- Declare `NSUbiquitousContainers` in Info.plist so the folder is user-visible
- **Store the prompt with the image** — the design brief requires "regenerate from this prompt", so
  prompt, seed, aspect ratio and date are metadata that must survive
- **Handle iCloud being unavailable or disabled.** A user with iCloud off must still be able to use
  the app — local fallback, and say what happens
- Handle download-on-demand: a file synced from another device may not be local yet
- No database unless you justify it; files plus sidecar metadata is probably right

⚠️ **iCloud is the user's own storage. It is not a server.** Nothing about it may imply an account
or a service.

---

## 5. Platform behaviour — the asymmetry matters

**macOS can set the desktop wallpaper. iOS cannot.** There is no public iOS API — the best any app
can do is save to Photos and tell the user where to go.

- **Mac:** a real *Set as Desktop* using `NSWorkspace.setDesktopImageURL`, working on the current
  display. Consider multiple displays.
- **iOS/iPadOS:** save to Photos, then an honest, short handoff. **Do not imply the app set the
  wallpaper.** That is the first 1-star review.

**Aspect ratio is a real input** — phone portrait, iPad, desktop widescreen are different
generations, not crops. Wire it through the protocol now even though the mock ignores it.

---

## 6. Design system — Liquid Glass, current APIs only

`.glassEffect()` · **`GlassEffectContainer`** · `glassEffectID` + namespace for the
Create→progress→result morph · `.buttonStyle(.glass)`.

⚠️ **No `.ultraThinMaterial`, `.regularMaterial` or `.thinMaterial` anywhere.** The predecessor
`aisixteen.studio.old` is built on `.ultraThinMaterial` throughout — that is the previous
generation and is exactly what not to inherit.

**Respect Reduce Transparency and Reduce Motion.** In a glass-heavy design these are not optional,
and the design brief requires variants.

**Legibility over glass in both themes** — prove controls read over a near-black wallpaper and a
near-white one. This is where glass designs fail.

---

## 7. Project setup

- Folder is `aisixteen.walpapers` — **never name a target `*.swift`.** App Review **5.2.5** rejects "Swift"
  in a shipped product name, and with `GENERATE_INFOPLIST_FILE` the generator takes `CFBundleName`
  from `PRODUCT_NAME`. This has caused a real rejection in this repo.
- **The App Store record already exists — do not create a new one.**

  | | |
  |---|---|
  | App name | **AISixteen Wallpapers** |
  | Bundle identifier | **`oleksandr.aisixteen.wallpapers`** |
  | Apple ID | **1662226479** · SKU `0000007` |

- **`PRODUCT_NAME = AISixteen Wallpapers`**. The bundle ID is registered and permanent — use it
  exactly, never invent one.
- Sibling records already exist for the two follow-on apps: **AISixteen Studio**
  (`oleksandr.aisixteen.studio`, 1659835815) and **AISixteen Architecture**
  (`oleksandr.aisixteen.architecture`, 6475354624). **This app is the first of the three** — the
  design system and the `ImageGenerator` seam you build here get reused, so keep both clean enough
  to lift.
- Match `storypole/`: `project.yml` (XcodeGen) → `.xcodeproj`
- `MARKETING_VERSION` 1.0.0
- Targets: one universal app (iPhone/iPad/Mac) + unit tests. **No UI tests in this run.**
- Deployment target: whatever Liquid Glass requires. State it.

---

## 8. Tests

Unit tests only. **Test the state space** — the house rule, and a dead toggle shipped once here
because tests only saw default state.

The axes in this app: generation **idle / running / complete / failed / cancelled** ·
**iCloud available / unavailable** · **aspect ratios** · **empty vs populated gallery** ·
**Reduce Transparency on/off**.

Cancellation mid-generation is the one most likely to be broken — test it explicitly.

---

## 9. 🛑 Stop and ask

**Creating an App Store version, submitting, or changing price are the owner's decisions.**

Also stop for:

- **Monetization.** Paid-upfront vs free + single unlock is undecided. **Do not build an IAP.**
- The stand-in asset pack question (§3a) — how to exercise the four gate states with real
  `BADownloadManager` byte progress
- Anything in the design brief the platform won't support — flag it rather than designing around it

---

## 10. Deliver a plan first

Before code: the `ImageGenerator` protocol and `GenerationProgress` shape, with your reasoning for
why the real diffusion pipeline will slot in unchanged; the storage model including the
iCloud-unavailable path; the screen list with every state from the design brief; the per-platform
differences; the test matrix; and the open questions from §9.

**Then build it so the mock runs end to end** — type a prompt, watch progress, see an image appear,
find it in the gallery, and on Mac set it as the desktop.
