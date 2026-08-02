# torchsim Producer — Report

## FINAL CONCLUSION (2026-07-10)

**Delivered:** a co-evolved adaptive world generator holding the player at the
chosen 62% win equilibrium. Artifact: `data/world_coevolved.json`
(θ knob table + 4k-param dealer network, browser-portable) +
`runs/coevolve_final.pt` (both sides). Measured at the true 480-week game on
4,608 fresh episodes: **argmax 0.640 / noisy-play 0.602 / old-player 0.648**
(CI ±1.5%) — all skill groups within ~0.03 of target, i.e. the generator
adapts difficulty per session rather than per global table.

**Final co-evolution config** (the one that converged; all flags in
`coevolve.py`): 1 PPO iter : 6 ES gens per round; ES lr 0.015–0.02 with
**proportional gate-error damping** (quarter-force near the band); sigma
0.4× (dealer 0.02 / θ-z 0.06) — below the win-cliff width; per-skill-group
fitness (current ×4, two old checkpoints, τ=1.0/1.5 sampled), first-episode-
only counting, 480-week (or compressed survive-192) horizons everywhere;
FIFO-7 generator league as env blocks + bank anchor; FIFO-6 player league
mixture for fitness; player lr 1.5e-4, entropy 0.005 fixed; final-round
artifact, never keep-best.

**Method conclusions** (full recipe: `BALANCE_GUIDE.md`): the original game
was unwinnable (gate caught it in hours); every static balance was broken by
the next trained agent (twice); search-calibrated knobs fix a balance for one
agent, co-evolution is what makes it hold across skill levels; the four
convergence fixes that mattered were tempo asymmetry, sigma-vs-cliff,
horizon alignment, and proportional damping.

**Deferred (documented, tooling ready):** `validate_coevo.py` fresh-player
acceptance test + cross-table + AUC probe — the pre-ship checklist.

---

# Phases 1–4 Report (session history)

**Date:** 2026-07-09 · **Hardware:** RTX 3090 · **Predecessor:** `GATE_REPORT.md` (STEP-0)

## What exists now

A GPU-batched, statistically-parity-validated torch replica of the (patched)
Producer Tycoon rules, an RL player trained on it, and a CEM searcher that
learns game-balance vectors — the requested "learnable game hyperparameters".

```
scripts/exportConstants.ts     TS -> game_constants.json (single source of truth)
scripts/goldenVectors.ts       2000 seeded TS episodes x 3 policies, weekly checkpoints
torchsim/world_config.py       constants + normalizers + 17 learnable knobs (theta)
torchsim/tables.py             offline precompute: 1M-artist bank, event tables
torchsim/env_producer.py       [N]-batched env, 95-action masked space, per-env theta
torchsim/obs_producer.py       bounded scale-invariant obs (Fs=48, Fm=35 x 14 tokens)
torchsim/py_policies.py        vectorized mirrors of the TS gate policies
torchsim/test_parity.py        statistical parity suite (KS, tie-corrected)
torchsim/policy_producer.py    single-query attention -> 95 masked logits (-1e4)
torchsim/train_ppo.py          PPO + GAE, decomposition panel, keep-best on eval win
torchsim/cem_gen.py            CEM over theta -> difficulty ladder JSON
```

## Phase 1–2: parity (gate PASSED)

- **102/102 statistical tests pass** (KS alpha=0.001 Bonferroni; weekly
  checkpoints 4..480 for money/fans/tokens/rep/roster/releases × 3 policies
  + finals + outcome frequencies).
- Outcome-rate agreement TS vs torch: greedy **bankrupt 31.4% vs 31.4%,
  win-fans 68.4% vs 68.4%** (max deviation 0.001); spam 1.3%; random 0.0%.
- **Throughput: 2.08M decision-steps/s** at N=4096 (policy+mask included),
  eager torch, no compile — 10× the 200k gate.
- Documented approximations: one active need per artist (TS allows a list;
  P(overlap) ≈ 0.8%/wk); producer spec fixed to `talented`; per-week
  candidate-pair reroll capped by the 16-action week budget.
