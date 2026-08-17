# The shared on-device generation base

One Swift package, `AISixteenModels`, used by every app in this repo that runs the `sd15cn` model
pack. It sits beside the Python that *produces* those packs, deliberately: an id written by
`convert_sd15_coreml.py` and an id compared by a resumed job are the same string, and keeping them
in one repository makes them impossible to edit apart.

```
aisixteen.models/
  scripts/            the converters, the licence gate, the checkpoint finder
  models/coreml/      the converted packs (gitignored — rebuild, don't commit)
  swift/AISixteenModels/
    Sources/ModelKit          which model is this, can this device run it
    Sources/TaskKit           what was this job doing, may that work be reused
    Sources/DiffusionKit      Apple's ml-stable-diffusion, vendored (MIT)
    Sources/DiffusionRuntime  the tiled ControlNet pass, shared by all three apps
```

Add it with a local path dependency:

```swift
.package(path: "../aisixteen.models/swift/AISixteenModels")
```

---

## What each target is for

### `ModelKit` — identity
Foundation only, so every rule is testable in milliseconds.

- `ModelIdentity` — *which* model, plus `nativeSide`, `hasControlNet`, measured resident bytes and a
  `minimumDeviceMemoryBytes` floor. `known` lists only models that have actually been converted and
  measured; an entry for a model that does not exist yet is a guess written where the app trusts it.
- `ModelUse` — one model **by subtask** (`generate` / `upscale` / `refine`), with a fingerprint.
  Recorded per subtask rather than per file so the day two stages use different packs, manifests
  written before it still mean what they said.
- `ModelFingerprint` — FNV-1a over name + **recursively summed** bytes. Not `hashValue` (salted per
  process) and not modification dates (they change on every reinstall).
- `AspectRatio` — output size in pixels, snapped to the latent grid.

### `TaskKit` — durable work
- `JobManifest` — everything that decides whether half-finished work still applies.
  `describesSameWork(as:)` compares every parameter that can change a pixel and nothing that cannot.
- `JobStore` — `Application Support/Jobs/<id>/`, holding `job.json`, a stage-1 checkpoint and tile
  PNGs. **Not** `temporaryDirectory`: the system purges that, silently, in exactly the case the
  feature exists for.
- `TileLedger` — which tiles are done, from a directory listing.
- `JobRunner` — **one owner of model work.** Two resident pipelines is ~1.5 GB and it has crashed and
  rebooted a test phone. Every app should route generation, refinement and any warm-up through it.

### `DiffusionKit` — Apple's runtime, vendored
MIT, see `APPLE-LICENSE.md`. Four changes, all additive or visibility-only so upstream fixes can be
re-applied by re-copying and re-widening:

1. `Unet.predictNoise` and `ResourceManaging.prewarmResources` made `public`.
2. **Zero residuals** — a controlled unet fed zeros is bit-identical to a plain one (proven,
   `scripts/prove_single_unet.py`, max abs diff 0.000000). One unet serves both plain and
   ControlNet runs, saving 618 MB of download and one resident model.
3. `ResumePoint` — restart a de-noising loop from a checkpoint. Verified byte-identical against an
   uninterrupted run.
4. `retainsDenoisingModels` plus autorelease pools in the step loop.

### `DiffusionRuntime` — the shared pass
- `TiledControlNetPass` — tiling, overlap, feathering, resumption, per-tile preview, memory
  discipline. The only things an app changes are the ControlNet name, the conditioning image and
  the settings.
- `ControlNetCatalog` — discover which nets a pack carries. Never hard-code a compiled name.

---

## The numbers that cost the most to learn

| | peak | wall time |
|---|---|---|
| unload models every tile, no autorelease pools | 1.43 GB | 372 s |
| no `reduceMemory` at all | 2.55 GB | 40 s |
| **retain denoising models + pools in both loops** | **0.46 GB** | **42 s** |

Without the pools, a nine-tile pass died at the eighth tile and took the device with it. Both halves
are load-bearing; neither is an optimisation you can skip.

Other measurements, on an iPhone 15 Pro Max unless stated:

- `--min-deployment-target iOS18` is **mandatory**. The converter defaults to `macOS13`, which
  predates ANE support for palettised weights, so a 6-bit model silently falls back to CPU: 6.16 GB
  and 0.04 steps/sec against 1.11 GB and 0.55.
- Diffusion 512², 28 steps: ~26 s. ESRGAN ×4 to 2048²: ~5 s. Nine-tile refine at 1024²: ~42 s.
- Neural Engine compilation happens at first load, is cached by the system keyed to hardware and OS
  build, **cannot be shipped**, and is lost on reinstall. There is no API to ask whether it has
  happened — see `ModelWarmth` in the Wallpapers app for the marker-file approach and its honest
  limits.

---

## Using the pass

```swift
import DiffusionRuntime

guard let net = ControlNetCatalog.name(of: .depth, at: resources) else { return }  // not installed
let pass = TiledControlNetPass(resourcesAt: resources, controlNet: net)

let result = try pass.run(
    source,                                   // already at the working size
    request: .init(prompt: prompt, seed: seed,
                   settings: .init(strength: 0.5, conditioningScale: 0.8)),
    conditioning: .aligned(depthMap),         // .theTileItself for Tile
    tiles: store?.tiles(.refine),             // optional; enables resumption
    preview: { partial in ... },              // publish after EVERY tile
    progress: { done, total in ... },
    isCancelled: { flag.isSet })
```

Four rules that are not obvious and were each learned the hard way:

