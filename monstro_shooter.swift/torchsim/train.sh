#!/usr/bin/env bash
# Train player + enemy co-evolution on the tiny dataset, then multi-seed eval + a 3x3 grid render.
# Device is AUTO-DETECTED (cuda -> mps -> cpu) and params AUTO-SCALED: big on the 3090, small here.
# Same script, both machines. Override the python via:  PY=/path/python ./train.sh
set -e
cd "$(dirname "$0")"
# PY override > mac dev venv > conda env 'fantastic' (3090's known-good deps incl. imageio-ffmpeg for
# --render; `sh train.sh` otherwise picks base python3 which lacks it and the render step errors) > python3.
_cbase="${CONDA_EXE:+$(dirname "$(dirname "$CONDA_EXE")")}"
_fant="$_cbase/envs/fantastic/bin/python"
PY="${PY:-$([ -x ../.venv-torch/bin/python ] && echo ../.venv-torch/bin/python || { [ -x "$_fant" ] && echo "$_fant"; } || command -v python3 || command -v python)}"

DEV=$("$PY" - <<'PYEOF'
import torch
mps = getattr(torch.backends, "mps", None)
print("cuda" if torch.cuda.is_available() else ("mps" if mps and mps.is_available() else "cpu"))
PYEOF
)

if [ "$DEV" = "cuda" ]; then     # 3090: big enemy-ES population + full-map episodes + long budget
  PERM=32; POP=256; TICKS=600; BULLETS=32; BUDGET=300    # POP=256 = enemy-ES sweet spot (T4). BUDGET secs (5 min)
  # PPO batch (T1 GPU-fill sweep, 3090): ppo-group=128 + ppo-minibatch=262144 took util 76%->94%,
  # power 280->316W, clear 16%->40% over the old g64/mb16384 default. The OLD mb=16384 ran ~2400
  # launch-bound micro optimizer steps/iter (tiny matmuls) — starving the GPU AND adding gradient
  # noise. group=128 beats 256 (more, equally-good iters); mb past 262144 underfits (too few steps).
  PPO_GROUP=128; PPO_MB=262144
  # PERF (3090, profiled): the per-monster enemy MLP is ~43% of the tick and MEMORY-bound, so bf16 halves
  # its traffic -> ~1.3x rollout AND ~1.4x more ES iters/budget (40s A/B: fp32 15 iters/16% clear vs bf16
  # 21 iters/46%). SIM stays fp32 (game logic unaffected) — only the policy forward + parity checksum change.
  POLICY_BF16="--policy-bf16"
  RESTARTS=5                                             # co-evo is seed-fragile; best-of-5 dodges collapses
else                             # Mac (mps/cpu): fast dev loop
  PERM=16; POP=48;  TICKS=200; BULLETS=24; BUDGET=300
  PPO_GROUP=64;  PPO_MB=16384                            # small GPU: keep the lightweight defaults
  POLICY_BF16=""                                         # bf16 unreliable on mps -> fp32 on the mac
  RESTARTS=3                                             # fewer restarts on the slow dev box
fi
RBUDGET=$((BUDGET / RESTARTS))                           # per-restart budget so total wall-time ≈ BUDGET
# DEFAULT = ES (mirrored-sampling Evolution Strategies) + torch.compile fusion. Enemy also ES (co-evolution).
# Honest validation (3090, 5-seed, 60s, eval vs the FIXED scripted reference — clear% = absolute player skill,
# not the co-evolving arms race): PPO and ES are a STATISTICAL TIE — PPO 67.8% clear (std ~28) vs ES 65.0%
# (std ~27); the 2.8pt edge is far inside the noise, so the earlier single-seed "PPO 2.25x" does NOT hold.
# ES is simpler + more robust -> it's the default. To use tuned PPO instead, pass it through train_multi:
#   --algo ppo --extra="--compile --keep-best $POLICY_BF16 --ppo-group $PPO_GROUP --ppo-minibatch $PPO_MB"
# Co-evo is seed-FRAGILE (some seeds collapse for every algo). Stabilization knobs --enemy-every K (slow the
# enemy) / --enemy-pool N (PSRO-lite league) were tested and did NOT help here (slowing the enemy under-trains
# the player vs the hard scripted reference: ES+stab 33.6%, pool-only 61.2%) -> left OFF by default.
echo "device=$DEV  perm=$PERM pop=$POP ticks=$TICKS bullets=$BULLETS  best-of-${RESTARTS} x ${RBUDGET}s  bf16=${POLICY_BF16:-off}"

# Why train_multi (best-of-K) instead of a single run: co-evo is seed-FRAGILE — collapse is LATE +
# OSCILLATORY (the enemy runs away, fitness 2.2->5.6; the player's skill-vs-fixed swings ±50pts iter-to-iter,
# so a single run's final weight is a lottery: the SAME seed ended 23% at 60s, 75% at 90s). Two fixes stack:
#  --keep-best  saves the PEAK fixed-eval checkpoint (not the collapsed final) — captures the ~85% peak; and
#  best-of-K restarts dodges the rare seed that fails EARLY and never peaks (keep-best alone can't save those).
# Measured (3090, new maps, 8-dim obs + bf16): best-of-5 = 85% clear vs a single run's 21-85% lottery.
# --eval-vs scripted = a FIXED, game-realistic opponent, so the eval-every trace is interpretable player skill
# (the old live-enemy metric bounced 6->94->2% as the co-evolving enemy strengthened).
"$PY" train_multi.py \
  --restarts $RESTARTS --dataset datasets/tiny --algo es \
  --perm $PERM --pop $POP --ticks $TICKS --bullets $BULLETS \
  --budget $RBUDGET --eval-vs scripted --eval-every 6 \
  --extra="--keep-best $POLICY_BF16" \
  --player-out ../MonstroSim/models/player.json --enemy-out ../MonstroSim/models/monster.json

# render a 3x3 eval grid of the BEST model (player vs its co-evolved enemy = the deployed pair)
"$PY" render_eval.py --dataset datasets/tiny \
  --player ../MonstroSim/models/player.json --enemy ../MonstroSim/models/monster.json \
  --out datasets/tiny/eval/grid.mp4 || echo "  [render skipped — needs imageio-ffmpeg]"
