# BUILD PROMPT — Froggo 2: Frog Jump (3D)

**Start here.** Open this directory in Claude Code, enter **plan mode**, read this file top to
bottom. It assumes you know nothing about this repo.

This folder contains only this file. The predecessor lives at `../froggo.swift/`.

---

## 1. Where you are

`rootyapps`, a monorepo of standalone iOS/macOS apps by a solo developer.

```
rootyapps/
├── CLAUDE.md              monorepo rules — read it
├── marketing/             SHARED library — NEVER fork it into an app folder
├── uitests.md             shared UI-test doc
├── froggo.swift/          ← THE PREDECESSOR. Read its math. Do not modify it.
├── storypole/             recent app — copy its project structure
└── froggo2/               ← you are here
```

**Portfolio rules:** no ads, no subscription. Games may use **free + a single one-time unlock IAP**.
Oracle-first: provable correctness where correctness is provable. Draft and stage only — creating an
App Store version, submitting, or changing price are the owner's decisions.

---

## 2. What this is

**Froggo 2 is a 3D sequel to a shipped 2D game.** The predecessor is a side-on SpriteKit jumper: the
frog moves along a **1-D corridor** of skyscrapers, always forward, drag-back-to-launch.

**Froggo 2 moves it into a 3-D city block.** The frog stands on a rooftop and can jump to **any** of
the surrounding buildings — so the player **rotates to aim**, sets power, and **chooses a route**
through the block rather than being pushed down a line.

| | Froggo 1 | **Froggo 2** |
|---|---|---|
| View | side-on 2D | **3rd person 3D** |
| Field | 1-D corridor, always forward | **2-D field — a block of buildings around you** |
| Aim | drag back, forward only | **rotate (yaw) + power** |
| Choice | none — one gap ahead | **many candidate rooftops; routing is the game** |
| Engine | SpriteKit | SceneKit or RealityKit — §6 |

---

## 3. Read froggo 1's math first — it is the asset

**`../froggo.swift/` is 1,659 lines. Read all of it before designing anything.** The code is small;
the **tuning** is what took iteration, and it transfers to any renderer.

⚠️ **Do not modify `../froggo.swift/`.** It is a shipped app and the reference.

### The constants that matter — verify each against source, do not trust this table

`GameManager.swift`:

| Constant | Value | Meaning |
|---|---|---|
| `gravitation` | **−5.8** | gravity on the frog |
| `jumpForce` | **50** | base launch impulse |
| `jumperLength` | **150** | max drag length = max power. **This is the reachability budget.** |
| `initialDeltaBetweenScrapers` | 80 | base gap |
| `scraperDistanceDeviation` | **1.62** | golden ratio — gaps are `80 × random(0.38…1.62)` ⇒ **30.4–129.6** |
| `scraperWidthDeviation` | 30 | width `80 + random(0…30)` |
| `scraperSizeYDeviation` | ±100 | height variance around `scaleY` 1200 |
| `initialSkyscrapers` | 20 | initial city length |

`Frog.swift`:

| Constant | Value | Meaning |
|---|---|---|
| `flyEatenMultiplier` | **1.5** | eating a fly multiplies the next jump |
| `stabilityChecks` | **5** | landing = 5 consecutive frames with Δpos < 0.5 **and** velocity < 10 |
| restitution / friction | 0.2 / 0.8 | on both frog and skyscraper |
| `allowsRotation` | false | frog does not spin |

**Directional clamp — a real design decision, not a bug:** `if direction.x > 0 { direction.x = 0 }`.
You drag *backwards* to launch *forwards*; forward drag is clamped to zero. **In 3-D this clamp
disappears** — rotation replaces it — so decide deliberately what takes its place.

### Preserve the feel, not the code

Jump arc, gap-to-power ratio, landing tolerance and the fly multiplier are the tuned feel. **Port
the numbers, not the SpriteKit.** Where a 2-D constant has no 3-D meaning, say so and justify what
replaces it.

---

## 4. The reachability oracle — the house pattern, and this is where it earns its place

