#!/usr/bin/env bash
# Train player + enemy co-evolution on the surround dataset, then multi-seed eval + a 3x3 grid render.
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
  PERM=32; POP=256                                       # POP=256 = enemy-ES sweet spot (T4)
  # BULLETS = bullet ring-buffer slots. Collision+dodge are all-pairs over B×M, so B is pure cost — but it
  # must be >= max SIMULTANEOUS alive bullets for the weapon or a live bullet gets overwritten (changes the
  # sim). Pistol peaks at 2 alive; 8 gives margin (parity-EXACT vs 32: kills/hp identical). SIZE UP for fast
  # guns (minigun/shotgun: faster fire × pellets => more alive). Was 32 (16x oversized for the pistol).
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
  PERM=16; POP=48                                        # mac: small/fast dev loop
  PPO_GROUP=64;  PPO_MB=16384                            # small GPU: keep the lightweight defaults
  POLICY_BF16=""                                         # bf16 unreliable on mps -> fp32 on the mac
fi

# --- dataset / run params (NOT device-scaled; each is env-overridable, e.g. BUDGET=600 ./train.sh) ---
DATASET="${DATASET:-datasets/surround}"
TICKS="${TICKS:-600}"      # MUST cover the map round so the game can complete (clear/death). surround = 20s = 600
CAP="${CAP:-16}"           # monster slots = max simultaneous monsters a map can have (surround totals <=16)
BULLETS="${BULLETS:-8}"    # bullet ring slots; >= weapon's max simultaneous alive bullets (pistol=2; size up for fast guns)
BUDGET="${BUDGET:-2400}"   # wall-time seconds (40 min). longer = more convergence (was 300 = 5 min)
EVAL_SEEDS="${EVAL_SEEDS:-3}"   # 3 eval maps x 3 seeds = the 3x3 render grid
EVAL_EVERY="${EVAL_EVERY:-30}"
ITERS="${ITERS:-40000}"
# reward shaping (training-only, parity-safe). RW_HIT = penalty per HP TAKEN — high so the player is
# DAMAGE-AVERSE and learns to dodge/move instead of tanking (was 0.05; 0.30 = 6x). Tune via env if needed.
RW_HIT="${RW_HIT:-0.30}"; RW_KILL="${RW_KILL:-1.0}"; RW_SURVIVE="${RW_SURVIVE:-0.01}"
# RW_SPACE = reward for keeping monsters spaced (allow SPACE_KEEP close, keep the rest away) -> proactive
# dodging, not fleeing (saturates). SPACE_KEEP=2 = "max 2 monsters close".
RW_SPACE="${RW_SPACE:-0.01}"; SPACE_KEEP="${SPACE_KEEP:-2}"
RW_AIM="${RW_AIM:-0.05}"   # reward for aiming at the threat (raised 0.005->0.05 so aim tracks the pack, not fixed)
# DEFAULT = ES (mirrored-sampling Evolution Strategies) + torch.compile fusion. Enemy also ES (co-evolution).
# Honest validation (3090, 5-seed, 60s, eval vs the FIXED scripted reference — clear% = absolute player skill,
# not the co-evolving arms race): PPO and ES are a STATISTICAL TIE — PPO 67.8% clear (std ~28) vs ES 65.0%
# (std ~27); the 2.8pt edge is far inside the noise, so the earlier single-seed "PPO 2.25x" does NOT hold.
# ES is simpler + more robust -> it's the default. To use tuned PPO instead:
#   --algo ppo --ppo-group $PPO_GROUP --ppo-minibatch $PPO_MB   (lr/ent/std tuned in train_torch.py)
# For the most robust model despite seed-fragility, run best-of-K manually:  python train_multi.py --restarts 5
ACCEL="--algo es --compile $POLICY_BF16"
echo "device=$DEV  data=$DATASET  perm=$PERM pop=$POP ticks=$TICKS cap=$CAP bullets=$BULLETS budget=${BUDGET}s  accel=$ACCEL"

# ONE full-budget run (long enough to converge). --keep-best saves the PEAK fixed-eval checkpoint, not the
# final weights — co-evo collapse is LATE + OSCILLATORY (the enemy runs away, the player's skill-vs-fixed
# swings ±50pts late), so the last weight is a lottery; keep-best grabs the peak instead.
# --eval-vs scripted = a FIXED game-realistic opponent, so the eval-every trace is interpretable player skill.
"$PY" train_torch.py \
  --dataset "$DATASET" \
  --perm $PERM --pop $POP --ticks $TICKS --cap $CAP --bullets $BULLETS \
  --iters $ITERS --budget $BUDGET $ACCEL \
  --rw-hit $RW_HIT --rw-kill $RW_KILL --rw-survive $RW_SURVIVE --rw-space $RW_SPACE --space-keep $SPACE_KEEP --rw-aim $RW_AIM \
  --eval --eval-seeds $EVAL_SEEDS --eval-every $EVAL_EVERY --eval-vs scripted --keep-best \
  --render "$DATASET/eval/grid.mp4"
