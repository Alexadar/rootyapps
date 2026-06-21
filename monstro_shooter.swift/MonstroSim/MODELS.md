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

## Bottom line

Inference on the GPU, in-graph, lag-free — same engine as training. The model artifact is backend-
agnostic, so wiring Core ML/ANE (for a future decoupled model) or Brax/JAX (for scale) is a load
step, not a rewrite.
