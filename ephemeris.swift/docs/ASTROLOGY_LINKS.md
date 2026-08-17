# Astrology links — what relates to what

The dependency map for every function Ephemeris Sky **has** or **might have**. Written for design:
it answers *which category does this belong to*, *what must exist before this screen can render*,
*what shares a surface*, and *what a user must have entered first*.

Per-function detail lives in [`functions/`](functions/README.md). This file is only the wiring.

```
LEGEND     [■] SHIPPED — oracle-tested engine AND a surface a user can reach
           [□] proposed, not built      [·] known gap, unproposed
           ──▶  requires        ═══▶ is rendered by
```

> **`[■]` means both halves, and that wording is deliberate.** It used to mean "the maths exists",
> which is how **astrocartography and export sat marked implemented while having zero UI** — the
> engines were oracle-tested for months and no screen reached them. A marker that cannot tell those
> apart hides exactly the gap it is meant to expose. If an engine ships without a surface it does
> not get `[■]`; say so in words instead.

**Audited against the code on 2026-08-17: all 20 entries below carry both halves.** Each was checked
by resolving its Kit symbol *and* a compiled Swift file that reads it — a match in a string catalog
or in `design_handoff_nebula/` does not count, since neither reaches a user.

| | |
|---|---|
| Sky | astronomy core · houses · events/timeline · **moon phases** · **planetary hours** |
| Charts | natal chart · aspects · dignities · chart analysis · midpoints · composite · synastry · **astrocartography** · uncertainty |
| Cycles | transits/cross-aspects · progressions · returns |
| Neither | **export** (an action) · **sidereal zodiac** (a setting) · **void-of-course** (an overlay) |

Everything **bold** gained its surface in the coverage-redesign pass; the rest already had one.

**Nothing proposed remains unbuilt.** The only unimplemented functions are the three `[·]` gaps
below — eclipses, harmonics and fixed stars — which have no Kit symbol and were never measured, so
no file here asserts they are worth building. Eclipses are the obvious Sky-shaped one and would be
the first to scope.

---

## 0. ⚠️ What this file is NOT — read before designing

This file and [`functions/`](functions/README.md) are the **structure and constraint layer**: what
exists, what depends on what, what shares a surface, what a user must enter first, and what must
never be shown. They are deliberately silent on visual language.

**They cannot finalize UI on their own.** Anything below is authority these files do not carry:

| Authority | Lives in | Covers |
|---|---|---|
| **Visual system** | `design_handoff_nebula/DesignSystem/` + `README.md` | tokens, type, spacing, colour |
| **Visual reference** | `design_handoff_nebula/reference/` | the shipped look |
| **Watch** | `design_handoff_nebula/WATCH_APP_BRIEF.md` | a whole platform, already briefed |
| **Widget** | `EphemerisWidget/` (watchOS) · `EphemerisWidgetIOS/` (iOS/macOS) | glanceable surfaces. ⚠️ `EphemerisWidget` is **watchOS-only** and never serves iOS; Home/Lock Screen widgets come from `EphemerisWidgetIOS`, which ships **moon phase** (gate 0, text-only — no location means no hemisphere, and every phase emoji is handed) and **planetary hours** (gate 1, reads the observer through the App Group). A moon complication was **removed from the watch bundle after five attempts** because the terminator never rendered right on device. The drawn disc lives in `MoonDisc.swift`, on the calendar, where a latitude exists |
| **Localization** | `Localization/` | 17 languages. Every label here will expand; German and Ukrainian break tight layouts |
| **Current screens** | `ephemeris/*View.swift` | `BirthDataEntry` · `ChartLibrary` · `Cycle` · `Events` · `NatalChart` · `Pairing` · `Settings`, plus an `IOSContentView` / `MacOSContentView` split |

⚠️ **Screens already exist.** `EventsView`, `CycleView` and `NatalChartView` map onto Sky, Cycles
and Charts today. This is a redesign against a shipped app, not a greenfield — read the current
views before proposing a structure, and say explicitly what you are changing and why.

**Order of authority when they disagree:** the code, then `design_handoff_nebula/`, then these
files. If a doc here contradicts what ships, the doc is stale — say so rather than designing to it.

✅ **`design_handoff_nebula/` is up to date with the delivered coverage redesign.** It carries
`NebulaCoverage.swift` and the Coverage Redesign / Astrocartography / Analysis references, and the
northern-hemisphere-only `MoonPhaseDisc.swift` has been **deleted** — the moon disc authority is the
shipped `ephemeris/Views/MoonDisc.swift`, which takes a latitude. Do not re-add a second disc.

---

## 1. The three categories — the app's actual shape

Everything is **Sky**, **Charts**, or **Cycles**. This is the shipped navigation, and the
dependency analysis below arrives at it independently — which is why it is the right frame rather
than an arbitrary one.