In 1-D there is one gap and it is either clearable or not. **In a 2-D field there are many candidate
rooftops, and a generated block can strand the player with no reachable target.** That is the
failure a solver prevents by construction.

**Build a `ReachabilityKit`** (oracle-tested SPM package, per the house pattern):

```
Kits/Reachability/ReachabilityKit/
├── Sources/ReachabilityKit/
└── Tests/ReachabilityKitTests/ReachabilityOracleTests.swift
```

**The oracle, stated as a testable property:**

> From every rooftop the player can occupy, **at least one other rooftop must be reachable** under
> the ballistic envelope defined by `gravitation`, `jumpForce` and `jumperLength` — at some
> (yaw, power) the player can actually input.

Additional properties worth proving:

- **No dead ends** — the reachability graph over a generated block has no sink before the goal
- **Solvable route exists** — a path from spawn to objective, and its length is the difficulty measure
- **Difficulty is measured, not guessed** — grade a block by minimum jumps and by margin (how much
  of the envelope a required jump consumes). A jump needing 98% of max power is hard; one needing
  40% is not.
- **Height matters** — rooftops differ in height, so the envelope is asymmetric: down-jumps reach
  further than up-jumps. The oracle must model that.

**Generate-and-verify:** produce candidate blocks, run the solver, discard any that fail. Never ship
a block the solver has not cleared. This is the same discipline as the Kits in `storypole` and
`overtonelab`, applied to level generation.

---

## 5. What to design

**Third-person camera** behind and above the frog, following rotation.

**Aim** — rotate the frog/camera in yaw, then set power. Show the predicted arc: froggo 1 drew a
trajectory line, and the 3-D equivalent is the landing-ring/arc preview. **The player must be able
to see whether a target is in range before committing** — that is what makes routing a decision
rather than a guess.

**Target choice** — many rooftops visible. Consider highlighting which are reachable at current
power, but decide whether that is too generous; the tension may come from judging it.

**Progression** — froggo 1 tracked `progress` by skyscraper index in a line. In a block, define what
progress means: reaching a goal building, height gained, blocks traversed. **This is an open design
question — propose and justify.**

**Carry forward from froggo 1:** the fly (`flyEatenMultiplier` 1.5) is a good mechanic — a pickup
that extends the envelope, which in a 2-D field opens *routes*, not just distance. Keep it.

---

## 6. Engine — decide and justify

**SceneKit** is simpler, mature, and adequate. **RealityKit** is Apple's forward direction and where
the tooling is going. Note `../froggo.swift/` already has a stray `import RealityKit`.

Recommend one in your plan with reasoning. Consider: physics quality for ballistic arcs, asset
pipeline (USDZ), and whether the frog needs skeletal animation.

⚠️ **3-D assets are the real project cost, not the code.** Froggo 1 is 1,659 lines; rewriting that is
a day. A rigged frog, buildings and animations are weeks. **Say plainly in your plan what art is
needed and what can be done with primitives** — a stylised low-poly city may be both cheaper and
better than realism.

---

## 6a. Assets — reuse froggo 1's, and use its palette where textures can't carry over

**Everything is in `../froggo.swift/froggo.swift/Assets.xcassets/`. Look at it before making
anything.** The whole game is built from Apple system colours, which makes it trivially portable to
3-D materials.

### Reuse directly

| Asset | Size | Use in 3-D |
|---|---|---|
| **`scraper.png`** | 100×100, **already tileable** | **building material, unchanged.** Froggo 1 tiles it 4–6× via an SKShader; a 3-D material repeats it the same way |
| **`NightSky.png`** | 1000×500 | **skybox / backdrop** |
| `fly_1.png` · `fly_2.png` | 200×200 | **camera-facing billboard quads.** A fly is small and fast — a billboard reads as 3-D and costs nothing. Keep the 2-frame animation |

### Cannot carry over — the frog

`idle_frog.png` (96×64) and `jump_frog.png` (100×116) are **side-view 2-D sprites**. They cannot
become a 3-D character. **This is the one asset that must be made**, and it's the whole art budget.

