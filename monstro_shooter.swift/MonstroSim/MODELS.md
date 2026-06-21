# Models — detached artifacts, portability, and NPU

## Detached model artifacts

Trained policies are **standalone JSON weight files** (`models/player.json`), independent of the
trainer. `GPUPolicy.toData()` / `fromData()` serialize `{sizes, weights, biases}`. The engine loads
them at runtime (`gprun --net …`). CI/CD to regenerate them on a schedule comes later; for now they
are simply committed.

This file **is the lego connector** — the same weights feed every backend:

| Backend | Status | How |
|---|---|---|
| **GPU in-graph (MLX/Metal)** | ✅ now | `GPUPolicy.fromData` → forward fused with `BatchWorld` |
| **Brax / JAX (CUDA, 3090)** | next | load the same JSON into a JAX MLP; identical math |
| **Core ML / ANE** | optional, later | export weights → `.mlpackage` via coremltools |

## Why inference stays on the GPU (and the NPU is *not* wired)

The policy is reactive — it runs **every tick**, reading the current GPU sim state. Keeping it
**in-graph on the GPU** means observation → policy → action → step all happen in one Metal context
with **no cross-processor handoff**.

The **Apple Neural Engine (ANE/NPU) is inference-only** and is reached only through **Core ML**
(MLX has no ANE backend). Routing the per-tick policy through the ANE would split it from the
GPU sim → a **GPU → ANE → GPU handoff every tick** = exactly the cross-processor latency we
designed the on-device loop to avoid. And the nets are tiny (≈30k params), so the ANE's setup +
buffer-crossing cost **exceeds** the actual inference. Net result: ANE here is *slower and laggier*,
not faster. So it is intentionally **not wired**.

### When the NPU *would* make sense

- A **large, infrequent** "director"/meta model (runs every few seconds, decoupled from the tick
  loop) — handoff cost amortized, model big enough to matter.
- A **standalone shipped model** for a non-realtime feature (offline analysis, one-shot classifier).

For those, export the JSON weights to Core ML (`coremltools`, Python) and let Core ML schedule the
ANE. That's a clean follow-on — the weights are already portable — but it is **not** the path for
the reactive control policy, which belongs on the GPU.

## 2026 update: Core AI is the "whole compute stack" framework

WWDC 2026 introduced **Core AI** (successor to Core ML), purpose-built to auto-dispatch one model
across **CPU + GPU + ANE** (`.aimodel` assets, ahead-of-time compile, Core AI Instrument). The lanes:
**Core AI** = neural nets / custom models; **Core ML** = classic ML (compat); **MLX** = training +
custom weights (**still GPU/CPU only — no ANE**). Two facts that shape our pipeline:

- **No MLX→ANE direct path.** Core AI converts from **PyTorch** (`coreai_torch`), not MLX. So
  MLX-trained weights reach the ANE only via a conversion *through PyTorch→Core AI*.
- **Swappable backends are now an Apple pattern.** Foundation Models ships `CoreAILanguageModel`
  (ANE) vs `MLXLanguageModel` (GPU) as drop-in backends — exactly this file's "lego connector" idea.

### Conversion pipeline options (all real; none testable on this box — broken coremltools, no Core AI SDK)

| Path | Status | Notes |
|---|---|---|
| coremltools on **Python 3.11/3.12** → `.mlpackage` | works | the 3.14 break was a Python-version gap, not a tool bug |
| MLX weights → tiny **PyTorch** MLP → `coreai_torch` → `.aimodel` (Core AI) | 2026 forward path | auto CPU/GPU/ANE; needs iOS 27 / macOS 27 SDK |
| pure-Swift **SwiftCoreMLTools** → `.mlmodel` | viable but **unmaintained since 2020** | legacy format; only if no-Python is a hard rule |
| `CoreMLPolicy.swift` (this repo) loading a `.mlpackage`/`.mlmodel` with `computeUnits = .all` | wired, compiles | runtime side; needs a converted model from one of the above |

## Bottom line

Behavior comes from **training**, not from compute placement. Deploy by use:
- **Reactive per-tick agents (live game)** → GPU in-graph (MLX/Metal), lag-free — *not* the ANE
  (per-tick GPU↔ANE handoff + tiny-net overhead make it slower).
- **Decoupled "director"/meta model** (runs every few seconds) → **Core AI** auto-dispatches across
  CPU/GPU/ANE — this is where the ANE finally makes sense.

The model artifact is backend-agnostic, so wiring Core AI/ANE (decoupled model) or Brax/JAX (scale)
is a load step, not a rewrite.