- Two harness lessons preserved for reuse: (1) two-sample KS **must advance
  both pointers on ties** or identical discrete distributions read D=1.0;
  (2) mirrors of imperative weekly policies need the TS ordering quirks —
  upper-median for even rosters, purchases-before-releases, action-budget
  guards — before mid-game money distributions line up.

## Phase 3: PPO player (gate PASSED — with a finding that matters more)

Single-query attention over 14 artist tokens (d=32, H=128, Ht=64, ~30k
params), masked categorical over 95 actions, PPO N=4096 × T=256
(γ=0.997, λ=0.95, 104-week training horizon with value bootstrap).

**Result: 99.2% win rate (eval, full-length, argmax) vs greedy's 68.7% —
+30.5 points — reached within ~20 iterations (~4 minutes of training).**

### The finding: a real, in-rules economy exploit

The agent's strategy is a **release machine-gun**: 15.5 releases/week (the
action cap), ~790 releases per run, 79% of all its actions are "release the
artist in slot 0/1", winning by fans at median week 12–53. It works because:

1. Releases have **no per-week limit** in the game rules — only tokens gate them.
2. Token rewards are **self-feeding**: Нормальний nets ~+1.5 tokens per release,
   Хіт ~+3 — every release funds more than one more release.
3. After the STEP-0 payout rebalance, mid-tiers earn money — so mass-release
   prints fans AND money simultaneously.

The STEP-0 scripted gate missed this because every scripted policy released
each artist at most once per week *by convention*. The RL agent had no such
convention. **This is the pipeline doing its actual job: four minutes of PPO
found a degenerate optimum that heuristic playtesting missed.** (For the TS
game, the minimal fixes would be a per-artist release cooldown or
tokenReward < 1 net; per instruction the TS game was left untouched — the
knob `token_reward_mult` was added to theta instead.)

## Phase 4: learnable game hyperparameters (CEM)

`theta` = 17 knobs (per-tier pay multipliers, release/tour/upgrade/equip cost
multipliers, salary multiplier, start money, event chances, luck spread,
bankruptcy floor, token reward multiplier). `ProducerEnv` takes **per-env
theta**, so one batch evaluates a whole CEM population: 24 candidates × 192
seeds = 4608 different-balance games per iteration, no gradients.

Fitness per difficulty target d: |win_rate(frozen agent) − target(d)| +
shape penalties (games shorter than ~6 months penalized; all-tour or
no-tour strategy monocultures penalized). Ladder rungs warm-start the next.
Output: `data/generated_worlds.json` — plain knob tables the TS game could
read directly (no torch on device).

### Results (gate PASSED)

Each rung took 40–64 s of search (18 CEM iterations). Out-of-sample
validation on 512 fresh seeds per rung (`validate_ladder.py`):

| rung | target win | achieved (fresh seeds) | bankrupt | med weeks | token_reward_mult |
|---|---|---|---|---|---|
| default θ | — | 0.998 | 0.002 | 12 | 1.00 |
| easy | 0.85 | **0.863** | 0.137 | 36 | 0.43 |
| medium | 0.60 | **0.594** | 0.406 | 56 | 0.22 |
| hard | 0.35 | **0.363** | 0.635 | 36 | 0.27 |

Monotone: PASS. Targets within 0.1 out-of-sample: PASS (all within 0.015).

**The searcher independently discovered the exploit's oxygen supply:** every
rung throttles `token_reward_mult` (1.0 → 0.43 → 0.22) — starving the
release machine-gun is *the* difficulty axis against this agent — combined
with tighter bankruptcy floors and cost shifts. Games stretch from a
degenerate 12 weeks to 36–56 weeks. This is the balance patch the TS game
would want, found by search instead of hand-tuning, in ~2.5 minutes.

## The self-improvement loop — TWO ROUNDS EXECUTED

