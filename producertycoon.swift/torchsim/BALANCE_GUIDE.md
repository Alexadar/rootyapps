# How to make a good game balance (the method, distilled)

What this directory proved on Producer Tycoon, written as a recipe you can
rerun on any content/economy change. Every claim below was measured here, not
assumed; the tooling to re-measure it is in this directory.

## The five-step loop

### 1. Gate first — prove decisions matter (hours, before anything else)
Drive the REAL game headlessly with scripted policies spanning "blind" to
"informed" (`scripts/gateRun.ts` → `gate_analyze.py`). The game is broken if:
- everything loses (our v0: **100% bankruptcy in ≤20 weeks** — payouts made
  every release tier below the top LOSE money while the weekly loop forces
  releases), or
- blind spam ≈ smart play (decisions cosmetic), or
- variance swamps decisions (tier-lottery check).
Fix in the game data, rerun the gate. `gate_analyze.py` is a permanent
balance regression test: run it after every content patch.

### 2. Mirror the sim, prove parity, THEN trust it
A torch replica (`env_producer.py`) is only usable after **statistical
parity** vs the real game: same scripted policies, KS tests on weekly
checkpoints + outcome rates (`test_parity.py`, 102/102 here; outcome
agreement to 0.1%). Rule-parity, not bit-parity — RNG streams differ.
Traps that cost us time: two-sample KS needs tie handling; policy mirrors
must reproduce ordering quirks (purchases-before-releases, upper-median).

### 3. Let RL find what playtesting can't
A small attention policy + PPO found a **real in-rules exploit in ~4 minutes**
(release machine-gun: no per-week release cap + self-feeding token rewards),
then — after that was patched via search — found the NEXT hole (fan yield).
Lesson: **every static balance gets broken by the next agent.** Budget for
the loop, not for a one-shot fix. An agent winning ≫ target via one action
spammed is your tell; log action histograms and tier mixes, not just win rate.

### 4. Make balance parameters learnable (search, don't hand-tune)
Expose knobs (θ: payouts, costs, chances, token/fan yields — `world_config.GEN_KNOBS`)
and let CEM/ES calibrate them against the trained agent to target win rates
(`cem_gen.py`: hit 0.85/0.60/0.35 within ±0.05 out-of-sample, ~1 min per
difficulty). Critical details:
- **first-completed-episode-only** win counting (window counting is length-
  biased and the generator can game it),
- calibrate at the SAME horizon you'll judge at (survive-to-end counts as a
  win — a 208-week-capped fitness systematically mis-calibrates a 480-week game),
- sigmoid-reparametrize knobs for search (raw scales differ by 10^5),
- hinge-only regularizers (zero gradient when satisfied = nothing to hack),
  and log every fitness term separately — a regularizer trending while the
  win term is flat is hacking in progress.

### 5. Co-evolve for a balance that STAYS balanced
Player (PPO) vs world-generator (dealer network + θ, one ES genome) with the
generator's objective = **calibration** (hold every skill group at the target
win rate), not adversarial max. What it took to converge (each fix from a
measured failure, see REPORT_TORCHSIM.md):
- **Tempo**: 1 PPO iter : 6 ES gens per round — the player out-learns the
  generator at any friendlier ratio (mirror of monstro's cadence rule).
- **Cliff vs sigma**: win rate is nearly binary in θ (snowball economy);
  ES sigma must be narrower than the cliff or you optimize a smoothed
  objective and deploy an unsmoothed point that sits on the wrong side.
- **Proportional damping**: scale the ES step by |gate − target| — undamped,
  the loop ping-pongs 0.5↔0.9 forever; damped, it orbited 0.635–0.685.
- **Per-skill-group fitness** (current player, noisy variants, old
  checkpoints — each targeted at 0.62) forces the generator to infer
  difficulty from session state = an adaptive levelgen, not a static table.
- Leagues both sides + a permanent unmodified-world anchor block; final-round
  artifact only (best-of-population is winner's-curse noise).

## Target and result

Chosen equilibrium: **player win 62%**. Delivered artifact
(`data/world_coevolved.json`): θ + dealer weights measured at
**0.640 argmax / 0.602 noisy / 0.648 old-player** on 4,608 fresh
full-length (480-week) episodes (95% CI ±1.5%) — all skill groups within
~0.03 of target. The dealer is ~4k parameters (plain matmuls + one masked
softmax): portable to a browser session as the in-game level/content
generator.

## What is NOT yet proven (run before shipping)

`validate_coevo.py` implements the full acceptance protocol; the piece that
matters most was not run within session budget: the **fresh-player test** —
train a brand-new agent against the frozen generator; it must plateau near
62% too. That test is the only one that catches generator-fingerprinting
(worlds fair only to the co-evolved player's style) and residual exploits.
Also run its week-4→outcome AUC probe (healthy 0.55–0.80; ≥0.9 means games
are decided at deal time = fake balance).
