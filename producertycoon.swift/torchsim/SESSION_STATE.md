# Session state dump — 2026-07-10 (WRAPPED — see FINAL CONCLUSION in REPORT_TORCHSIM.md)

**Final status:** artifact delivered (data/world_coevolved.json from
coevolve7/ckpt_r02: 0.640/0.602/0.648 @480wk, CI ±1.5%). qkv-dealer line
(coevolve8/9) reached 0.68-0.72 with tighter skill gaps but wasn't given time
to fully converge — it's the recommended line to continue. Pre-ship checklist:
run validate_coevo.py (fresh-player test especially). Only torchsim/ is
committed; TS game changes + scripts/ left uncommitted by user instruction.

--- (historical pause notes below) ---


**Goal (user-set):** monstro-style co-evolution: 1 player (PPO) vs 1 "enemy" =
world generator (dealer net ~4k params + 18 θ knobs, single ES genome).
Equilibrium: player win **62%**. Deliverable: a **levelgen model for player
sessions** that **infers difficulty from session state** (no difficulty input) —
enforced by per-skill-group fitness (current player argmax ×4, two old
checkpoints, τ=1.0 and τ=1.5 sampled variants — each group targeted at 0.62).
NO Swift/CoreML export (dropped by user).

## Where co-evolution stands

Run `runs/coevolve5` (STOPPED for PC shutdown; safe — per-round checkpoints):
gates 0.706 → 0.857 → 0.549 → 0.508, fit 0.186 (best), player healthy
(ent ~0.9, ref-win ~1.0). **Orbiting the target with shrinking amplitude** —
resume and let it produce rounds inside the band, then select the checkpoint
with gate closest to 0.62 (gate CI ±1.5%, sound selection).

Resume command:
```
cd torchsim && nohup python3 -u coevolve.py --resume runs/coevolve5/ckpt_r04.pt \
  --rounds 40 --budget-min 90 --ppo-iters 1 --es-gens 6 --es-lr 0.015 \
  --sigma-scale 0.4 --full-after 0 --out runs/coevolve6 > runs/coevolve6.log 2>&1 &
```

## Tuning history (why those flags — each from a diagnosed failure)

1. v1 (6 PPO : 2 ES, lr .03): player out-tempos generator, gate stuck 0.72–0.84.
2. v2 (3:5, lr .06): oscillation 0.70→0.98 — ES steps overshoot a SHARP
   win-rate cliff (snowball economy: slightly richer world → everyone wins).
3. v3 (lr .03): still drifting up — PPO iters still too strong.
4. v4 (1 PPO : 6 ES + current-player weighted ×4 in fitness): diagnosis via
   within-round log: **ES optimizes the σ-smoothed objective but we deploy the
   unsmoothed mean** (pop mean 0.62 while mean genome gates 0.94) + **fitness
   ran at 208wk while gate at 480wk** (timeout=loss vs survive=win — C4).
5. v5 (= current flags): σ×0.4, lr .015, 480wk fitness → orbiting, damping.

## Next steps (TODO)

1. Resume co-evolution (command above), run until several rounds land in
   0.62±0.03 (band_hits) or budget; artifact = round ckpt with gate closest
   to 0.62 → copy as runs/coevolve_final/generator_final.pt (or rerun the
   tail of coevolve.py's artifact dump).
2. `python3 validate_coevo.py --dir <final run dir>` — cross-table, headline
   CI, sequence curves (undecided@104wk > 25%), week-4 AUC, and THE
   acceptance test: fresh random player trained vs frozen generator must
   plateau at 0.62±0.05 (catches exploitability AND fingerprinting).
3. If oscillation still too wide to land in band: next lever = gate-feedback
   damping (halve es-lr when gate error grows round-over-round), or replace
   |wr−0.62| with logit-distance to soften the cliff.
4. Append co-evolution section + validation results to REPORT_TORCHSIM.md.
5. Decide with user: wire dealer (JSON, ~4k params, plain matmuls) into the
   TS game as the session levelgen; git commit strategy (EVERYTHING is still
   uncommitted: TS balance patch, scripts/, torchsim/, reports).

## Key artifacts / files

- runs/coevolve5/ckpt_r04.pt — latest co-evo state (player+gen_mean+meta)
- runs/v2_ladder/best.json — θ-aware player (Fs=65), the co-evo warm start
- data/generated_worlds{,_r2}.json — CEM ladders (pre-co-evo, superseded)
- data/world_coevolved.json — will be overwritten by final artifact dump
- torchsim/{coevolve,validate_coevo,dealer,train_ppo,env_producer}.py
- GATE_REPORT.md, REPORT_TORCHSIM.md — reports so far
- Parity: test_parity.py (102/102 as of C1 fix); gate_analyze.py = balance
  regression tool for the TS game

## Gotchas for the next session

- Long runs: nohup+disown (Bash tool background tasks die at 10-min timeout).
- coevolve.py --resume loads BOTH sides from ckpt (Adam state not preserved).
- Two-sample KS needs tie handling (test_parity.py has the fixed version).
- torch RNG: `.any()` guards / int(sum()) in hot loops = GPU→CPU sync; the
  workload is kernel-launch-bound — batch size is the throughput lever
  (N=32768 → 2.3M steps/s).
- fan_rate_mult is deliberately hidden from the player's obs (17 of 18 knobs
  observed; W.OBS_KNOB_NAMES frozen for v2-player compat).
