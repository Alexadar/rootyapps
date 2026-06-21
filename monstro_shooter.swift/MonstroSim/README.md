# MonstroSim

Headless, dependency-free simulation of Monstro Shooter for **automated playtesting**,
**map-difficulty/fun evaluation**, **training an ML player agent (pure Swift)**, and
**procedural map generation (autoconfig)** that balances new maps using the agent as the
fitness function.

**100% Swift, zero dependencies. No Python** — the sim, the agent training (Evolution
Strategies), and the map generator are all native Swift and run on the M1 CPU.

---

## Why this exists

Two goals:
1. **Train an agent** that plays the game with no UI, far faster than real time.
2. **Generate + auto-balance maps** ("autoconfig"): take example maps, produce new ones tuned
   to a target difficulty and maximal "fun", validated by the agent playing them headless.

The map format is just numbers (wave timings, counts, monster mixes), so map generation =
search over those parameters with the agent as the fitness function. This is the standard
**generate-and-test / experience-driven PCG** approach used by EA SEED, King, modl.ai, Ubisoft.

## Architecture

```
World.step(action) -> (observation, reward, terminated, truncated)
   spawn waves -> move monsters (steering) -> player move/aim/shoot
   -> bullet↔monster collision (circle) -> contact damage -> victory/death
```

- Loads the **same data files the game ships**: maps from `monstro_client/Resources/MapConfigs/*.json`,
  unit stats from `monstro_client/Assets/configs/**/*.yaml`. No logic is re-authored in another
  language — the formulas mirror the app's `Logic/` helpers and are pinned by parity tests.
