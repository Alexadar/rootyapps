# Ultimate-game showcase (SQUARE arena, NOT a ribbon): the swarm launches and sweeps a SQUARE combat field
# packed with mixed cover (trees + buildings) to hunt enemies dug in among them. A square forces genuine 2D
# navigation -- a long ribbon is a corridor the swarm can funnel down / flank around to CHEAT the geometry,
# so we render on the same square the policy was trained on (fully in-distribution -> honest performance).
# --- path bootstrap: run from any cwd; expose sibling arena modules + the shared `common` package ---
import os as _bo, sys as _bs                                                        # stdlib only (safe pre-import)
_bs.path.insert(0, _bo.path.dirname(_bo.path.abspath(__file__)))                    # arena/  (env_drone, schedule_drone, ...)
_bs.path.insert(0, _bo.path.dirname(_bo.path.dirname(_bo.path.abspath(__file__))))  # torchsim/  (the `common` package)
import os, sys, numpy as np, torch, imageio.v3 as iio, time
os.makedirs('runs/latest/videos', exist_ok=True)
FR = sys.argv[1]
from world_config_drone import WorldConfig
import schedule_drone as S
from env_drone import EnvDrone
import policy_recur as RE, policy_attn as AT
import render_drone as R, render_drone_torch as RT

# EXACT training geometry -> in-distribution (arena 30 / combat 10 / ceiling 10 / engage 8 / terrain 3).
cfg = WorldConfig(); cfg.arena_half = 30; cfg.combat_half = 10; cfg.ceiling = 10; cfg.engage_range = 8; cfg.terrain_amp = 3
NENV = 4
# SQUARE cover field: trees + buildings spread across the arena (
# no x/y bands). Up to 7 trees + 4 buildings <= O=16 capacity, rejection-spaced so no concave traps.
field = [
    S.ObstacleClass("tree",     "cyl", (5, 7), (0.5, 1.0), (0.5, 1.0), (3.0, 6.0), 0.9, 3.5),
    S.ObstacleClass("building", "box", (3, 4), (1.6, 2.6), (1.6, 2.6), (2.5, 4.0), 0.9, 5.0),
]
# build_eval already places enemies in the central combat square and randomizes the launch ring around it
# (spawn-distance DR) -> a square engagement with 2D freedom. No hand-placed bands (that was the ribbon).
sched = S.build_eval(cfg, NENV, D=8, E=8, O=16, T=900, base_seed=303, obstacle_field=field)

DEV = 'cuda' if torch.cuda.is_available() else 'cpu'   # roll + rasterize on the GPU
env = EnvDrone(sched, device=DEV, cfg=cfg); env.aa_enabled = False
dp, dls, dm = RE.load_safetensors('runs/latest/models/drone.safetensors', device=DEV); ep, els, em = AT.load_safetensors('runs/latest/models/enemy.safetensors', device=DEV)
env.ctrl_gains = RE.ctrl_gains(dp)                                  # base-controller gains from the model (else flies at init defaults)
# chase cam pulled back + up so the whole square board (cover + converging swarm + enemies) reads at once
cam_kw = dict(back_base=22.0, back_k=0.5, back_hi=60.0, height_base=17.0, height_k=0.42, height_hi=50.0)
t0 = time.time()
RT.render_torch(env, dp, dls, ep, els, K_dec=240, H=dm['H'], out_path='runs/latest/videos/swarm_ultimate.mp4',
                W=900, Hp=520, n_panel=NENV, cols=2, chunk=64, cam_mode='chase', cam_kw=cam_kw, max_seconds=60)
fr = iio.imread('runs/latest/videos/swarm_ultimate.mp4', index=None)
print('ULTIMATE %s in %.1fs' % (str(fr.shape), time.time() - t0))
for tag, idx in [('a', min(30, fr.shape[0]-1)), ('b', fr.shape[0]//3), ('c', 2*fr.shape[0]//3), ('d', fr.shape[0]-14)]:
    iio.imwrite(f'{FR}/ult_{tag}.png', fr[idx])
print('wrote frames')
