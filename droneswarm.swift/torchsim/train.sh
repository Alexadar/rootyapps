#!/usr/bin/env bash
# Canonical training: drone swarm (CTBR + attention) vs coevolving enemy (unicycle/social-force + anti-air).
# Device AUTO-DETECTED (cuda -> mps -> cpu), heavy knobs AUTO-SCALED (big on the 3090, small on the mac).
# Every knob env-overridable, e.g.:  BUDGET=1800 ./train.sh    FREEZE_ENEMY=1 ./train.sh
set -euo pipefail
cd "$(dirname "$0")"
# prefer conda 'fantastic' (torch + av for the renderer), else python3 (monstro train.sh:10-12 idiom)
_cbase="${CONDA_EXE:+$(dirname "$(dirname "$CONDA_EXE")")}"
_fant="$_cbase/envs/fantastic/bin/python"
PY="${PY:-$([ -x "$_fant" ] && echo "$_fant" || command -v python3 || command -v python)}"
export PYTORCH_CUDA_ALLOC_CONF="${PYTORCH_CUDA_ALLOC_CONF:-expandable_segments:True}"
export PYTHONUNBUFFERED=1   # live stdout when redirected to a log (froggo idiom)
export TORCHINDUCTOR_CACHE_DIR="${TORCHINDUCTOR_CACHE_DIR:-$HOME/.cache/torchinductor_droneswarm}"  # persist compile across relaunches

DEV=$("$PY" - <<'PYEOF'
import torch
mps = getattr(torch.backends, "mps", None)
print("cuda" if torch.cuda.is_available() else ("mps" if mps and mps.is_available() else "cpu"))
PYEOF
)

if [ "$DEV" = "cuda" ]; then     # 3090: wide batch, bf16 policy, compiled _core
  N_ENVS="${N_ENVS:-1024}"; PPO_GROUP="${PPO_GROUP:-4}"; ENEMY_GROUP="${ENEMY_GROUP:-8}"
  PPO_MB="${PPO_MB:-262144}"; ACCEL="--compile --policy-bf16"
else                             # mac/cpu: small/fast dev loop, fp32
  N_ENVS="${N_ENVS:-32}"; PPO_GROUP="${PPO_GROUP:-2}"; ENEMY_GROUP="${ENEMY_GROUP:-2}"
  PPO_MB="${PPO_MB:-16384}"; ACCEL=""
fi

DRONES="${DRONES:-16}"; ENEMIES="${ENEMIES:-12}"; OBST="${OBST:-24}"; TICKS="${TICKS:-750}"
BUDGET="${BUDGET:-300}"; ITERS="${ITERS:-40000}"
EVAL_EVERY="${EVAL_EVERY:-20}"; EVAL_SEEDS="${EVAL_SEEDS:-16}"
ENEMY_EVERY="${ENEMY_EVERY:-4}"; ENEMY_POOL="${ENEMY_POOL:-6}"; AA_WARMUP="${AA_WARMUP:-15}"
# KILL_CURR="3 40" bootstraps kills: kamikaze radius starts 3x, anneals to 1x over 40 iters. Empty = off.
KILL_CURR="${KILL_CURR:-3 40}"; [ -n "$KILL_CURR" ] && KILLCURR="--kill-curriculum $KILL_CURR" || KILLCURR=""
PPO_LR="${PPO_LR:-1e-4}"; EPOCHS="${EPOCHS:-2}"; ATTN_DIM="${ATTN_DIM:-32}"; ATTN_HIDDEN="${ATTN_HIDDEN:-64}"
[ "${FREEZE_ENEMY:-0}" = "1" ] && FREEZE="--freeze-enemy" || FREEZE=""
# NO_AA=1 (default now) ejects enemy anti-air fire — enemies only maneuver. Re-inject: NO_AA=0 ./train.sh
[ "${NO_AA:-1}" = "1" ] && NOAA="--no-aa" || NOAA=""
[ "${KEEP_BEST:-1}" = "1" ] && KEEPBEST="--keep-best" || KEEPBEST=""
OUT="${OUT:-runs}"; RENDER="${RENDER:-$OUT/swarm.mp4}"
INIT_DRONE="${INIT_DRONE:+--init-drone $INIT_DRONE}"; INIT_ENEMY="${INIT_ENEMY:+--init-enemy $INIT_ENEMY}"

echo "device=$DEV n_envs=$N_ENVS D=$DRONES E=$ENEMIES O=$OBST ticks=$TICKS budget=${BUDGET}s ${FREEZE:-coevo}"
"$PY" train_drone.py \
  --device "$DEV" --n-envs "$N_ENVS" --drones "$DRONES" --enemies "$ENEMIES" --obstacles "$OBST" \
  --ticks "$TICKS" --ppo-group "$PPO_GROUP" --enemy-group "$ENEMY_GROUP" --ppo-minibatch "$PPO_MB" \
  --ppo-lr "$PPO_LR" --ppo-epochs "$EPOCHS" --attn-dim "$ATTN_DIM" --attn-hidden "$ATTN_HIDDEN" \
  --budget "$BUDGET" --iters "$ITERS" $ACCEL \
  --enemy-every "$ENEMY_EVERY" --enemy-pool "$ENEMY_POOL" --aa-warmup "$AA_WARMUP" $FREEZE $NOAA $KILLCURR \
  --eval-every "$EVAL_EVERY" --eval-seeds "$EVAL_SEEDS" $KEEPBEST \
  --out-dir "$OUT" --render "$RENDER" $INIT_DRONE $INIT_ENEMY
echo "##### DONE — models $OUT/{drone,enemy}.json ; video $RENDER #####"