**Round 2 (agent):** retrained under the theta ladder (domain randomization
over {default + 3 rungs}, N=16384, ~10 min) with **theta-aware observations**
(the agent sees the 17 knob values — a difficulty-conditioned policy).
Training passed through a transient *survival-win* phase (rungs won via the
10-year condition at week 480 — a win path CEM round 1 never priced, because
the round-1 agent never used it), then converged to **99.7% mean win across
all rungs**, med 10–23 weeks. Post-hoc behavior on the medium rung: the token
throttle works as a rate limiter (4.4 releases/week, tokens pinned at 1), but
the agent adapted — studio maxed early, then **77% of releases are Культовий**
(fan yield ~1.5M each). Diagnosis: *fan yield per release was not in the knob
set* — CEM could price money and tokens but not the win currency itself.

**Round 2 (generator):** added `fan_rate_mult` (hidden from the agent's obs —
an unobserved difficulty dimension) and re-ran CEM against the v2 agent.
Out-of-sample validation (384 fresh seeds/rung):

| rung | target | achieved | med weeks |
|---|---|---|---|
| default | — | 0.995 | 10 |
| easy | 0.85 | **0.810** | 47 |
| medium | 0.60 | **0.568** | 52 |
| hard | 0.35 | **0.310** | 31 |

Monotone PASS, all within 0.04–0.05. `data/generated_worlds_r2.json`.

Every loop iteration so far has surfaced exactly one unpriced dimension
(tokens → survival-wins → fan yield), and one CEM round repaired it — the
co-evolution dynamic working as designed. The keep-best lesson from monstro
applies verbatim: a difficulty ladder is only calibrated against the strategy
distribution of the agent it was tuned on.

## Learned content generator: the artist DEALER (transformer, ES-trained)

Per user direction ("generate with transformer"), content generation moved a
level deeper than knobs: `dealer.py` is a tiny population-batched attention
generator (~4k params) that replaces the i.i.d. artist bank for candidate
slots. Conditioned on [target win rate, week, game summary] + single-query
attention over a K=8 memory of its own recent deals, it emits distribution
parameters (stat means/sigmas, genre/archetype logits, trait moments) and
samples the weekly candidate pair. Trained with antithetic OpenAI-ES
(pop 64 × 96 episodes each, all in one batched env) against the frozen v2
agent to hit three win-rate targets simultaneously via CONTENT alone (all
knobs at default). Init lesson: ES needs the untrained dealer to deal
bank-like artists (sigma≈12 via output-bias init) — from a random init the
agent never wins and the fitness landscape is flat.

*Results appended when the run completes.*

## Performance note (the "51% GPU" question)

The workload is kernel-launch-bound (a ~30k-param policy issues ~300 tiny
kernels per step), not sync- or compute-bound: removing all 13 hidden
GPU→CPU syncs (.any() guards, int(sum()) in _new_pair) left throughput flat,
while batch size scales it near-linearly — 561k steps/s at N=4096 →
**2.32M steps/s at N=32768**. Round-2 training ran at N=16384 (493k steps/s
end-to-end, 1.6× round 1). Next 2–4× would need CUDA-graph capture
(torch.compile reduce-overhead): requires dropping explicit RNG generator
args and the two remaining dynamic-shape writes (sign copy, equip buy).
Utilization % is a red herring at this model size; wall time is the metric.

## Known gaps / honest caveats

- Parity was validated against the STEP-0-patched TS game as of this date;
  any TS change requires `exportConstants` + `goldenVectors` + parity rerun.
- The trained agent is an exploit specialist; its play style is not
  "interesting" gameplay. The interesting agent comes after round 2 of the
  loop (train under repaired theta).
- validate_producer.py (coverage/behaviour/attribution families) not yet
  written — next after the CEM ladder.
- CoreML export (Phase 5) deliberately deferred: coremltools isn't installed
  here, and the artifact worth shipping is the round-2 agent (trained under
  the repaired theta ladder), not the exploit specialist. The policy was kept
  static-shape and -1e4-masked from day one so export stays mechanical
  (monstro's export_coreml.py pipeline applies directly).
