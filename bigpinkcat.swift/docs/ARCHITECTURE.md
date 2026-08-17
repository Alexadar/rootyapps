# Big Pink Cat — architecture

A relativistic Metal game. An ordinary black-hole energy-extraction engineer works inside a Kerr
hole from an Alcubierre worker platform, and meets the adjacent world of a colossal pink cat past
the Cauchy horizon.

The premise is load-bearing rather than decorative, and that is worth stating once because it drives
the whole design:

- **An event horizon is *defined* as the surface past which escape requires exceeding c.** The
  Alcubierre metric is the canonical model of effective superluminal motion. A warp bubble is
  therefore not a hand-wave that gets you inside a black hole — it is the one object in general
  relativity that is specifically the right tool for the job.
- **The bubble interior is flat and inertial.** No tidal force, no time dilation, clocks ticking
  with a distant observer's. That is what licenses "ordinary engineer" as a register rather than a
  joke, and it is why the hero frame is a calm interior against an insane window.
- **The maximal analytic extension of Kerr contains passage to other asymptotically flat regions.**
  The cat's world past the Cauchy horizon is a feature of the 1967 solution, not an invention. And
  crossing a Cauchy horizon is otherwise one-way — the bubble is why there is a second act.

## The one distinction everything turns on

| | Tier 1 (demos 1–5) | Tier 2+ (demos 6–18) |
|---|---|---|
| What bends | what you **see** | where things **are** |
| A thrown wrench | flies straight | curves |
| Implementation | screen-space UV offset | geodesic integration |
| Pipeline | `relativistic_fragment` | `geodesic_fragment` |

Tier 1 exists to get the look on screen early and to make the store frame. **It is not the
destination.** From Tier 2 on, entity state is `(t, r, θ, φ)` with covariant `p_μ`, and light and
matter integrate through the *same* function one mass-shell parameter apart: photons on the null
shell (`p·p = 0`), bodies on the timelike shell (`p·p = −μ²`). Frame dragging then genuinely moves
things, and the renderer *projects* curved coordinates rather than filtering a flat picture.

The readout's `SCREEN-SPACE` / `WORLD-SPACE` label is driven by `Demo.isWorldSpace`, which also
selects the pipeline — so the label cannot lie about which one is running.

## Layers

```
Kits/          Foundation-only. No Metal, no SwiftUI. Enforced by the manifests, not by habit.
  TensorKit      the vector engine — one ruleset over a leading [N]; the game is that program at N=1
  DetMathKit     deterministic transcendentals, integer tick, trajectory hashing
  RelativityKit  Kerr metric, RK4 Hamiltonian geodesics, invariants, region radii
  PortalKit      portal transforms, crossing by arithmetic, holonomy
  StoryKit       the YAML tree loader + graph validator
BigPinkCat/    the app: Metal renderer, rigs, palette, demo catalog. Owns no rules.
```

A Kit that cannot import Metal cannot make the GPU authoritative. A Kit that cannot import SwiftUI
cannot let a frame time reach the simulation. That is the core→presentation boundary, and it is
structural rather than a convention anyone has to remember.

## Determinism contract

Verified on this toolchain rather than assumed:

- Swift does **not** contract `a*b + c` into `fmadd`, even at `-Ounchecked`. The worst C/C++ hazard
  does not exist here.
- `Double.squareRoot()` lowers to hardware `fsqrt`, which IEEE-754 specifies as correctly rounded.
- `simd_fast_*` **is** the hazard and is on the ban list; `simd_precise_*` sits beside it.
- IEEE-754 does not mandate correct rounding for `sin`/`cos`/`exp`, and libm differs across OS
  versions. So DetMathKit ships its own, from FDLIBM and Cephes coefficients.

Rules: CPU is authoritative; GPU renders and runs *unvalidated* bulk search whose hits are
re-verified on CPU. Integer tick, never a float time accumulator. Geometrized units (G = c = M = 1)
so everything is O(1). Chaos is presentation-only — near the photon sphere and past the Cauchy
horizon only *topological* outcomes are assertable, never exact paths.

