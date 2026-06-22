#!/usr/bin/env bash
# POC launch: co-evolve player + enemy on the 10 swiper maps for ~5 min, then eval on the UNSEEN map.
# Time-budgeted (--budget 300): runs as many iters as fit, then saves. Stops cleanly at the budget.
# Pass extra flags through, e.g.:  ./run_poc.sh --device mps   |   ./run_poc.sh --device cuda --budget 0 --iters 200
set -e
cd "$(dirname "$0")"
PY="${PY:-../.venv-torch/bin/python}"

"$PY" train_torch.py \
  --perm 3 --pop 12 --ticks 300 --cap 48 --bullets 24 \
  --iters 4000 --budget 300 \
  --eval \
  "$@"
