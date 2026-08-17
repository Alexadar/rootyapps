# BUILD PROMPT — City Pigeon

**Start here.** Open this directory in Claude Code, enter **plan mode**, read this file top to
bottom. It assumes you know nothing about this repo.

This folder contains only this file. This is a **new game**, built from scratch — but it reuses
assets and structure from a sibling app.

---

## 1. Where you are

`rootyapps`, a monorepo of standalone iOS/macOS apps by a solo developer.

```
rootyapps/
├── CLAUDE.md              monorepo rules — read it
├── marketing/             SHARED — NEVER fork into an app folder
├── froggo2/               the 3-D sibling. REUSE ITS ASSETS. Read its PROMPT.md.
├── froggo.swift/          the original 2-D game — source of the art palette
├── storypole/             structural reference (project.yml, Kits)
└── citypigeon/            ← you are here
```

**Portfolio rules:** no ads, no subscription. Games may use **free + a single one-time unlock IAP**.
Draft and stage only — creating an App Store version, submitting, or changing price are the owner's
decisions.

---

## 2. The game

**A pigeon flies across a city. You bomb the traffic below.**

3-D rendered, locked to a **side view**. The pigeon travels **left → right**; the camera tracks it.
Skyscrapers fill the far plane. Cars and pedestrians move along the street beneath.

| | |
|---|---|
| **Left thumb — movement** | a joystick area. The pigeon holds position when untouched, and moves **up / down / forward / back** within the frame while dragged. It never leaves the visible area. |
| **Right thumb — one button** | **hold to charge**, release to drop. **Longer hold = heavier, more powerful payload.** |
| **The payload** | follows a **ballistic arc** — it inherits the pigeon's forward velocity, then gravity takes it down onto the street |
| **Scoring** | points on hits. Cars and people are the targets. |

That is the whole loop: position, charge, release, arc, hit. Everything else is variation on it.

**It is 3-D, but it plays in a plane.** Depth is for parallax and readability — buildings behind,
street below — not for aiming. The player never rotates the camera.

---

## 3. The ballistic model — build it as an oracle-tested Kit

This is the one part that must be provably correct, and it's the whole game feel.

```
Kits/Ballistics/BallisticsKit/
├── Sources/BallisticsKit/
└── Tests/BallisticsKitTests/BallisticsOracleTests.swift
```

**The model:** on release, the payload starts at the pigeon's position with the pigeon's **current
velocity**, plus a downward component from charge. Charge affects **mass and initial velocity** —
decide which and justify it. Gravity does the rest. Air drag optional; if you add it, say why.

**Oracle properties to prove:**

- **Closed-form landing point.** Given release altitude, forward velocity, charge and gravity, the
  impact point is computable analytically. Test the simulation against the closed form — they must
  agree within tolerance. **If they diverge, the physics has a bug the player will feel.**
- **Monotonic charge.** More charge must always mean a predictable change in the arc, never a
  reversal. Players learn this curve; it must be honest.
- **Hittability** — the reachability question, and the reason this Kit exists: **given the pigeon's
  altitude band and the charge range, which street positions are reachable?** Target spawning must
  only place targets inside that envelope. A target that cannot be hit at any charge is a bug, and
  the solver prevents it by construction.
- **Determinism** — same seed, same inputs, same result. Needed for replay and for testing at all.

This is the same discipline as `froggo2`'s `ReachabilityKit`. Read that prompt's §4.

---

## 4. Assets — reuse Froggo 2

⚠️ **Read `../froggo2/PROMPT.md` §6a before making anything.** Froggo 2 builds 3-D city assets from
the original game's art, and this game is set in the same city.

**Reuse directly:**

- **Skyscrapers** — Froggo 2's 3-D buildings and the tiling `scraper` texture. Same city, further
  away. This is most of your far plane.
- **The palette**, which is Apple system colours and already coherent:
  `#FFA90A` (systemOrange — lit windows) · `#0A84FF` (systemBlue — facades and sky) ·
  `#30D158` / `#34C759` (the Froggo greens) · `#FFFFFF` · `#1A0D0D`

