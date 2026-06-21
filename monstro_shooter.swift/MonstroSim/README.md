# MonstroSim — GPU-only RL engine (lego before braxification)

A headless, GPU-resident simulation of Monstro Shooter with an on-device RL agent. **One engine
(`MonstroSimGPU`) is shared by the trainer and (later) the game** — training runs N envs + ES with
one sync per episode; the game will run the same `BatchWorld` at N=1 with one sync per frame.
**Models are detached artifacts** (portable JSON weights in `models/`). Pure Swift + MLX (Metal).
No CPU sim, no Python.

## Layout

```
Sources/MonstroSim/      shared infra: SeededGenerator, SimConstants, config/map loaders, types
Sources/MonstroSimGPU/   the engine: BatchWorld (vectorized, mx.compile-fused), SpawnSchedule,
                         GPUPolicy (MLP in-graph), GPUES (Evolution Strategies)
Sources/MonstroCLI/      gputrain / gpueval / gprun / gpubench / gpuprofile
models/                  shipped trained weights (detached artifact; CI/CD regen later)
```

## Architecture (one engine, two callers)

```
TRAINER (headless):  N = maps×seeds envs → rolloutPlayer → ES → per-EPISODE sync
GAME (later):        N = 1 env          → step + render   → per-FRAME sync
                     ▲ both use the SAME BatchWorld.step + GPUPolicy ▲
```

The whole episode runs in-graph on the GPU (policy forward fused with the sim); the CPU syncs once
per episode (training) or once per frame (game). See the conversation/plan for the per-tick-sync
analysis that motivated this.

## Use

```sh
swift build -c release          # build metallib once — see GPU_SETUP.md, then stage it
# train a player (ES, on-device, per-episode sync)
.build/release/monstrosim gputrain --map <map.json> --envs 512 --ticks 400 --pop 20 --iters 40 --out models/player.json
# does it play? trained vs random on HELD-OUT seeds
.build/release/monstrosim gpueval  --map <map.json> --net models/player.json
# run a shipped model through the engine (the game's inference path, headless)
.build/release/monstrosim gprun    --map <map.json> --net models/player.json
# throughput / per-phase profile
.build/release/monstrosim gpubench  --map <map.json> --envs 4096
.build/release/monstrosim gpuprofile --map <map.json>
```

## Status (proven on M1 Pro)

- BatchWorld: thousands of envs as batched tensors, `mx.compile` fusion (~1.5× over unfused).
- On-device player policy + ES: **learns** — 5.5 vs 2.3 kills vs random on held-out seeds.
- One sync per episode (no per-tick CPU bottleneck). Memory gentle (~50 MB host).
- The M1 GPU is *marginal vs a 10-core CPU* on sparse maps (dispatch-bound); it wins on dense
  scenes and big nets. The real scale-up is the **3090 / Brax (JAX)** port — same design, ~7×
  hardware, `jax.jit` fusion, batched-population eval, per-type monster nets + co-evolution.

## Models, portability, and NPU — see [MODELS.md](MODELS.md)

The JSON weights are the **lego connector**: same artifact → GPU inference now (recommended),
Core ML/ANE export later (optional), Brax/JAX later. Short version: keep inference **on the GPU
in-graph** (lag-free); the Apple Neural Engine is inference-only and *re-introduces* a per-tick
GPU↔ANE handoff for a reactive policy, so it's not wired (correctly) — details in MODELS.md.
