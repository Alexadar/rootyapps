#!/usr/bin/env bash
# ONE full-reward run with tensorboard. Logs per-iter fitness + PPO loss, per-eval survival/clear/kills/dmg,
# and per-reward-term RAW value + weighted CONTRIBUTION curves. All key knobs are env-overridable so rounds
# are one-liners. Each RUN writes its own subdir under $OUT so tensorboard compares them side by side:
#   tensorboard --logdir /tmp/rxp            # baseline 'tb' + 'round1' + ...
# Round 1 (default below) = the co-evo rebalance + reward de-shaping bundle.
set -e
cd "$(dirname "$0")"
_fant="$(dirname "$(dirname "${CONDA_EXE:-/home/oleksandr/miniconda3/bin/conda}")")/envs/fantastic/bin/python"
PY="${PY:-$([ -x "$_fant" ] && echo "$_fant" || command -v python3)}"
export PYTORCH_CUDA_ALLOC_CONF="${PYTORCH_CUDA_ALLOC_CONF:-expandable_segments:True}"
OUT="${OUT:-/tmp/rxp}"; RUN="${RUN:-round1}"; LOG="$OUT/$RUN"; mkdir -p "$OUT"

# --- round-1 bundle (override any via env) ---
ENEMY_EVERY="${ENEMY_EVERY:-4}"      # player gets 3 PPO steps per enemy ES step (was 2 = 50/50)
ENEMY_POOL="${ENEMY_POOL:-6}"        # train vs a league of past enemies (was 1 = newest only)
RW_AIM="${RW_AIM:-0.02}"             # demote aim proxy below kill (was 0.05)
RW_HIT="${RW_HIT:-0.15}"             # penalty no longer exceeds kill (was 0.30)
RW_E_APPROACH="${RW_E_APPROACH:-0.0004}"  # tame the enemy's dense closing gradient (was 0.0008)
RW_E_DEATHS="${RW_E_DEATHS:-0.02}"   # enemy: penalty per monster killed (set 0 = flock charges in, no fear of death)
RW_KILL="${RW_KILL:-1.0}"            # objective weight; raise to push the player to CLEAR more (round-2)
RW_DAMAGE="${RW_DAMAGE:-0.02}"       # dense landing-shot reward; raise alongside kill for more aggression
RW_SEPARATE="${RW_SEPARATE:-0.02}"   # enemy: anti-stacking penalty (redundant w/ rigid bodies; set 0 to drop)

"$PY" train_torch.py --dataset datasets/surround --perm 16 --pop 256 --cap 32 --bullets "${BULLETS:-24}" --ticks 600 \
  --algo ppo --player-arch attn --ppo-group 64 --ppo-minibatch 262144 --compile --policy-bf16 \
  --iters 100000 --budget "${BUDGET:-600}" --eval-every "${EVAL_EVERY:-15}" --eval-vs "${EVAL_VS:-live}" --eval --eval-panel \
  --logdir "$LOG" --weapons "${WEAPONS:-1,5,4}" --range-rand "${RANGE_RAND:-0.3,1.0}" \
  --enemy-every "$ENEMY_EVERY" --enemy-pool "$ENEMY_POOL" \
  --rw-hit "$RW_HIT" --rw-kill "$RW_KILL" --rw-survive 0.01 --rw-space 0.0 --space-keep 2 --rw-aim "$RW_AIM" \
  --rw-ring 0.03 --ring-radius 90 --rw-effort 0.005 --rw-shot 0.01 --rw-damage "$RW_DAMAGE" \
  --rw-align 0.01 --rw-separate "$RW_SEPARATE" --sep-radius 50 \
  --rw-e-approach "$RW_E_APPROACH" --rw-e-deaths "$RW_E_DEATHS" \
  --render "datasets/surround/eval/grid.mp4" \
  --player-out "$OUT/p_$RUN.json" --enemy-out "$OUT/m_$RUN.json"
echo "##### DONE [$RUN] — tensorboard --logdir $OUT ; video datasets/surround/eval/grid.mp4 #####"