**Build it in froggo 1's exact palette so the identity survives:**

| | Hex | Share | Note |
|---|---|---|---|
| **Frog body** | **`#30D158`** | 37% idle / **67% jump** | Apple systemGreen (dark) |
| Frog body, second tone | `#34C759` | 31% / 20% | Apple systemGreen |
| Frog highlights / eyes / belly | `#FFFFFF` | 28% / 12% | |
| Frog outline accent | `#1A0D0D` | 1% | near-black |

**Building palette** (from `scraper.png`): `#FFA90A` **69%** (systemOrange — lit windows) over
`#0A84FF` **28%** (systemBlue — facade). **Sky**: `#0A84FF` 87%, with `#ACACAC` and `#FFFFFF` for
cloud/haze, plus `#64D2FF` accent.

**Low-poly is the right answer.** The source sprites are 96×64 and 100×116 — this was never
detailed art. A stylised low-poly frog in those two greens will look *more* faithful than an
attempt at realism, and it needs no texture painting. Primitives plus flat materials in these
hexes will carry the whole city.

**Do not invent a new palette.** If a 3-D need has no froggo 1 equivalent — ground plane, shadow,
UI — derive it from these colours and say what you derived and why.

---

## 7. Project setup

**The App Store record already exists. Do not create one.**

| | |
|---|---|
| Bundle identifier | **`oleksandr.aisixteen.froggo-swift`** |
| Apple ID | **6753925277** |
| Current name | **`froggo.swift`** → rename to **`Froggo 2: Frog Jump`** |
| State | macOS 1.0 `PREPARE_FOR_SUBMISSION`, **never been on sale**, no availability record |

**Froggo 1 stays untouched.** *Skyscraper Frog* (`com.rooroogames.froggo`, **1563057204**) is live in
175 territories with iOS 1.151 / macOS 1.15. **Do not modify it.** Two records — original and
sequel — is a legitimate structure; a sequel is not a duplicate.

**Two things this record needs that a live app wouldn't:**

- **Only a macOS version exists.** The iOS/iPadOS version has to be created. That is an owner
  decision (§10) — prepare, then ask.
- **It has no availability record at all**, so it is on sale in zero territories. Even after a build
  is approved it would show as "removed from sale" until territories are set. **Flag this to the
  owner; do not set it yourself.**

⚠️ The bundle ID contains "froggo-swift". **That is fine and must not be changed** — bundle IDs are
never user-visible, are permanent, and Guideline 5.2.5 concerns what people *see*. The rule applies
to `PRODUCT_NAME` and the record name, both of which you are fixing.
- ⚠️ **`PRODUCT_NAME` must be `Froggo 2`.** Froggo 1 has `PRODUCT_NAME = "$(TARGET_NAME)"` with the
  target named `froggo.swift`, which ships a product literally called **"froggo.swift"**. App Review
  **5.2.5** rejects Apple trademarks — including "Swift" — in a shipped product name. **Never name a
  target `*.swift`.** That is why this folder is `froggo2`, not `froggo2.swift`.
- App Store name: **`Froggo 2: Frog Jump`** — §9
- `MARKETING_VERSION` — bump the **patch** of whatever the live version is; do not bump the build
  number alone
- Match `storypole/`: `project.yml` (XcodeGen), Kits as local SPM packages
- **Platforms: iPhone + iPad + Mac, universal.** One target, `TARGETED_DEVICE_FAMILY: "1,2"` plus a
  Mac destination. Not tvOS — froggo 1 has some tvOS remote code, ignore it.

### ⚠️ Scope — this is a shipping run, not a perfection run

**The objective is a live App Store record carrying a current build.** A record with no recent
build goes stale and Apple eventually removes it.

That sets the bar: **a working, universal 3-D game that runs well on all three platforms and looks
finished.** Not a deep game. Ship the loop — rotate, aim, jump, land, progress, fail — with the
reachability oracle guaranteeing generated blocks are solvable, and stop there.