- Collision replaces SpriteKit physics with brute-force circle checks (entity counts are small).
- **Seedable RNG** (SplitMix64) threaded through everything → reproducible training and *fair*
  map comparison (the shipping game's global random is not seedable; this is the key sim refactor).

## Targets

| Target | What |
|---|---|
| `MonstroSim` (lib) | The engine, policies, scoring, generator, ES trainer |
| `monstrosim` (exe) | CLI: `eval` / `train` / `autoconfig` |
| `MonstroSimTests` | Formula parity + determinism + smoke tests |

## Usage

```sh
swift build -c release   # release is ~10-50x faster than debug for training

# 1) Playtest a real map with the scripted baseline; print difficulty + fun
.build/release/monstrosim eval --map ../monstro_client/Resources/MapConfigs/map_0014.json --policy kiter --episodes 30

# 2) Train an agent in PURE SWIFT (Evolution Strategies, no Python/MLX)
.build/release/monstrosim train --map ../monstro_client/Resources/MapConfigs/map_0014.json --iterations 40 --out net.json
.build/release/monstrosim eval  --map ... --policy net --net net.json

# 3) Generate + auto-balance a new map from examples, targeting difficulty 0.6
.build/release/monstrosim autoconfig \
  --examples ../monstro_client/Resources/MapConfigs/map_0014.json,../monstro_client/Resources/MapConfigs/map_0020.json \
  --target 0.6 --fun 0.6 --policy net --net net.json --out generated_map.json
# generated_map.json is a real map the game loads.
```

---

## How big a model? (capacity / complexity)

The policy approximates a **reactive control function**: local threat geometry → (move, aim,
shoot). That is **low intrinsic complexity** — smooth, local, near-Markov when the observation
carries enough nearby-entity state. Concretely:

- **Observation**: egocentric. Player state (health, ammo, reload, aim, time) + the **K nearest
  monsters** as relative (dx, dy, vx, vy, dist, type), padded to fixed K. Default K=8 → 62 floats.
- **Network**: a **2-layer MLP, 128 units** is plenty. That is ~**25k–40k parameters**
  (62→128→128→27). This is smaller than an MNIST classifier. It trains on the M1 **CPU**.
- You do **not** need depth, CNNs, or transformers unless you switch to **pixel** observations
  (then a small CNN, overnight on the Metal GPU) or want emergent, superhuman play.

**"Lots of monsters, many different types" is an encoding problem, not a depth problem.**
K-nearest truncation loses information when swarmed, and a scalar `type` underuses type identity.
The principled upgrades (in order of effort), all still **small** nets:

1. **K-nearest + one-hot type** (cheap): replace scalar type with a one-hot/embedding of the
   monster type so the net can specialize per type (fast birds vs tanky berserkers). +K×(types) inputs.
2. **DeepSets / mean-pool** (permutation-invariant, any monster count): embed each monster
   `MLP_enc(type_embed, rel_pos, rel_vel) -> R^d`, **sum/mean-pool** over all monsters, concat
   player state, `MLP_head -> action`. Handles arbitrary counts with ~**100k–200k params**.
3. **Attention over entities** (best, OpenAI Five / the 2025 2D-shooter paper): the player state
   is the query, each monster a key/value; multi-head attention aggregates a variable set.
   ~**150k–400k params**. Overkill until you have many co-occurring types that need different
   responses.

Recommendation: ship K-nearest + type one-hot first; move to DeepSets when swarms/variety hurt.
Capacity is never the bottleneck here — **exploration + reward shaping** are. (Evolution Strategies
actually favors the *smaller* nets, which is another reason the pure-Swift path is a good default.)

---

## How "joy / playability" become ML factors and hyperparameters

You can't optimize "fun" directly — you optimize **measurable proxies** computed from headless
episodes, then weight them. These live in `Scoring.swift` (`DifficultyReport`, `FunReport`).

**Difficulty** (0 trivial → 1 brutal): driven by the agent's **best-case clear fraction**
(top run) and **death rate** — research shows top-percentile runs of even a weak agent track
human-perceived difficulty. `difficulty = 0.6·(1 − bestCaseClear) + 0.4·deathRate`.

**Fun / playability** = weighted composite of five proxies, each grounded in game-feel /
flow literature:

| Factor | Proxy (measured headless) | Why it maps to "joy" |
|---|---|---|
| **Challenge balance** | how close difficulty sits to a target *flow band* | too easy = boring, too hard = frustrating; fun peaks in-band |
| **Pacing variety** | coefficient of variation of per-second monster pressure | flat pressure is dull; ebb-and-flow feels alive |
| **Engagement** | accuracy / active-aimed-fire fraction | rewards active play, punishes idle/spray/camping |
| **Fairness** | low survival variance across seeds | outcomes from skill/map, not an RNG lottery |
| **Progression** | pressure–time correlation (ramp up) | escalation/tension arc |

`fun = 0.35·challenge + 0.20·pacing + 0.20·engagement + 0.15·fairness + 0.10·progression`.

**These weights ARE the design hyperparameters.** They encode *your* definition of fun for this
game. Different genres reweight: a relaxed game raises fairness/lowers challenge; a bullet-hell
raises pacing/challenge. The autoconfig loop then maximizes `−|difficulty − target| + w·fun`, so
you tune the *target difficulty band* and the *fun weight vector* to shape what maps get produced.

**Two pitfalls (the research warned; one already observed here):**
- **Reward/metric hacking.** An early autoconfig run hit the difficulty target by generating
  exponentially huge, *unclearable* waves the player simply never finishes — "hard" by length,
  not by threat (the kiter took 0 damage). Fix: make `difficulty` weight damage-taken / near-death
  more, and/or normalize expected monsters against episode length so "unclearable" can't dominate.
- **Camping bias.** Distance/survival shaping can train a passive agent. Counter with the
  engagement term and a damage-taken penalty (already in the per-step reward).

Reward shaping itself (in `World.step`): `+0.01` survival, `+1` per kill, `−0.05·damage`,
`±10` terminal. Keep it bounded (the 2025 shooter paper uses `tanh`) and prefer
**potential-based shaping** when densifying, so you don't change the optimal policy.

---

## Roadmap / upgrades (all stay in Swift)

- Type one-hot → DeepSets/attention observation encoder (above).
- Stronger agent: keep ES but scale population/iterations, or add a Swift PPO on the Metal GPU
  via **MLX-Swift** (`ml-explore/mlx-swift`, Apple's array+autodiff framework) — still no Python.
- Tighten the difficulty metric (damage/near-death weighting) to kill the unclearable-wave exploit.
- Curriculum: autoconfig a *ladder* of maps at increasing target difficulty.
