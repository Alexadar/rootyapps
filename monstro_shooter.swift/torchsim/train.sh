#!/usr/bin/env bash
# Train player + enemy co-evolution on the surround dataset, then multi-seed eval + a 3x3 grid render.
# Device is AUTO-DETECTED (cuda -> mps -> cpu) and params AUTO-SCALED: big on the 3090, small here.
# Same script, both machines. Override the python via:  PY=/path/python ./train.sh
set -e
cd "$(dirname "$0")"
# PY override > conda env 'fantastic' (the project's known-good deps: torch, coremltools, imageio-ffmpeg
# for --render; base python3 lacks them and the render/export steps error) > python3. No venv — this
# project uses conda 'fantastic' on both machines.
_cbase="${CONDA_EXE:+$(dirname "$(dirname "$CONDA_EXE")")}"
_fant="$_cbase/envs/fantastic/bin/python"
PY="${PY:-$([ -x "$_fant" ] && echo "$_fant" || command -v python3 || command -v python)}"

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
CAP="${CAP:-32}"           # monster slots = max simultaneous monsters a map can have (surround totals <=16)
BULLETS="${BULLETS:-8}"    # bullet ring slots; >= weapon's max simultaneous alive bullets (pistol=2; size up for fast guns)
BUDGET="${BUDGET:-300}"    # wall-time seconds (5 min). NOTE: the keep-out-ring reward is PURE-NEURAL (PPO learns
#   its own monster predictor from discounted return — weaker/longer-horizon than hand-coded), so 5 min may
#   underconverge into a timid player; --keep-best grabs the peak. BUDGET=1800 ./train.sh (30 min) to converge.
EVAL_SEEDS="${EVAL_SEEDS:-3}"   # 3 eval maps x 3 seeds = the 3x3 render grid
EVAL_EVERY="${EVAL_EVERY:-30}"
ITERS="${ITERS:-40000}"
# reward shaping (training-only, parity-safe). RW_HIT = penalty per HP TAKEN — high so the player is
# DAMAGE-AVERSE and learns to dodge/move instead of tanking (was 0.05; 0.30 = 6x). Tune via env if needed.
RW_HIT="${RW_HIT:-0.30}"; RW_KILL="${RW_KILL:-1.0}"; RW_SURVIVE="${RW_SURVIVE:-0.01}"
# KEEP-OUT RING (replaces the old saturating RW_SPACE): penalty per tick per monster inside a personal-space
# circle of RING_RADIUS. Only the CURRENT incursion is penalized -> PPO learns its OWN monster predictor (the
# net sees pos+dir+velocity per monster) and must MOVE to keep the circle clear -> reactive maneuvering + speed.
# RING_RADIUS=90 ~ 2 monster bodies, just outside the ~60u damage line. RW_RING is the main knob to tune.
RW_RING="${RW_RING:-0.03}"; RING_RADIUS="${RING_RADIUS:-90}"
RW_SPACE="${RW_SPACE:-0.0}"; SPACE_KEEP="${SPACE_KEEP:-2}"   # old spacing reward OFF by default (ring replaces it)
RW_AIM="${RW_AIM:-0.05}"   # reward for aiming at the threat (raised 0.005->0.05 so aim tracks the pack, not fixed)
# ECONOMICAL ACTIONS (Stage A, ON): actions cost energy -> learned discipline, no hardcoded limits. RW_EFFORT =
# move cost (still when safe); RW_SHOT = fire cost; RW_DAMAGE = dense per-HP hit reward so a landing shot out-pays
# the shot cost -> "fire only when it'll connect" + trigger discipline emerge. Keep small vs RW_KILL/RW_RING.
RW_EFFORT="${RW_EFFORT:-0.005}"; RW_SHOT="${RW_SHOT:-0.01}"; RW_DAMAGE="${RW_DAMAGE:-0.02}"
# SWARM (enemy-side, ON by default): RW_ALIGN = coherent pack heading; RW_SEPARATE = anti-stacking penalty inside
# SEP_RADIUS (~1 monster body). Disable for a Stage-A-only run with RW_ALIGN=0 RW_SEPARATE=0 sh train.sh
RW_ALIGN="${RW_ALIGN:-0.01}"; RW_SEPARATE="${RW_SEPARATE:-0.02}"; SEP_RADIUS="${SEP_RADIUS:-50}"
# DEFAULT = ATTENTION player (single-query cross-attention over the per-monster SET obs) + PPO. The old MLP
# player saw ONE pre-summed threat vector -> near-fixed move+aim; attention learns per-target weights and acts
# on blend+individuals (surroundings-aware). PPO because gradients can use the richer obs (ES can't scale to it).
# Enemy stays ES (co-evolution). bf16 is safe here: apply_attn casts only the projection matmuls; the masked
# softmax runs fp32 internally. --compile still fuses the env step; the policy forward is eager regardless.
# To fall back to the validated ES/MLP baseline (PPO~ES statistical tie on the fixed-eval; ES simpler/robust):
#   ACCEL="--algo es --compile $POLICY_BF16" ./train.sh
ACCEL="--algo ppo --player-arch attn --ppo-group $PPO_GROUP --ppo-minibatch $PPO_MB --compile $POLICY_BF16"
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
  --rw-ring $RW_RING --ring-radius $RING_RADIUS \
  --rw-effort $RW_EFFORT --rw-shot $RW_SHOT --rw-damage $RW_DAMAGE \
  --rw-align $RW_ALIGN --rw-separate $RW_SEPARATE --sep-radius $SEP_RADIUS \
  --eval --eval-seeds $EVAL_SEEDS --eval-every $EVAL_EVERY --eval-vs scripted --keep-best \
  --render "$DATASET/eval/grid.mp4"
