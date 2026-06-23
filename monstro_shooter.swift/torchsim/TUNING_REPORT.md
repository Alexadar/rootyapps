# torchsim tuning report (RTX 3090) — honest findings

Env: conda `fantastic` (Python 3.14.3, torch 2.12.1+cu130, jax 0.10.2 + optax 0.2.8), RTX 3090 24 GB.
Method: fixed wall-budget runs under `torch.compile` fusion; GPU util/mem/power sampled every 0.25 s;
quality = **clear %** over a 9-game held-out eval (3 maps × 3 seeds). All quality claims are multi-seed.
CPU parity guard (kills=56.0 / hp=47936.0) re-run after every `env_torch.py` change — bit-identical throughout.

## TL;DR
- **GPU fill (T1):** real, hardware-level win for the PPO path — util 76%→94%. Kept.
- **PPO vs ES (the headline):** on a *fair fixed metric*, 5 seeds, **they're a statistical TIE** (PPO 67.8% ± 28,
  ES 65.0% ± 27). The single-seed "PPO 2.25×" does **not** replicate. **Default reverted to ES** (simpler, robust).
- **Eval metric was contaminated** — fixed (A): eval now runs vs a constant opponent, not the co-evolving enemy.
- **Co-evolution is the real blocker** (Red-Queen / seed-fragility). Tested stabilization (B) — **didn't help here**.
- **JAX-PPO (T4):** built, 1.74× faster than torch-PPO (caveat below). Don't migrate the default.

---

## A new flag was required first: `--seed`
Every run was bit-identical before (hardcoded init seeds), so "multi-seed" was impossible. Added `--seed`
(training-only; sim uses `det_rand`, not global RNG → parity-safe; seed=0 == original run).

## T1 — Fill the GPU (KEPT; PPO path)
Old cuda PPO default (`ppo-group=64`, `ppo-minibatch=16384`): **76% util / 1.5 GB / 280 W**. Root cause was the
tiny minibatch → ~2400 launch-bound micro optimizer steps/iter, starving the GPU. Sweep (g128/p32, 50 s):

| minibatch | util | clear (9 games) |
|---|---|---|
| 16384 (old) | 72.6% | 11% |
| 65536 | 92.7% | 35% |
| **262144** | **93.9%** | **40%** ← knee |
| 524288 | 94.0% | 22% (underfits) |

**Before→after (PPO path):** util 76%→94%, power 280→316 W. `ppo-group=128 ppo-minibatch=262144`.
Note: **ES is already GPU-saturated** (95–96% util at `pop=256`, 0.95 GB), so T1 only matters when `--algo ppo`
is selected. The knee (262144) is single-seed — treat as "much bigger than 16384", not a precise optimum.

## T2/T3/V — PPO vs ES, honestly (DEFAULT = ES)
- **T2 (3-seed, 90 s, live metric):** default PPO (lr 3e-4) was unstable and *lost* to ES (44% vs 74% clear).
- **T3:** found lr 3e-4→1e-4 stabilizes PPO (+ ent 0.003, std 0.5; epochs=10 harmful). Baked into `train_torch.py`.
  At 90 s tuned PPO looked ahead of ES (78 vs 74%) — but that was 3 seeds on the **contaminated live metric**.
- **V (5-seed, 60 s, FIXED scripted metric — the fair test):**

  | algo | clear% (s0–s4) | mean | std |
  |---|---|---|---|
  | PPO (tuned) | 88,90,82,24,55 | 67.8% | ~28 |
  | ES | 88,85,76,23,53 | 65.0% | ~27 |

  **PPO's 2.8 pt edge ≪ 1 std → statistical TIE.** Seed 3 collapsed for *both* (24 vs 23) — a hard-seed/co-evo
  problem, not the algorithm. → **`train.sh` default reverted to `--algo es`** (simpler, robust). The tuned-PPO
  config remains fully selectable and GPU-filled. GRPO confirmed worse (dead-end).

## A — Fixed-reference eval (DONE; the metric fix)
The old eval played the player vs the **co-evolving** enemy, so clear% measured the arms race, not skill — it
bounced 6→94→2% as the enemy strengthened (your 300 s run finished at 34% for exactly this reason). New
`--eval-vs {fixed,scripted,live}`: **scripted** = canonical monster steering, identical for every run/seed (a
constant, game-realistic yardstick); **fixed** = frozen iter-0 snapshot; **live** = old behavior (diagnostic).
`train.sh` now uses `--eval-vs scripted` so the eval-every trace is interpretable player progress.

