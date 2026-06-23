#!/usr/bin/env bash
# T4: fitness-per-wall-minute sweep over ES population. Same budget per run; compare clear%/fitness gain.
set -e
cd "$(dirname "$0")"
PY="${PY:-$(command -v python)}"
BUDGET="${BUDGET:-100}"
PERM="${PERM:-32}"
for POP in 128 256 512; do
  echo "======== POP=$POP PERM=$PERM budget=${BUDGET}s ========"
  "$PY" train_torch.py --dataset datasets/tiny \
    --perm $PERM --pop $POP --ticks 600 --cap 16 --bullets 32 \
    --iters 100000 --budget $BUDGET --compile \
    --eval-every 20 \
    --player-out /tmp/t4_player.json --enemy-out /tmp/t4_monster.json \
    2>&1 | grep -E "co-evolution|eval @|Player fitness|Enemy  fitness|reached"
  echo
done
