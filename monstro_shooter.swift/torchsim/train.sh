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
else                             # Mac (mps/cpu): fast dev loop
  PERM=16; POP=48;  TICKS=200; BULLETS=24; BUDGET=300
  PPO_GROUP=64;  PPO_MB=16384                            # small GPU: keep the lightweight defaults
  POLICY_BF16=""                                         # bf16 unreliable on mps -> fp32 on the mac
fi
# DEFAULT = ES (mirrored-sampling Evolution Strategies) + torch.compile fusion. Enemy also ES (co-evolution).
# Honest validation (3090, 5-seed, 60s, eval vs the FIXED scripted reference — clear% = absolute player skill,
# not the co-evolving arms race): PPO and ES are a STATISTICAL TIE — PPO 67.8% clear (std ~28) vs ES 65.0%
# (std ~27); the 2.8pt edge is far inside the noise, so the earlier single-seed "PPO 2.25x" does NOT hold.
# ES is simpler + more robust -> it's the default. Tuned PPO is selectable and fully GPU-filled:
#   ACCEL="--algo ppo --compile --ppo-group $PPO_GROUP --ppo-minibatch $PPO_MB"   (lr/ent/std tuned in train_torch.py)
# Co-evo is seed-FRAGILE (some seeds collapse for every algo). Stabilization knobs --enemy-every K (slow the
# enemy) / --enemy-pool N (PSRO-lite league) were tested and did NOT help here (slowing the enemy under-trains
# the player vs the hard scripted reference: ES+stab 33.6%, pool-only 61.2%) -> left OFF by default.
ACCEL="--algo es --compile $POLICY_BF16"
echo "device=$DEV  perm=$PERM pop=$POP ticks=$TICKS bullets=$BULLETS budget=${BUDGET}s  accel=$ACCEL"

# --eval-vs scripted = a FIXED, game-realistic opponent held constant across the run, so the eval-every
# trace is interpretable player progress (the old live-enemy metric bounced 6->94->2% as the enemy evolved).
# --keep-best = save the PEAK fixed-eval checkpoint, not the final weights. Diagnosis (3090, fine traces):
# co-evo collapse is LATE + OSCILLATORY — the enemy runs away (fitness 2.2->5.6) and the player's skill-vs-
# fixed swings ±50pts iter-to-iter, so the final weight is a lottery (same seed ended 23% at 60s, 75% at 90s).
# keep-best captures the ~85-94% peak regardless of stop point: 5-seed mean 65->75%, max 88->92%. For the most
# reliable model, run train_multi.py (best-of-K restarts + keep-best) -> ~92% in ~5 min; it dodges the rare
# seed that fails EARLY and never recovers (keep-best alone can't save those).
"$PY" train_torch.py \
  --dataset datasets/tiny \
  --perm $PERM --pop $POP --ticks $TICKS --cap 16 --bullets $BULLETS \
  --iters 40000 --budget $BUDGET $ACCEL \
  --eval --eval-seeds 3 --eval-every 30 --eval-vs scripted --keep-best \
  --render datasets/tiny/eval/grid.mp4