## B — Co-evolution stabilization (TESTED; did NOT help here)
The +4.15 runaway enemy is Red-Queen oscillation. Added `--enemy-every K` (asymmetric cadence — slow the enemy)
and `--enemy-pool N` (PSRO-lite league — player trains vs a mix of past enemy snapshots). Defaults reproduce the
old 50/50 loop exactly. 5-seed results (ES, 60 s, scripted):

| config | mean clear |
|---|---|
| baseline | 65.0% |
| + pool-only (`enemy-pool 4`) | 61.2% (≈ no change) |
| + pool + slow-enemy (`enemy-every 4`) | 33.6% (worse) |

**Slowing the enemy under-trains the player** — against the hard scripted reference you want a *strong* training
opponent. The pool alone is neutral, and **neither fixes the seed collapses**. Left OFF by default; flags remain
for experimentation. The genuine fragility (some seeds collapse for every config) needs deeper work — see below.

## T4 — JAX-PPO (BUILT: `jax_ppo.py`; 1.74×, don't migrate)
Pure-JAX PPO: PRNG through the rollout `lax.scan`, GAE via reverse `lax.scan`, optax Adam minibatched under jit.
Reuses the parity-proven `env_jax` (refactored `step`→`step_pa`, re-verified bit-identical at P=1). A/B vs
torch-PPO, same frozen enemy, TF32 fair: **torch 0.86 vs jax 1.49 updates/s = 1.74×**. **Caveat:** torch-PPO's
GAE is a 600-iter Python loop; some of the 1.74× is removable torch overhead, so the fair *structural* win is
likely closer to the ~1.23–1.3× ES-jax showed. **Recommendation: keep torch default** (Core ML export needs it;
jax-PPO isn't wired into co-evo/reward-shaping/eval). jax-PPO exports the same `{sizes,w,b}` JSON (round-trip OK).

## T5 — Reward shaping (DONE; current is fine)
Added parity-safe dense damage-dealt term (`--rw-damage`, default 0.0, capped at monster HP). On tuned PPO it
didn't help (rw_damage 0.02 ≈ same; 0.05 destabilizes; rw_kill 2.0 lowers clear). Verified: any `rw_*` changes
`rp` but leaves kills/hp **bit-identical**. Left at defaults.

## T6/T7 — scoped, not built
- **T6 (enemy PG):** split `_core` into pre-spawn → expose enemy obs → inject `a_enemy` → post-spawn
  (`step_pa2`) to make the enemy PPO too. Deferred.
- **T7 (async APPO/IMPALA):** would address the residual ~6% util bubble but makes PPO off-policy — overkill;
  scan-fusion (T4) is the better lever.

## What's actually capping model quality (next work)
Not the algorithm (PPO≈ES) and not GPU util (95%+). It's **co-evolution seed-fragility**: some seeds collapse
regardless of algo/stabilization. Promising directions not yet tried: a real population/league with fitness
sharing, enemy-update trust regions, or decoupling the eval target (deploy-vs-live-enemy vs skill-vs-scripted)
and optimizing the one that matters for the shipped game.

## Render crash fix (the `sh train.sh` traceback)
Root cause: base conda lacks `imageio-ffmpeg` → imageio's PyAV fallback can't open h264. Fixes: (1) `train.sh`
prefers the `fantastic` env, (2) render fails fast with a clear message instead of a cryptic traceback,
(3) the render step is non-fatal (models save regardless). Verified in both envs.

## Net changes (all uncommitted)
- `train.sh` — default `--algo es`, `--eval-vs scripted`, prefer `fantastic` env; tuned-PPO documented/selectable.
- `train_torch.py` — `--seed`, `--rw-damage`, `--eval-vs`, `--enemy-every`, `--enemy-pool`; PPO defaults tuned
  (lr 1e-4 / ent 0.003 / std 0.5); fixed-reference eval; non-fatal render.
- `env_torch.py` — parity-safe dense damage-dealt term (default off).
- `env_jax.py` — `step`→`step_pa` split (parity-neutral).
- `render_eval.py` — backend-aware writer (clear error without imageio-ffmpeg).
- `jax_ppo.py` — NEW fully-fused JAX PPO + A/B benchmark.
