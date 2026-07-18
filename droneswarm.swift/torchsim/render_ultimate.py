# Ultimate-game showcase: drones launch in an open FIELD (left), weave a TREE belt (middle),
# and engage enemies among BUILDINGS (right). Instance of the general field with band regions.
import sys, numpy as np, torch, imageio.v3 as iio, time
FR = sys.argv[1]
from world_config_drone import WorldConfig
import schedule_drone as S
from env_drone import EnvDrone
import policy_recur as RE, policy_attn as AT
import render_drone as R, render_drone_torch as RT

cfg = WorldConfig(); cfg.arena_half = 42; cfg.combat_half = 12; cfg.ceiling = 10; cfg.engage_range = 8; cfg.terrain_amp = 3
NENV = 4
# sparser, weavable tree belt (gaps) + a spaced building cluster
field = [
    S.ObstacleClass("tree",     "cyl", (3, 4), (0.5, 1.0), (0.5, 1.0), (3.0, 6.0), "arena", 1.0, 4.0, xr=(-6.0, 6.0),  yr=(-13.0, 13.0)),
    S.ObstacleClass("building", "box", (3, 4), (1.6, 2.6), (1.6, 2.6), (2.5, 4.0), "arena", 1.0, 5.0, xr=(22.0, 36.0), yr=(-9.0, 9.0)),
]
sched = S.build_eval(cfg, NENV, D=8, E=8, O=16, T=900, base_seed=303, obstacle_field=field)
rng = np.random.default_rng(2)
ep0 = sched['e_pos0'].copy()
for e in range(NENV):
    ep0[e, :, 0] = rng.uniform(24.0, 36.0, 8); ep0[e, :, 1] = rng.uniform(-8.0, 8.0, 8)   # enemies among buildings
sched['e_pos0'] = ep0.astype(np.float32)
bp = sched['base_pos'].copy(); so = sched['spawn_off'].copy(); yl = np.linspace(-6, 6, 8)
for e in range(NENV):
    bp[e, 0] = -28.0; bp[e, 1] = 0.0                                                        # launch from the field
    bp[e, 2] = float(R._bilerp_np(sched['hf'][e], np.array([-28.0]), np.array([0.0]), cfg.arena_half)[0]) + 5.
    so[e, :, 0] = 0.0; so[e, :, 1] = yl; so[e, :, 2] = 0.0
sched['base_pos'] = bp.astype(np.float32); sched['spawn_off'] = so.astype(np.float32)

env = EnvDrone(sched, device='cpu', cfg=cfg); env.aa_enabled = False
dp, dls, dm = RE.from_json('runs/latest/drone.json'); ep, els, em = AT.from_json('runs/latest/enemy.json')
env.cfg.combat_half = 0.0
# pull the chase cam back + up so buildings don't overwhelm and the field->trees->buildings progression reads
cam_kw = dict(back_base=20.0, back_k=0.55, back_hi=62.0, height_base=15.0, height_k=0.42, height_hi=48.0)
t0 = time.time()
RT.render_torch(env, dp, dls, ep, els, K_dec=240, H=dm['H'], out_path='runs/latest/swarm_ultimate.mp4',
                W=900, Hp=520, n_panel=NENV, cols=2, chunk=64, cam_mode='chase', cam_kw=cam_kw, max_seconds=60)
fr = iio.imread('runs/latest/swarm_ultimate.mp4', index=None)
print('ULTIMATE %s in %.1fs' % (str(fr.shape), time.time() - t0))
for tag, idx in [('a', min(30, fr.shape[0]-1)), ('b', fr.shape[0]//3), ('c', 2*fr.shape[0]//3), ('d', fr.shape[0]-14)]:
    iio.imwrite(f'{FR}/ult_{tag}.png', fr[idx])
print('wrote frames')