**New and required:** the **pigeon** (the one real character), **cars**, **pedestrians**, and the
**payload**.

**Low-poly is the right register** — it matches Froggo's origin as 96×64 sprites, it costs no
texture painting, and it keeps a comic tone. **Do not attempt realism**, for tone reasons as much as
budget ones (§7).

**Time of day is yours to pick.** Froggo's sky asset is night; a daytime street reads better for
traffic and pedestrians. If you go day, derive the palette from the existing hexes and say what you
derived.

---

## 5. Feel — the part that decides whether it's fun

**The charge is the whole game.** Hold too briefly and it drifts behind; hold too long and it
overshoots. The player is solving a lead-and-drop problem every few seconds. Make the charge
**legible** — the player must be able to see how much power they have before releasing, and learn
the arc after a handful of attempts.

Decide and justify: **do you show a predicted trajectory?** Froggo 1 drew a trajectory line, which
made it a game of aiming. Hiding it makes it a game of feel. **Recommend one.**

**Movement should feel like flight, not like a cursor.** Some inertia, some drift, a sense of mass.
The pigeon holding still when untouched is correct — but "still" relative to a moving camera means
it is still travelling forward.

**Reward accuracy over spam.** If holding the button and releasing constantly is optimal, the game
is broken. Consider a cooldown, a limited supply that replenishes, or scoring that rewards precision
— **propose a mechanism**.

---

## 6. Scope — shipping, not perfection

**Universal: iPhone + iPad + Mac.** On Mac, map the controls to keyboard and trackpad honestly — a
twin-stick layout in a window is wrong.

**No UI tests.** Unit tests for `BallisticsKit` only — the oracle is the one thing that must be
provably right. Everything else is judged by playing it.

Ship the loop — fly, charge, drop, hit, score, fail — and stop. Cut anything threatening the build
and say what you cut.

---

## 7. ⚠️ Content and age rating — think about this before the art

The premise is a pigeon dropping on cars and people. That is ordinary comic mischief, and it exists
widely on the store — but **how it is drawn decides the rating**.

- **Keep it abstract and cartoon.** A white splat. No anatomical detail, no toilet humour framing.
  Low-poly stylisation helps here.
- Expect a rating around **9+/12+ for infrequent crude humour**. That is fine, but it is the owner's
  call to confirm.
- ⚠️ **App Store creative assets must meet a 4+ standard regardless of the app's rating** — icon,
  screenshots and preview must all be clean. Design the icon around the **pigeon and the city**, not
  the payload.
- Pedestrians are **cartoon figures**, never caricatures of real or identifiable people.

**If the tone drifts crude, pull it back.** The comedy is in the timing and the arc, not the subject.

---

## 8. Project setup

- **Bundle identifier is registered — use it exactly, never invent one.**

  | | |
  |---|---|
  | Identifier | **`oleksandr.aisixteen.citypigeon`** |
  | Platform | **UNIVERSAL** — iPhone, iPad, Mac from one identifier |
  | Seed / Team ID | `LSKNNBG94G` |

- **The App Store record exists.** Do not create one.

  | | |
  |---|---|
  | App name | **City Pigeon: Bird Game** |
  | Apple ID | **6800063278** |
  | SKU | `0000021` |
  | Versions | **iOS 1.0 + macOS 1.0**, both `PREPARE_FOR_SUBMISSION`, `AFTER_APPROVAL` |

  Both platform versions already exist — **you do not need to create a version.** Upload a build and
  attach it to them.

- `PRODUCT_NAME = City Pigeon`
- **`PRODUCT_NAME`** — set explicitly. **Never name a target `*.swift`**: App Review **5.2.5**
  rejects "Swift" in a shipped product name, and with `GENERATE_INFOPLIST_FILE` the generator takes
  `CFBundleName` from `PRODUCT_NAME`. This has caused a real rejection in this repo.
