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

if [ "$DEV" = "cuda" ]; then     # 3090: big enemy-ES population + full-map episodes + long budget
  PERM=32; POP=256; TICKS=600; BULLETS=32; BUDGET=300    # POP=256 = enemy-ES sweet spot (T4). BUDGET secs (5 min)
else                             # Mac (mps/cpu): fast dev loop
  PERM=16; POP=48;  TICKS=200; BULLETS=24; BUDGET=300
fi
# PPO player (clipped surrogate + critic + GAE) beat ES ~2.25x on eval-per-wall-time (clear 18% vs 8% in a
# 110s mps A/B) — the sample-efficiency win. + torch.compile fusion. Enemy still ES (co-evolution).
# Fallbacks still selectable: --algo es | --algo grpo | --engine jax.
ACCEL="--algo ppo --compile"
echo "device=$DEV  perm=$PERM pop=$POP ticks=$TICKS bullets=$BULLETS budget=${BUDGET}s  accel=$ACCEL"

"$PY" train_torch.py \
  --dataset datasets/tiny \
  --perm $PERM --pop $POP --ticks $TICKS --cap 16 --bullets $BULLETS \
  --iters 40000 --budget $BUDGET $ACCEL \
  --eval --eval-seeds 3 --eval-every 30 \
  --render datasets/tiny/eval/grid.mp4
