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

if [ "$DEV" = "cuda" ]; then     # 3090: wide batch, bf16 policy, compiled _core (compile also LOWERS peak VRAM
  #                                via inductor buffer reuse -> eager OOMs at N=9216 where compiled fits).
  # enemy_group=2 (not 8): the enemy's PPO rollout buffer is [enemy_group,N,K_dec,..] and BINDS peak memory;
  # with N=9216 scenes the enemy already gets a huge batch, so 2 copies suffice and leave the drone SAPO room.
  N_ENVS="${N_ENVS:-12288}"; ENEMY_GROUP="${ENEMY_GROUP:-2}"   # compiled drone-SAPO peak ~21GB (torch-measured);
  PPO_MB="${PPO_MB:-262144}"; ACCEL="--compile --policy-bf16"
else                             # mac/cpu: small/fast dev loop, fp32
  N_ENVS="${N_ENVS:-32}"; ENEMY_GROUP="${ENEMY_GROUP:-2}"
  PPO_MB="${PPO_MB:-16384}"; ACCEL=""
fi

DRONES="${DRONES:-8}"; ENEMIES="${ENEMIES:-8}"; OBST="${OBST:-16}"; TICKS="${TICKS:-750}"
BUDGET="${BUDGET:-300}"; ITERS="${ITERS:-40000}"
# GEOMETRY: showcase obstacle-course scale (WorldConfig 'design' defaults are much bigger: 60/45/15).
ARENA_HALF="${ARENA_HALF:-30}"; COMBAT_HALF="${COMBAT_HALF:-10}"; CEILING="${CEILING:-10}"
ENGAGE_RANGE="${ENGAGE_RANGE:-8}"; TERRAIN_AMP="${TERRAIN_AMP:-3}"
# DRONE update rule (CANONICAL = sapo): sapo (max-ent analytic diff-sim, single-phase FROM SCRATCH) is the
# default; shac (analytic, needs a warm start) and ppo (score-fn) stay selectable via TRAIN_MODE=. The ENEMY
# always co-evolves via PPO regardless (one-sided diff-physics: two-sided pathwise grads through the shared
# physics oscillate; the enemy plays a frozen league mean with no-grad inside the drone's SAPO window).
TRAIN_MODE="${TRAIN_MODE:-sapo}"; GAMMA="${GAMMA:-0.99}"
# P (rollout copies): sapo/shac use LOW-VARIANCE analytic gradients -> P=1 pours the whole wide batch into
# DISTINCT scenes (N) instead of re-rolling the same scenes; only PPO's score-function estimator wants P>1.
# Memory scales as P*N, so P=1 buys ~4.5x the scene diversity at the SAME VRAM (the real "more room").
case "$TRAIN_MODE" in ppo) PPO_GROUP="${PPO_GROUP:-4}" ;; *) PPO_GROUP="${PPO_GROUP:-1}" ;; esac
SHAC_HORIZON="${SHAC_HORIZON:-6}"; SHAC_LR="${SHAC_LR:-2e-3}"; SHAC_LAMBDA="${SHAC_LAMBDA:-0.95}"; SHAC_TAU="${SHAC_TAU:-0.005}"
SAPO_TE="${SAPO_TE:--2.0}"; SAPO_ALPHA_LR="${SAPO_ALPHA_LR:-3e-3}"; SAPO_ALPHA0="${SAPO_ALPHA0:-0.1}"
EVAL_EVERY="${EVAL_EVERY:-20}"; EVAL_SEEDS="${EVAL_SEEDS:-16}"
ENEMY_EVERY="${ENEMY_EVERY:-4}"; ENEMY_POOL="${ENEMY_POOL:-6}"; AA_WARMUP="${AA_WARMUP:-15}"
# KILL_CURR="3 40" bootstraps kills: kamikaze radius starts 3x, anneals to 1x over 40 iters. Empty = off.
KILL_CURR="${KILL_CURR:-3 40}"; [ -n "$KILL_CURR" ] && KILLCURR="--kill-curriculum $KILL_CURR" || KILLCURR=""
PPO_LR="${PPO_LR:-1e-4}"; EPOCHS="${EPOCHS:-2}"; ATTN_DIM="${ATTN_DIM:-32}"; ATTN_HIDDEN="${ATTN_HIDDEN:-64}"
[ "${FREEZE_ENEMY:-0}" = "1" ] && FREEZE="--freeze-enemy" || FREEZE=""
# NO_AA=1 (default now) ejects enemy anti-air fire — enemies only maneuver. Re-inject: NO_AA=0 ./train.sh
[ "${NO_AA:-1}" = "1" ] && NOAA="--no-aa" || NOAA=""
[ "${KEEP_BEST:-1}" = "1" ] && KEEPBEST="--keep-best" || KEEPBEST=""
OUT="${OUT:-runs}"; RENDER="${RENDER:-$OUT/videos/swarm.mp4}"   # train_drone makes OUT/{models,videos,logs,config}/
INIT_DRONE="${INIT_DRONE:+--init-drone $INIT_DRONE}"; INIT_ENEMY="${INIT_ENEMY:+--init-enemy $INIT_ENEMY}"

echo "device=$DEV n_envs=$N_ENVS D=$DRONES E=$ENEMIES O=$OBST ticks=$TICKS budget=${BUDGET}s ${FREEZE:-coevo}"
"$PY" train_drone.py \
  --device "$DEV" --n-envs "$N_ENVS" --drones "$DRONES" --enemies "$ENEMIES" --obstacles "$OBST" \
  --ticks "$TICKS" --ppo-group "$PPO_GROUP" --enemy-group "$ENEMY_GROUP" --ppo-minibatch "$PPO_MB" \
  --ppo-lr "$PPO_LR" --ppo-epochs "$EPOCHS" --attn-dim "$ATTN_DIM" --attn-hidden "$ATTN_HIDDEN" \
  --budget "$BUDGET" --iters "$ITERS" $ACCEL \
  --train-mode "$TRAIN_MODE" --gamma "$GAMMA" \
  --arena-half "$ARENA_HALF" --combat-half "$COMBAT_HALF" --ceiling "$CEILING" \
  --engage-range "$ENGAGE_RANGE" --terrain-amp "$TERRAIN_AMP" \
  --shac-horizon "$SHAC_HORIZON" --shac-lr "$SHAC_LR" --shac-lambda "$SHAC_LAMBDA" --shac-tau "$SHAC_TAU" \
  --sapo-target-entropy "$SAPO_TE" --sapo-alpha-lr "$SAPO_ALPHA_LR" --sapo-alpha0 "$SAPO_ALPHA0" \
  --enemy-every "$ENEMY_EVERY" --enemy-pool "$ENEMY_POOL" --aa-warmup "$AA_WARMUP" $FREEZE $NOAA $KILLCURR \
  --eval-every "$EVAL_EVERY" --eval-seeds "$EVAL_SEEDS" $KEEPBEST \
  --out-dir "$OUT" --render "$RENDER" $INIT_DRONE $INIT_ENEMY
echo "##### DONE — weights $OUT/models/{drone,enemy}.safetensors ; video $RENDER #####"
