#!/usr/bin/env bash
# POC launch: co-evolve player + enemy on the 10 swiper maps, then eval on the UNSEEN held-out map.
# Pass extra flags through, e.g.:  ./run_poc.sh --device mps   |   ./run_poc.sh --device cuda --perm 32 --pop 64
set -e
cd "$(dirname "$0")"
PY="${PY:-../.venv-torch/bin/python}"

"$PY" train_torch.py \
  --perm 2 --pop 6 --ticks 300 --iters 12 --cap 40 --bullets 24 \
  --eval \
  "$@"