1. **Publish the preview.** The pass composes after every tile because an earlier version composed
   once at the end, and for a whole minute the user watched an unchanged picture. If you ignore
   `preview`, your feature will appear to do nothing.
2. **Downscale before, upscale after.** Run at ~1024 rather than the master's size — nine tiles
   instead of twenty-five, and the downscale on the way in is supersampling, so the pass sees a
   cleaner picture than the master. Put the result back with a plain resample, not a second ESRGAN
   pass: that costs a ~200 MB accumulator for detail the downscale throws away.
3. **The grid is not evenly spaced.** The last origin is pulled back so the final tile is full, so at
   1024 the origins are 0, 448, 512. Any progress overlay should partition evenly and accept that it
   is approximate; drawn literally, the first tile clears two-thirds of the picture.
4. **Ask the catalogue, don't hard-code.** A pack that does not carry your net must disable the
   feature, not crash — and it must disable it *visibly*, not by silently returning nil from the
   action behind a button that still draws.
5. **Size your progress from `plan`, not from a guess.** `TiledControlNetPass.plan(for:width:height:)`
   returns the tile count and the *real* steps-per-tile before the pass starts, from arithmetic — no
   model, no disk. `run` calls the same function, so the number you display and the number the loop
   iterates cannot drift apart.

### The strength cliff — sweep the range, don't check the presets

`stepsPerTile` is `steps - Int(steps × strength)` onwards. When `steps × strength` floors to **zero**
the schedule is empty, and `Scheduler.addNoise` then indexes `timeSteps[stepCount]` — one past the
end, which **traps**. So a strength of 0.08 is fine at 20 steps and fatal at 12:

```swift
let plan = TiledControlNetPass.plan(for: settings, width: side, height: side)
plan.isRunnable        // false ⇒ run() throws .strengthTooLowForStepCount before loading anything
TiledControlNetPass.minimumStrength(forSteps: 12)   // 0.0833…
```

The pass refuses the pair rather than letting it reach Apple's scheduler, and the error names
**both** numbers because it is the pair that is invalid — an app that surfaces only the strength
sends someone hunting the wrong dial. The setting that breaks is the *gentlest* one, which is the
last one anyone tests by hand.

**If strength comes from a slider, validating your presets is not enough.** The value set is the
whole interval, not the labels on it: at `steps: 12`, **84 of 1001** positions on a 0–1 rail produce
an empty schedule, so correcting four named detents leaves 84 reachable crashes and a green test.
Put the curve through the clamp instead, and sweep the rail rather than the labels:

```swift
let safe = TiledControlNetPass.clamped(strength: curve(rail), forSteps: steps)
```

The clamp only ever raises, and never moves a value that was already valid — both asserted, because
a clamp that quietly rewrote a deliberate setting would be worse than the crash.

One thing it exposes and does not fix: **your dial is coarser than it looks.** Resolution is
`steps × the fraction of the range you use`, so capping the range — which any *enhance* app should,
since a photo of someone's child has no business at 0.8 — halves it again:

```swift
TiledControlNetPass.distinctOutcomes(forSteps: 12, strengthFrom: 0, to: 0.5)   // 6
TiledControlNetPass.distinctOutcomes(forSteps: 24, strengthFrom: 0, to: 0.5)   // 12
```

Six results is what a hundred-position slider with four named detents actually offers, and a third
of its travel lands on the same one. Clamping stops the crash; it does not make the bottom of the
rail *do* anything. The only lever is `steps`, which costs wall time roughly in proportion — 12
outcomes at about double the wait. That trade belongs to whoever owns the dial, and they should see
the number before they choose.

**Apply this to the right controls only.** The rule is *what the control resolves to*, not what it is
called:

| the control resolves to… | honest shape | why |
|---|---|---|
| a **step count** (`strength`) | discrete — named choices | there are `steps × range` answers; a rail overstates them |
| a **blend** (alpha composite, before/after wipe) | continuous | no scheduler involved, every position distinct, and free |

An app can have one of each behind controls that look identical — a strength dial that is a *request*
before a pass and a *live blend* after it, or a strength dial beside a comparison wipe. Both consuming
apps hit this. Reading the table above as "strength dials should be discrete" once came within a
message of discretising a before/after wipe, which would have removed the interaction that product
was built around.

`plan` costs ~0.7 ms in Debug (it builds the scheduler's beta tables). Fine per drag or per pass;
not for a per-frame loop.

---

## Licences — check before you convert, not after

`scripts/licences.py` is the gate; `import_single_file.py --civitai-model <id>` refuses unshippable
weights before the 2 GB read. Shipping means **redistributing weights inside a product**, which needs
all three of `allowDerivatives`, `allowDifferentLicense`, and `Sell` in `allowCommercialUse`.
`Image` (sell generated pictures) and `Rent` (hosted generation) are **not** enough. This project has
had to throw away two converted artefacts for getting it the wrong way round.

What ships today:

| component | licence | obligation |
|---|---|---|
| Lyriel v1.6 (checkpoint) | CivitAI, `allowNoCredit: false` | **attribution required in-app** |
| Theovercomer8's Contrast Fix (LoRA) | CivitAI, all flags pass | none |
| ControlNet 1.1 tile / mlsd / depth | CreativeML OpenRAIL-M | Attachment A must pass through to your EULA |
| Real-ESRGAN | BSD-3-Clause | none |
| Depth Anything V2 Small | Apache-2.0 | none |

`LICENCE.txt` travels **inside** the converted pack, carried there by the converter, so the terms
cannot be separated from the weights they govern. Read it before you ship.