Proven by `BigPinkCatTests/DeterminismGoldenTests`, which runs the same goldens on macOS **and** the
iOS Simulator. A golden that fails is never to be updated: find the operation that diverged.

## Oracles

Every number cites a published source, per `docs/calculators_VALIDATION.md`.

| Quantity | Expected | Source |
|---|---|---|
| Photon sphere | r = 3M exactly | standard GR |
| Critical impact parameter | b = 3√3 M | standard GR |
| ISCO, Schwarzschild | r = 6M | Bardeen–Press–Teukolsky 1972 |
| ISCO / photon orbit, extremal Kerr | 1M prograde, 9M / 4M retrograde | BPT 1972 |
| Light deflection | α = 4M/b + 15π/4b² | Eddington 1919 + post-Newtonian |
| Gravitational redshift | (1 − 2M/r)^−½ | Pound & Rebka 1959 |
| Penrose efficiency | 20.7% single decay, 29% reservoir | Penrose 1969 |
| E, L_z, Q along any geodesic | conserved | **Carter 1968** |

Carter's result is the one that pays repeatedly: Kerr geodesic motion is completely integrable, so
**every trajectory carries four quantities that must not change.** Nobody authors an expected value;
the physics supplies the assertion, on generated content as readily as authored content.

E and L_z are conserved *structurally* by the Hamiltonian form (`dp_t/dλ ≡ 0`), so they test the
state plumbing. Q and the mass shell test the integrator.

## Vector discipline

`VectorDisciplineTests` scans the Kit sources and fails on a `for`/`while` outside the primitive
layer without an allowlist entry, and on any banned call. Loops are legitimate in exactly three
places: primitive kernels; bounded algorithmic depth (RK4 stages, portal recursion); boundary
marshalling. It also asserts that its own matchers fire — a guard that never fires proves nothing.

## Palette

Measured from `output_story/images/{char1,char2,style}.png` by median-cut quantisation. **Do not
invent a colour**: every value is a sampled hex or carries a stated derivation. `PaletteTests`
enforces it. The 2025 marketing gradient (#FF69B4 → #8B008B) is a cross-check, not a source — the
cat's real pink is duller and warmer, and that difference is the character of the thing.

## Story

`output_story/` is **read-only to this codebase.** StoryKit parses it and reports; nothing writes it.

Honest state: depth 1 and depth 2 are fully written (all four branches). Depth 3 is **1 of 16**
(`dialog_1_1_1`, with 4 endings), 3 more exist as guidelines-only stubs, 12 do not exist.
`StoryGraph.validate()` names every gap rather than dead-ending — the previous build shipped fifteen
of sixteen paths going nowhere precisely because the loader failed silently.

## Things that cost time, recorded so they cost it once

- **A units bug can look exactly like a colour-space bug.** Comparing a geometrized radius (r₊ = 1.6 M)
  against a screen NDC radius made `saturate(r₊/r)` saturate everywhere; the frame came out flat
  lavender and the first hypothesis was double gamma encoding. Sampling the pixel and matching it to
  `Palette.ergosphere` found it in one step. Measure the pixel before theorising.
- **`smoothstep` requires edge0 < edge1.** Reversed edges are undefined and silently returned 0.
- **Equirectangular star fields have poles**, and the resulting dashes read convincingly as lensing.
  Hash the 3-D direction instead.
- **Two passes must share one camera**, or objects correctly placed at the ISCO render inside the
  shadow and it looks like a depth bug.
- **Debug builds are ~350× slower** through elementwise closures (froggo2 measured 12.4 s vs 35 ms).
  Never conclude anything about cost from a debug build.
- **A golden must be recorded, not authored.** Inventing a constant and then "fixing" it when it
  fails inverts the test into a tautology.
- **`PRODUCT_NAME` differing from the target name breaks `TEST_HOST`**, which defaults to the target
  name. That override exists for Guideline 5.2.5 and is not optional.
- **Same-named resources in sibling folders need a folder reference**, not a group.