**Do not write UI tests.** Unit tests for `ReachabilityKit` only — the oracle is the one thing that
must be provably right, because it is what stops the game shipping unplayable levels. Everything
else is judged by running it.

Prefer shipping a smaller, correct game over a larger, unfinished one. If a feature in §5 is
threatening the ship, cut it and say what you cut.

---

## 8. Icon

**Froggo 1 already has a full icon set — look before drawing:**

- `Assets.xcassets/AppIcon.appiconset/` — complete, including `Icon-Store-1024.png`
- `Assets.xcassets/AppIcon.brandassets` and `AppIcon.solidimagestack`
- **`froggo.swift/liquid_icon.icon/`** — an **Icon Composer layered icon** already exists. Open it.
- Plus `aso_media/` and `media/` at the app root

The icon must read at 1024 **and** at Home-Screen size, and on **Mac** — this build is universal, so
check it in the Dock too.

A 3-D sequel should stay recognisably the same character: same greens (`#30D158` / `#34C759`), same
silhouette, rendered with depth. Reuse the existing layered icon as the starting point rather than
beginning from nothing.

**Do not ship a placeholder icon as finished.** If it is a draft, say so.

---

## 9. ASO — measured, do not re-derive

| Term | Autocomplete hits | Field |
|---|---|---|
| `frog jump` | **10** | top results have **0–2 ratings each** — effectively open |
| `frog game` | 6 | Frog Game! at 92 ratings is the largest |
| `Froggo` / `Froggo 2` | 1 / **0** | pure brand, no search demand |

**The store name carries the head noun**: `Froggo 2: Frog Jump`. "Froggo 2" alone is the Kerf Calc
mistake — brand with nothing searchable. The **subtitle is a second indexed field** — put `frog game`
terms there rather than losing them.

**Screenshot captions are indexed.** There is no `params.yaml` in froggo 1 — that is an empty
ranking surface.

---

## 9a. Shipping — archive, upload, and where you stop

The run ends with **a build on App Store Connect and an icon**, so the record is alive.

1. Build and **run it on all three platforms** — iPhone Simulator, iPad Simulator, and Mac. The Mac
   build is the one people forget; a universal game that is broken in a window is worse than no Mac
   build. Look at it, don't just compile it.
2. Bump `MARKETING_VERSION` patch from whatever is live.
3. Archive and upload following **`../docs/RELEASE_runbook.md`** — it is measured against a real
   submission and is the authority for the plumbing.
4. Report the build number and processing status.

**You may archive and upload a build. You may not create an App Store version, submit for review,
change price, or assign the build to an external TestFlight group** — those are the owner's, and
uploading a build is not the same as shipping it.

**Signing:** `xcodebuild -authenticationKey` with the `.p8` auto-creates the distribution cert if
needed. Keys live in `keys/` and are gitignored — never print or commit key material.

---

## 10. 🛑 Stop and ask

**Creating an App Store version, submitting, or changing price are the owner's decisions.**

Also stop for:

- **Monetization.** The live record is **$0.99 paid with 0 ratings**. Measurement on 2026-08-10
  found **zero paid puzzle-adjacent games released since 2021** in a 823-app sample — every new
  entrant that broke through was free. The compass permits **free + a single one-time unlock** for
  games. **This is the owner's call — do not decide it, and do not build an IAP unless told to.**
- **Creating the iOS/iPadOS version** on the record — only macOS exists today (§7)
- **Setting territory availability** — the record has none, so it is on sale nowhere (§7)
- The progression definition (§5) if you cannot justify one
- Any froggo 1 constant whose 3-D meaning you cannot establish
- Art scope, if it exceeds what primitives can carry

---

## 11. Deliver a plan first

Before code: the constants read from froggo 1 with your 3-D mapping for each; the engine
recommendation with reasoning; `ReachabilityKit`'s design and its oracle properties; the
generate-and-verify loop; the camera and aiming model; the progression proposal; the art inventory
split into "primitives will do" and "needs an artist"; and every open question for the owner.
