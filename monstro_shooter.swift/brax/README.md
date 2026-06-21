# brax/ — JAX/CUDA training engine (the braxified MonstroSim)

The MLX/Metal engine (`MonstroSim/Sources/MonstroSimGPU`) ported to **JAX** for the **RTX 3090**
(CUDA): `jax.jit` fuses the step, `jax.lax.scan` runs a whole episode on-device (one sync), and
**`jax.vmap` evaluates the entire ES population in one pass** — the pop× speedup the sequential MLX
trainer couldn't do. "Braxify" = the Brax *paradigm* (custom vectorized env), not the rigid-body lib.

Loads the **same** game data as the Swift engine (`monstro_client/Resources/MapConfigs/*.json`,
`Assets/configs/**/*.yaml`). Weights round-trip as the same JSON artifact (`models/player.json`) →
JAX ⇄ MLX/Metal ⇄ Core ML.

## Files
- `env.py` — JAX `BatchWorld` (state pytree, jit `step`, `lax.scan` rollout, aim-shaped reward).
- `policy.py` — MLP (same math as `GPUPolicy.swift`); `load_player_json` for cross-checks.
- `es.py` — Evolution Strategies, **vmapped population**, centered-rank shaping (mirror `GPUES`).
- `schedule.py` — numpy spawn-schedule precompute (mirror `SpawnSchedule.swift`).
- `data.py` — load map JSON + unit YAML (mirror `Configs.swift`).
- `train.py` — CLI: `train` / `eval` / `parity`.

## Run

```sh
pip install -r requirements.txt          # 3090: pip install "jax[cuda12]"

# verify the port matches the Swift engine (forward bit-parity):
python train.py parity --net ../MonstroSim/models/player.json

# dev smoke (CPU, tiny — defaults are small on purpose):
python train.py train --map /path/map.json --envs 16 --ticks 180 --iters 4 --pop 8

# real scale (3090): crank N, ticks, iters
python train.py train --map /path/map.json --envs 4096 --ticks 600 --iters 200 --pop 32 --out player.json
python train.py eval  --map /path/map.json --net player.json    # trained vs random, held-out seeds
```

## Status / parity
- **Verified on JAX-CPU:** parity (max|Δ|≈0 vs Swift/MLX), `jit` compiles, ES learns (reward ↑).
- **Rule-parity, not bit-exact** for the sim: JAX threefry RNG ≠ Swift `SeededGenerator`, so spawn
  rolls differ — mechanics/distributions match, the MLP forward is bit-identical.
- **Phase 1–2 done** (port + vmapped-population ES). **Next:** Phase 3 map×seed batching
  (`N = maps × seeds`), Phase 4 per-type monster nets + staged co-evolution — the natural-behavior
  goal, run at 3090 scale.
