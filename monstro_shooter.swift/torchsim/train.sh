#!/usr/bin/env bash
# Train player + enemy co-evolution on the tiny dataset, then multi-seed eval + a 3x3 grid render.
# Device is AUTO-DETECTED (cuda -> mps -> cpu) and params AUTO-SCALED: big on the 3090, small here.
# Same script, both machines. Override the python via:  PY=/path/python ./train.sh
set -e
cd "$(dirname "$0")"
# PY override > the mac dev venv (if present) > whatever python is active (e.g. the 3090 venv)
PY="${PY:-$([ -x ../.venv-torch/bin/python ] && echo ../.venv-torch/bin/python || command -v python3 || command -v python)}"

DEV=$("$PY" - <<'PYEOF'
import torch
mps = getattr(torch.backends, "mps", None)
print("cuda" if torch.cuda.is_available() else ("mps" if mps and mps.is_available() else "cpu"))
PYEOF
)

if [ "$DEV" = "cuda" ]; then     # 3090: big ES population + full-map episodes + long budget
  # POP=256 wins fitness/min over 128 & 512 (T4 sweep): the player net actually improves (+3.7) and
  # holds the co-evo balance; 128 lets the enemy run away, 512 is too few iters. VRAM ~0.5/24 GiB.
  PERM=32; POP=256; TICKS=600; BULLETS=32; BUDGET=1800
  # JAX lax.scan rollout = the fastest engine here: ~1.21x more iters/wall-time than torch-fusion
  # end-to-end (T3), same model quality (env_jax is parity-proven). Needs jax[cuda12].
  ACCEL="--engine jax"
else                             # Mac (mps/cpu): fast dev loop. jax would be CPU-only here, so use
  PERM=16; POP=48;  TICKS=200; BULLETS=24; BUDGET=300   # torch.compile fusion (5.3x on mps) instead.
  ACCEL="--compile"
fi
echo "device=$DEV  perm=$PERM pop=$POP ticks=$TICKS bullets=$BULLETS budget=${BUDGET}s  accel=$ACCEL"

"$PY" train_torch.py \
  --dataset datasets/tiny \
  --perm $PERM --pop $POP --ticks $TICKS --cap 16 --bullets $BULLETS \
  --iters 40000 --budget $BUDGET $ACCEL \
  --eval --eval-seeds 3 --eval-every 30 \
  --render datasets/tiny/eval/grid.mp4
