# Ephemeris Sky — app preview reels

Two reels, not one. The App Store takes **three previews per device size per locale**, and a single
video cannot sell both halves of this app.

| reel | sells | tour |
|---|---|---|
| `sky` | the live moment | Chart → Positions → Aspects → Cycle → Events |
| `natal` | saved birth charts | Library → chart → transits bi-wheel → positions → houses |

They are different products to a buyer: one is "where is the sky now", the other is "here is your
chart, and here is what is crossing it". Trying to cover both in thirty seconds gave each about
twelve, which sold neither.

## Layout

Everything is namespaced by reel id. This is the change from the old pipeline, which assumed
exactly one video per device+locale and hard-coded a single `scenes.json`.

```
marketing/reels/scenes/<reel>/<iphone|ipad|mac>_<loc>.json   captions + fallback timing
marketing/raw/<loc>/<ios|ipad>/video/<reel>/capture.mov      raw simulator capture
marketing/raw/<loc>/mac/video/<reel>/clips/                  one Mac clip per screen
marketing/aso/<loc>/<ios|ipad|mac>/video/<reel>/full.mp4     conformed
marketing/aso/<loc>/<ios|ipad|mac>/video/<reel>/store_preview_*  what gets uploaded
```

## Running

```bash
REEL=natal PLATFORM=ios  ./capture_reel.sh en      # one reel, one device, one locale
REELS="sky natal" ./run_all_reels.sh en de fr ja   # iPhone + iPad, everything
REEL=natal ./capture_mac_reel.sh en de fr ja       # the Mac, which is a separate script
```

`REEL` defaults to `sky` everywhere, so existing invocations keep working.

The Mac is not in `run_all_reels.sh` on purpose: it records the real app on the real display via
ScreenCaptureKit, so it takes the machine over for the duration and cannot run unattended
alongside anything else.

## How the natal screens are reached

Three DEBUG-only launch overrides, the same ones the screenshot script uses:

| variable | effect |
|---|---|
| `EPHEMERIS_CHART=<uuid prefix>` | opens that saved chart from the library |
| `EPHEMERIS_LENS=wheel\|table\|aspects\|houses` | which reading it opens on |
| `EPHEMERIS_TRANSITS=1` | turns the wheel into the natal/transit bi-wheel |

**By UUID prefix, never row index.** The library sorts by `modifiedAt` and the seeded fixtures all
share an instant, so "row 0" is whichever the sort happened to put first — a capture keyed on it
shoots a different person's chart from run to run.

## How the tour is driven — and why not by XCUITest

The app walks itself. `EPHEMERIS_REEL=1` starts `ReelDriver`, and `EPHEMERIS_REEL_TOUR=sky|natal`
picks which tour. The driver emits `REEL_T0` / `REEL_SCENE <key>` / `REEL_END` via `NSLog`, and
`align_scenes.py` retimes the captions from those markers.

Driving it from outside did **not** work, three times, and each failure produced a finished video,
a clean log and a successful exit — see the comment block at the top of `ReelDriver.swift`. Scene
keys in the JSON must match the keys the driver emits, or captions silently fall back to their
nominal times.

## The natal reel needs a library

A reel of an empty library sells nothing, and capturing whatever charts happen to sit in a
developer's iCloud would put real birth data into a public video. So under `EPHEMERIS_REEL=1`,
`NatalViewModel.live()` returns an in-memory store seeded with `reelFixtures` — invented people at
fixed instants. Deterministic, and private data can never leak into a capture.

## Traps

- **Upload order is listing order.** The first preview uploaded autoplays on the product page.
  Choose which reel leads rather than letting the batch order decide.
- **No framing** (Guideline 2.3.4). Previews are full-bleed captures; `store_preview.py` produces
  the compliant cut. A device bezel is a rejection.
- **Every preview needs an audio track**, even silence — `capture_reel.sh` ffprobes for one and
  warns, because App Store Connect rejects a video without it.
- **Scene keys are a contract** between `ReelDriver` and the JSON. A renamed beat does not error;
  it just leaves the caption on its nominal time and drifts out of sync with the footage.
- **`preview_maxlen` is 30s** and the store enforces it. The natal tour's dwell times sum to exactly
  30 — adding a beat means taking the time from another.