```
┌─ SKY ─────────────────── what is happening ───────────────────────────────┐
│  no birth data required — works on a brand-new install                    │
│                                                                            │
│  [■] events: ingresses · mundane aspects · synodic cycles                 │
│  [■] lunations  →  [■] MOON PHASES as its own surface                     │
│  [■] retrogrades                                                          │
│  [■] planetary hours          (needs location only)                        │
│  [·] eclipses                 (unproposed gap — obviously Sky)             │
│                                                                            │
│  ⚠ THIS IS THE ENTRANCE. Everything else is locked until birth data        │
│    exists. It is also where the consumer money is: moon-phase apps         │
│    measure $3.99 × 3,619 and $3.99 × 2,581 ratings, both active.           │
└────────────────────────────────────────────────────────────────────────────┘

┌─ CHARTS ──────────────── who you are ──────────────────────────────────────┐
│  requires one birth record (two, for synastry and composite)                │
│                                                                            │
│  [■] natal chart + archive     [■] houses          [■] aspects             │
│  [■] dignities                 [■] chart analysis  [■] midpoints           │
│  [■] composite                 [■] synastry        [■] astrocartography    │
│  [·] harmonics   [·] fixed stars      (unproposed gaps)                     │
│                                                                            │
│  This is the depth, and the $8.99–29.99 professional tier.                 │
└────────────────────────────────────────────────────────────────────────────┘

┌─ CYCLES ──────────────── what is happening TO you ─────────────────────────┐
│  requires birth data AND a time range                                      │
│                                                                            │
│  [■] transits      [■] progressions     [■] returns     [■] timelines      │
│                                                                            │
│  The recurring use. A natal chart is computed once; transits are            │
│  consulted every morning. This is the retention category.                   │
└────────────────────────────────────────────────────────────────────────────┘

┌─ NEITHER — do not give these a category ──────────────────────────────────┐
│  [■] export             an ACTION, available wherever you are              │
│  [■] sidereal zodiac    a SETTING — re-reads Charts and Cycles in another  │
│                         frame, adds no screen of its own                    │
│  [■] astronomy core     the engine underneath all three                     │
└────────────────────────────────────────────────────────────────────────────┘
```

> **The rule:** if a proposed feature does not fit Sky, Charts or Cycles, that is a signal it is a
> **different product** — not a reason to add a fourth category. Tarot did not fit. Document
> scanning did not fit. Both correctly became separate apps.

---

## 2. Dependency graph

Everything hangs off three user inputs. Nothing below a box can render until that box can.
Category shown in the margin.

