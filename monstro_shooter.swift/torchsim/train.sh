#!/usr/bin/env bash
# Canonical training: player (PPO + single-query attention) vs enemy (ES) co-evolution on the surround dataset
# (with static rock obstacles + a clearance flow field), then live-enemy eval + a 3x3 weapons-x-maps grid render.
# Device is AUTO-DETECTED (cuda -> mps -> cpu) and the heavy params AUTO-SCALED (big on the 3090, small on the mac).
# Every knob is env-overridable, e.g.:   BUDGET=1800 ./train.sh      FREEZE_ENEMY=1 WEAPONS=1 ./train.sh
set -e
cd "$(dirname "$0")"
# PY override > conda env 'fantastic' (project's known-good deps: torch, coremltools, imageio-ffmpeg for --render)
# > python3. No venv — both machines use conda 'fantastic'.
_cbase="${CONDA_EXE:+$(dirname "$(dirname "$CONDA_EXE")")}"
_fant="$_cbase/envs/fantastic/bin/python"
PY="${PY:-$([ -x "$_fant" ] && echo "$_fant" || command -v python3 || command -v python)}"
export PYTORCH_CUDA_ALLOC_CONF="${PYTORCH_CUDA_ALLOC_CONF:-expandable_segments:True}"

DEV=$("$PY" - <<'PYEOF'
import torch
mps = getattr(torch.backends, "mps", None)
print("cuda" if torch.cuda.is_available() else ("mps" if mps and mps.is_available() else "cpu"))
PYEOF
)

if [ "$DEV" = "cuda" ]; then     # 3090: big enemy-ES population + bf16 policy. perm16/group64 is the validated fit
  # for the current obs (attention + rocks/flow). perm32/group128 OOMs a 24GB card now (the obs grew + flow grid).
  PERM=16; POP=256; PPO_GROUP=64; PPO_MB=262144; POLICY_BF16="--policy-bf16"
else                             # mac (mps/cpu): small/fast dev loop, fp32 (bf16 unreliable on mps)
  PERM=16; POP=48;  PPO_GROUP=64;  PPO_MB=16384;  POLICY_BF16=""
fi

# --- run params (NOT device-scaled; each env-overridable) ---
DATASET="${DATASET:-datasets/surround}"
TICKS="${TICKS:-600}"      # must cover the map round (surround = 20s = 600 ticks)
CAP="${CAP:-32}"           # monster slots = max simultaneous monsters per map
BULLETS="${BULLETS:-24}"   # bullet ring slots; 24 gives headroom for the fast/multi-pellet guns (minigun/shotgun)
BUDGET="${BUDGET:-900}"    # wall-time seconds (15 min). BUDGET=1800 (30m) / 3600 (1h) to converge further.
ITERS="${ITERS:-40000}"; EVAL_SEEDS="${EVAL_SEEDS:-3}"; EVAL_EVERY="${EVAL_EVERY:-40}"
OUT="${OUT:-/tmp/rxp}"; RUN="${RUN:-run}"; LOGDIR="${LOGDIR:-$OUT/$RUN}"; mkdir -p "$OUT"

# weapon generalization: ONE weapon-conditioned policy across pistol/minigun/shotgun (ids 1,5,4), cycled per iter.
# range-rand shrinks bullet range 0.3-1.0x per iter so the player learns hold-fire / range discipline.
WEAPONS="${WEAPONS:-1,5,4}"; RANGE_RAND="${RANGE_RAND:-0.3,1.0}"
# co-evolution cadence: enemy trains 1-in-4 iters (player gets 3 PPO steps each) vs a league of 6 past enemies, so
# the enemy can't run away early. FREEZE_ENEMY=1 freezes the enemy entirely (player converges vs a static foe).
ENEMY_EVERY="${ENEMY_EVERY:-4}"; ENEMY_POOL="${ENEMY_POOL:-6}"
[ "${FREEZE_ENEMY:-0}" = "1" ] && FREEZE="--freeze-enemy" || FREEZE=""
# reward shaping (training-only, parity-safe) — the validated weights. RW_HIT = penalty/HP taken (damage-averse);
# RW_RING = keep-out personal-space penalty (PPO learns its own predictor -> reactive dodging); RW_DAMAGE = dense
# landing-shot reward (pairs with RW_SHOT cost -> trigger discipline). RW_ALIGN/RW_SEPARATE = enemy swarm shaping.
RW_HIT="${RW_HIT:-0.15}"; RW_KILL="${RW_KILL:-1.5}"; RW_SURVIVE="${RW_SURVIVE:-0.01}"; RW_AIM="${RW_AIM:-0.02}"
RW_DAMAGE="${RW_DAMAGE:-0.03}"; RW_RING="${RW_RING:-0.03}"; RING_RADIUS="${RING_RADIUS:-90}"
RW_EFFORT="${RW_EFFORT:-0.005}"; RW_SHOT="${RW_SHOT:-0.01}"
RW_ALIGN="${RW_ALIGN:-0.01}"; RW_SEPARATE="${RW_SEPARATE:-0.02}"; SEP_RADIUS="${SEP_RADIUS:-50}"
RW_E_APPROACH="${RW_E_APPROACH:-0.0004}"; RW_E_DEATHS="${RW_E_DEATHS:-0.02}"   # enemy: tame closing gradient; death penalty
EVAL_VS="${EVAL_VS:-live}"   # eval opponent: live (co-evolving) or fixed (frozen snapshot)
ACCEL="--algo ppo --player-arch attn --ppo-group $PPO_GROUP --ppo-minibatch $PPO_MB --compile $POLICY_BF16"
echo "device=$DEV data=$DATASET perm=$PERM pop=$POP ticks=$TICKS cap=$CAP bullets=$BULLETS budget=${BUDGET}s weapons=$WEAPONS"

"$PY" train_torch.py \
  --dataset "$DATASET" \
  --perm $PERM --pop $POP --ticks $TICKS --cap $CAP --bullets $BULLETS \
  --iters $ITERS --budget $BUDGET $ACCEL \
  --weapons "$WEAPONS" --range-rand "$RANGE_RAND" \
  --enemy-every $ENEMY_EVERY --enemy-pool $ENEMY_POOL $FREEZE \
  --rw-hit $RW_HIT --rw-kill $RW_KILL --rw-survive $RW_SURVIVE --rw-space 0.0 --space-keep 2 --rw-aim $RW_AIM \
  --rw-ring $RW_RING --ring-radius $RING_RADIUS --rw-effort $RW_EFFORT --rw-shot $RW_SHOT --rw-damage $RW_DAMAGE \
  --rw-align $RW_ALIGN --rw-separate $RW_SEPARATE --sep-radius $SEP_RADIUS \
  --rw-e-approach $RW_E_APPROACH --rw-e-deaths $RW_E_DEATHS \
  --eval --eval-seeds $EVAL_SEEDS --eval-every $EVAL_EVERY --eval-vs "$EVAL_VS" --eval-panel \
  --logdir "$LOGDIR" \
  --render "$DATASET/eval/grid.mp4" \
  --player-out "$OUT/p_$RUN.json" --enemy-out "$OUT/m_$RUN.json"
echo "##### DONE [$RUN] — models $OUT/{p,m}_$RUN.json ; tensorboard --logdir $OUT ; video $DATASET/eval/grid.mp4 #####"