- Match `storypole/`: `project.yml` (XcodeGen), Kits as local SPM packages
- `MARKETING_VERSION` 1.0.0
- Engine: whatever `froggo2` chose — **use the same one**, since you are sharing assets and half the
  problem. If froggo2 hasn't decided yet, recommend and justify.

---

## 8a. Shipping — the run ends with an icon on the App Store record

**The objective: a build attached to the record so the listing carries the icon.** Deliver in this
order.

### 1. The game
Playable loop on all three platforms. **Run it, don't just compile it** — especially the Mac build.

### 2. The icon
1024 and Home Screen, **and the Dock** since this is universal. Design it around the **pigeon and
the city — never the payload** (§7). App Store creative must meet a **4+ standard regardless of the
app's age rating**. Use **Icon Composer** for the layered format.

### 3. The app preview video — side-view gameplay capture

⚠️ **App previews must be UNFRAMED.** Guideline **2.3.4** requires a full-bleed capture of the app
itself. A device-framed video is a rejection. This has bitten this repo before.

- **`../marketing/reels/store_preview.py`** produces the unframed store preview — use it
- `frame_reel.py` / `mac_frame_reel.py` are for **marketing** reels, **never** for store previews
- Read `../marketing/reels/README.md` first
- ⚠️ **Never fork anything out of `marketing/`.** Call the scripts in place.
- Capture the side-view loop: fly, charge, release, arc, hit. Audio is muted by default — it must
  read silently. Lead with the drop connecting; the first seconds decide.

### 4. Upload and attach

- Bump `MARKETING_VERSION` if you have already uploaded once
- Archive and upload per **`../docs/RELEASE_runbook.md`** — the authority for the plumbing
- **Attach the build to the existing iOS 1.0 and macOS 1.0 versions.** This is what puts the icon on
  the record.
- Report build number and processing state

**Signing:** `xcodebuild -authenticationKey` with the `.p8` auto-creates the distribution cert. Keys
live in `keys/`, gitignored — **never print or commit key material.**

### Where you stop

**You may archive, upload, and attach the build to the existing versions.** You may **not** submit
for review, create a new version, set price, or assign the build to an external TestFlight group.

⚠️ **The record has no territory availability**, so even an approved build would read *"removed from
sale."* Also unset: **price**, **category** (Games → Action/Arcade), **age rating**. **All owner
decisions — flag them, don't set them.**

---

## 9. Naming and ASO — measured 2026-08-10

**`City Pigeon` is completely free** — no exact match, **zero** starts-with, **zero** autocomplete
presence. Clean.

| Term | Hits | Field |
|---|---|---|
| `pigeon games` | 10 | Pigeon Bird Flying Simulator 4,113r · Pigeon Wings Strike 2,977r — all free |
| `bird game` | 10 | largest is 37 ratings — effectively open |
| `City Pigeon` | **0** | pure brand, no demand |

**The store name needs a head noun** — `City Pigeon` alone is brand with nothing searchable, which
is the Kerf Calc mistake. Something like **`City Pigeon: Bird Game`**. The subtitle is a second
indexed field — put the remaining terms there.

---

## 10. 🛑 Stop and ask

**Creating an App Store version, submitting, or changing price are the owner's decisions.**

Also stop for:

- **Submitting for review, price, territory availability, category, age rating** — all unset on the
  record, all the owner's (§8a). Uploading and attaching a build is fine; the rest is not.
- **Monetization** — paid-upfront vs free + single unlock is undecided. **Do not build an IAP.**
- The anti-spam mechanism (§5) if you cannot justify one
- Art scope, if it exceeds what low-poly primitives can carry
- Anything about tone that feels like it is drifting past §7

---

## 11. Deliver a plan first

Before code: the ballistic model with its oracle properties and the closed-form check; the
hittability envelope and how target spawning respects it; the control scheme for all three
platforms; the trajectory-preview recommendation; the anti-spam mechanism; the asset inventory split
into "reused from froggo2", "low-poly primitives", and "needs an artist"; and every open question
for the owner.