```
                        ┌──────────────────────────────────┐
                        │           USER INPUT             │
                        │   date · time · place · name     │
                        └───┬──────────┬───────────┬───────┘
                            │          │           │
              instant only ─┘          │           └─ place only
                            │   instant + place     │
                            ▼          ▼            ▼
        ┌───────────────────────┐  ┌──────────┐  ┌───────────────────┐
        │ [■] ASTRONOMY CORE    │  │[■] HOUSES│  │[■] PLANETARY HOURS│ SKY
        │  10 body longitudes   │  │ cusps    │  │ sunrise → sunset  │
        │  ±7′, 1900–2100       │  │ ASC · MC │  │ Chaldean rulers   │
        │  ORACLE: JPL Horizons │  │          │  │                   │
        └──┬────────┬───────┬───┘  └────┬─────┘  └───────────────────┘
           │        │       │           │
           │        │       │  ┌────────┴──────────────────────────┐
           │        │       │  │                                   │
           │        │       ▼  │                                   ▼
           │        │  ┌───────────────────────┐      ┌──────────────────────┐
           │        │  │[■] EVENTS · LUNATIONS │ SKY  │  [■] NATAL CHART     │ CHARTS
           │        │  │ ingress · mundane     │      │  positions + houses  │
           │        │  │ synodic · retrograde  │      │  + aspects, STORED   │
           │        │  └───────────┬───────────┘      │  + uncertainty band  │
           │        │              │                  └──┬───┬───┬───┬───┬───┘
           │        │              ▼                     │   │   │   │   │
           │        │  ┌───────────────────────┐         │   │   │   │   │
           │        │  │[■] MOON PHASES        │ SKY     │   │   │   │   │
           │        │  │ calendar · widget     │         │   │   │   │   │
           │        │  │ ⚠ the paid-volume one │         │   │   │   │   │
           │        │  └───────────────────────┘         │   │   │   │   │
           │        │                                    │   │   │   │   │
           │        └─▶┌────────────────────┐            │   │   │   │   │
           │           │[■] SIDEREAL ZODIAC │ SETTING    │   │   │   │   │
           │           │  λ − ayanamsa      │            │   │   │   │   │
           │           └────────────────────┘            │   │   │   │   │
           │                                             │   │   │   │   │
           ▼         ┌───────────────┬───────────────┬───┘   │   │   │   │
    ┌───────────┐    ▼               ▼               ▼       ▼   ▼   │   ▼
    │[■] ASTRO- │ ┌────────┐ ┌───────────┐ ┌────────────┐ ┌───────┐ │ ┌──────────┐
    │ CARTOGRA- │ │[■] AS- │ │[■] DIGNI- │ │[■] MIDPTS  │ │[■]CHRT│ │ │[■] CROSS-│
    │ PHY       │ │  PECTS │ │  TIES     │ │ + COMPOSITE│ │ ANALY-│ │ │  ASPECTS │
    │ 40 lines  │ │ in one │ │ Ptolemy   │ │  Ebertin   │ │  SIS  │ │ │ 2 charts │
    │ the MAP   │ │  chart │ │ tables    │ │  half-sums │ │ Jones │ │ └────┬─────┘
    └───────────┘ └────────┘ └───────────┘ └────────────┘ └───────┘ │      │
       CHARTS       CHARTS      CHARTS         CHARTS       CHARTS   │   CYCLES
                                                                     │      │
                                          ┌──────────────────────────┴──────┤
                                          ▼              ▼                  ▼
                                   ┌────────────┐ ┌─────────────┐  ┌──────────────┐
                                   │  TRANSITS  │ │  SYNASTRY   │  │ PROGRESSED   │
                                   │ sky ▸natal │ │  A ▸ B      │  │  ▸ radix     │
                                   │   CYCLES   │ │   CHARTS    │  │   CYCLES     │
                                   └────────────┘ └─────────────┘  └──────┬───────┘
                                                                          │
    ┌────────────────────┐    ┌────────────────────┐   ┌──────────────────┴───────┐
    │ [■] EVENTS         │    │ [■] RETURNS        │   │ [■] PROGRESSIONS         │
    │ ROOT-FIND f(t)=0   │    │ ROOT-FIND λ=λnatal │   │ day-for-a-year           │
    │      SKY           │    │      CYCLES        │   │      CYCLES              │
    └─────────┬──────────┘    └─────────┬──────────┘   └──────────────────────────┘
              │      shared machinery   │
              └────────┬────────────────┘
                       ▼
              ┌──────────────────┐          ┌──────────────────────────┐
              │ RootFinding      │          │ [·] UNPROPOSED GAPS      │
              │ solve f(t)=0     │          │ eclipses      → SKY      │
              │ ⚠ retrograde =   │          │ harmonics     → CHARTS   │
              │   3 roots, not 1 │          │ fixed stars   → CHARTS   │
              └──────────────────┘          └──────────────────────────┘
                       │
                       ▼
              ┌──────────────────┐
              │ [■] EXPORT       │  an ACTION, not a category
              │ ⚠ once shipped,  │
              │   a public       │
              │   contract       │
              └──────────────────┘
```

---

## 3. Input gates — what the user must supply first

**This is the screen-order constraint.** A function cannot be offered before its gate is satisfied.
Gate maps almost exactly onto category.

```
GATE 0  nothing                 ┌─ [■] EVENTS (ingresses, mundane aspects, retrogrades)
        no user data at all     ├─ [■] LUNATIONS ─▶ [■] MOON PHASES
        ══▶ SKY                 └─ these work on an EMPTY app. THE first-run content.

GATE 1  place only              ┌─ [■] PLANETARY HOURS
        (device GPS is fine)    └─ still no birth data. Second-best first-run content.
        ══▶ SKY

GATE 2  date + time + place     ┌─ [■] NATAL CHART ─┬─ [■] ASPECTS      ┐
        = one birth record      │                   ├─ [■] DIGNITIES    │ CHARTS
        ══▶ CHARTS              │                   ├─ [■] CHART ANALYSIS
                                │                   ├─ [■] MIDPOINTS    │
                                │                   └─ [■] ASTROCARTOGRAPHY
                                │                   ┌─ [■] TRANSITS     ┐
                                │                   ├─ [■] PROGRESSIONS │ CYCLES
                                │                   └─ [■] RETURNS      ┘

GATE 3  TWO birth records       ┌─ [■] SYNASTRY          ┐ CHARTS
        ══▶ CHARTS              └─ [■] COMPOSITE CHART   ┘

GATE 4  a date RANGE            ┌─ [■] EVENT TIMELINE      ══▶ SKY
        on top of gate 2        ├─ [■] TRANSIT TIMELINE    ══▶ CYCLES
                                └─ [■] EXPORT              ══▶ action
```

⚠️ **Design consequence:** gates 0 and 1 — the whole Sky category — are the only things a
brand-new user can see. If the app opens on an empty natal-chart form, every screen is locked and
it reads as broken. **Sky is not a secondary tab; it is the front door.**

---

## 4. Surface map — what shares a screen

