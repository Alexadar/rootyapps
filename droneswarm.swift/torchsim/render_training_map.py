# render_training_map.py — render the model on the ACTUAL TRAINING distribution (schedule.build, NOT build_eval),
# so we can SEE what the swarm trained on. build() draws TRAINING seeds (base_seed+e) with obstacle_field=None ->
# DEFAULT_OBSTACLE_FIELD (up to 6 buildings + 10 trees, spread across the arena). Obstacle PLACEMENT is now the
# same for train and eval (arena spread), so the training map differs from render_all's scenarios only by seeds.
import os, sys, torch, imageio.v3 as iio, time
os.makedirs('runs/latest/videos', exist_ok=True)
from world_config_drone import WorldConfig
import schedule_drone as S
from env_drone import EnvDrone
import policy_recur as RE, policy_attn as AT
import render_drone_torch as RT

cfg = WorldConfig(); cfg.arena_half = 30; cfg.combat_half = 10; cfg.ceiling = 10; cfg.engage_range = 8; cfg.terrain_amp = 3
NENV = 4
base_seed = int(sys.argv[1]) if len(sys.argv) > 1 else 0        # TRAINING seeds (build uses base_seed+e), default 0..3
# build() = the TRAINING schedule (obstacle_field=None -> DEFAULT_OBSTACLE_FIELD, arena-wide dense DR).
sched = S.build(cfg, NENV, D=8, E=8, O=16, T=900, base_seed=base_seed)

DEV = 'cuda' if torch.cuda.is_available() else 'cpu'
env = EnvDrone(sched, device=DEV, cfg=cfg); env.aa_enabled = False
dp, dls, dm = RE.load_safetensors('runs/latest/models/drone.safetensors', device=DEV)
ep, els, em = AT.load_safetensors('runs/latest/models/enemy.safetensors', device=DEV)
env.ctrl_gains = RE.ctrl_gains(dp)                                  # base-controller gains from the model (else flies at init defaults)
cam_kw = dict(back_base=22.0, back_k=0.5, back_hi=60.0, height_base=17.0, height_k=0.42, height_hi=50.0)
out = 'runs/latest/videos/swarm_training_map.mp4'
t0 = time.time()
RT.render_torch(env, dp, dls, ep, els, K_dec=240, H=dm['H'], out_path=out,
                W=900, Hp=520, n_panel=NENV, cols=2, chunk=64, cam_mode='chase', cam_kw=cam_kw, max_seconds=50)
fr = iio.imread(out, index=None)
print(f'[training_map] {out}  {fr.shape}  {time.time()-t0:.1f}s  (seeds {base_seed}..{base_seed+NENV-1})')
