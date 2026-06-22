# MonstroSim — GPU training engine + playable Metal game

Two things that share **game data files** and a **portable model-weights artifact** — not (yet) a
single step function:

- **`MonstroSimGPU`** — a GPU-batched *training* engine (thousands of envs as MLX/Metal tensors,
  on-device player policy + Evolution Strategies, one sync per episode). Driven by the `monstrosim` CLI.
- **`monstro-game`** (`Sources/MetalGame`) — the *playable* game: a standalone Metal engine running the
  whole loop in compute kernels with instanced-sprite rendering, no SpriteKit.

They are independent implementations of the same game (a third, JAX, lives in `../brax` for 3090-scale
training). The connective tissue is the **model JSON** (`models/player.json`) — trained by MLX or JAX,
runnable in the Metal game or exported to Core ML/ANE. **Unifying the kinetics into one shared engine
is future work.** Pure Swift + MLX (Metal). No CPU sim, no Python.

## Layout

```
Sources/MonstroSim/      shared infra: SeededGenerator, SimConstants, config/map loaders
Sources/MonstroSimGPU/   training engine: BatchWorld (mx.compile-fused), SpawnSchedule,
                         GPUPolicy (MLP in-graph), GPUES (ES), CoreMLPolicy (ANE connector)
Sources/MonstroCLI/      monstrosim: gputrain / gpueval / gprun / aneinfer / gpubench / gpuprofile
Sources/MetalGame/       monstro-game: the playable GPU game (Metal compute + instanced render)
models/                  detached artifacts: player.json (weights), player.mlmodel (Core ML)
tools/export_coreml.py   offline: player.json -> player.mlmodel (coremltools, Py3.11)
```

## Use

```sh
swift build -c release          # build metallib once — see GPU_SETUP.md, then stage it

# --- training engine (MonstroSimGPU) ---
.build/release/monstrosim gputrain --map <map.json> --envs 512 --ticks 400 --pop 20 --iters 40 --out models/player.json
.build/release/monstrosim gpueval  --map <map.json> --net models/player.json   # trained vs random, held-out
.build/release/monstrosim gprun    --map <map.json> --net models/player.json   # run a model headless
.build/release/monstrosim aneinfer                                             # Core ML CPU/GPU/ANE parity vs MLX
.build/release/monstrosim gpubench --map <map.json> --envs 4096                # throughput / profile

# --- the playable game (separate Metal engine) ---
swift run -c release monstro-game --window        # WASD; auto-fire at nearest
swift run -c release monstro-game --frames 600    # headless playthrough (stats + PNG)
swift run -c release monstro-game --frames 600 --agent models/player.mlmodel   # player driven by Core ML
```

## Architecture (Apple-blessed, WWDC 2026)

Metal-4 rendering for the game + **Core ML / Core AI for the learned agents** (the split Apple
showcased — their flagship Core AI demo is a learned game NPC). Training is off-runtime: **MLX on
Mac** (`MonstroSimGPU`) or **JAX on a 3090** (`../brax`, optional accelerator). The connector is the
portable weights JSON → Core ML `.mlmodel` (verified `aneinfer`) → Core AI `.aimodel` on macOS 27.
We deliberately do **not** run the whole sim on GPU compute (off Apple's path); the agent runs via
Core ML, the game via Metal.

## Status (proven on M1 Pro)

- BatchWorld: thousands of envs as batched tensors, `mx.compile` fusion (~1.5× over unfused).
- On-device player policy + ES **learns** — 5.5 vs 2.3 kills vs random on held-out seeds; one sync
  per episode; ~50 MB host.
- The M1 GPU is *marginal vs a 10-core CPU* on sparse maps (dispatch-bound); it wins on dense scenes
  and big nets. The real scale-up is the **3090 / JAX** port (`../brax`) — same design, ~7× hardware,
  `jax.jit` fusion, batched-population, per-type monster nets + co-evolution.

## Models, portability, NPU — see [MODELS.md](MODELS.md)

The JSON weights are the **connector**: same artifact → MLX (now) / Metal game / Core ML+ANE
(`aneinfer`, verified) / JAX. Keep the *reactive per-tick* policy **GPU-in-graph** (lag-free); the
Core ML/ANE path is for a **decoupled/shipped** model (details + the 2026 Core AI note in MODELS.md).