**Do not build one screen per function.** Fourteen functions collapse into seven surfaces.

```
┌─ THE WHEEL ──────────────────────────────────────── CHARTS ───────┐
│  natal chart · aspects (lines across centre) · dignities (badges) │
│  chart analysis (one line above) · houses (the ring)              │
│  ALSO renders: composite · return · progressed — same drawing,    │
│  different source chart, always LABELLED as such                  │
└───────────────────────────────────────────────────────────────────┘

┌─ THE MAP ────────────────────────────────────────── CHARTS ───────┐
│  astrocartography — the ONLY non-wheel view in the whole app,     │
│  and therefore the whole screenshot story                         │
└───────────────────────────────────────────────────────────────────┘

┌─ THE TIMELINE ───────────────────────────── SKY + CYCLES ─────────┐
│  events · transit exactness · upcoming returns · progressed hits  │
│  one vertical scroll, today anchored, filter by body and family   │
└───────────────────────────────────────────────────────────────────┘

┌─ THE CALENDAR ────────────────────────────────────── SKY ─────────┐
│  [■] moon phases — a MONTH grid, not a timeline. Different        │
│  audience, different mental model. Do NOT merge into the timeline.│
│  Widget + full/new moon notifications are the feature being bought│
│  Reached from a Sky ROW, not a lens segment: a month is not a     │
│  reading of one instant, and six segments do not fit 16 languages.│
└───────────────────────────────────────────────────────────────────┘

┌─ THE GRID ───────────────────────────────────────── CHARTS ───────┐
│  synastry (A down × B across) · midpoint trees · dignity table    │
│  dense, textual, unapologetically tabular                         │
└───────────────────────────────────────────────────────────────────┘

┌─ THE ARCHIVE ────────────────────────────────────── CHARTS ───────┐
│  saved charts — browse, search, group. The retention asset.       │
│  user-owned iCloud. NEVER reads as an account.                    │
└───────────────────────────────────────────────────────────────────┘

┌─ THE CLOCK ─────────────────────────────────────────── SKY ───────┐
│  [■] planetary hours — unequal ring, current hour, widget-shaped  │
│  segment widths MUST visibly differ or the drawing is lying       │
│  Sky ROW → full screen. Widget ships too (gate 1, App Group).     │
└───────────────────────────────────────────────────────────────────┘
```

---

## 5. The two-chart fan-out

One engine, three questions. Same maths, unrelated user intents — **three screens, not a mode
switch.** Note it straddles two categories.

```
                    ┌──────────────────────────┐
                    │  [■] CrossAspect         │
                    │  set A ▸ set B           │
                    │  ⚠ SIDES NOT SYMMETRIC   │
                    └──┬────────┬───────────┬──┘
                       │        │           │
       set A = sky ────┘        │           └──── set A = progressed chart
       set B = natal            │                 set B = natal
             │           set A = person A               │
             ▼           set B = person B               ▼
      ┌─────────────┐           │              ┌──────────────────┐
      │  TRANSITS   │           ▼              │ PROGRESSED       │
      │ "what now?" │    ┌─────────────┐       │ "what phase?"    │
      │  CYCLES     │    │  SYNASTRY   │       │  CYCLES          │
      │ → TIMELINE  │    │ "us?"       │       │ → TIMELINE       │
      └─────────────┘    │  CHARTS     │       └──────────────────┘
                         │ → GRID      │
                         └─────────────┘
```

⚠️ **Every label must name the side.** "Sun square Moon" is ambiguous and therefore wrong.
"Transiting Sun square natal Moon" is the minimum.

---

## 6. What this map tells a designer

1. **Sky is the front door, not a side tab.** It is the only category that works on a fresh
   install, and it carries the largest measured paying audience in the whole niche.
2. **The wheel is the app's identity.** Five Charts functions render into it. Get it right once at
   every size — watch to Mac — rather than designing per function.
3. **The map is the differentiator.** Astrocartography is the only non-wheel view in astrology.
   It carries the screenshots.
4. **Cycles is the retention category.** Charts is computed once; Cycles is consulted daily.
5. **Nothing here justifies a second app record.** Every function is a view over one birth chart or
   one sky. Both paid competitors ship all of it in one app for $8.99–$29.99.
6. **Sidereal adds no screen.** It re-reads the same charts in another frame. Any design that
   duplicates the wheel for it has misunderstood the function.
7. **Uncertainty is cross-cutting.** When birth time is approximate, every gate-2 function inherits
   the doubt — most visibly the Ascendant, therefore houses, therefore astrocartography. Show it
   where it bites, not once in a settings note.
8. **If it doesn't fit Sky, Charts or Cycles, it is a different product.** Do not add a category.

---

## 7. Related

Function detail: [`functions/README.md`](functions/README.md)
Accuracy and oracle policy: [`VALIDATION.md`](VALIDATION.md)
