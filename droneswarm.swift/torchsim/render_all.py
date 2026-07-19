# Rerender ALL showcase scenarios on the current runs/latest model -- every scene a SQUARE arena (a ribbon is
# a corridor the swarm can funnel/flank to CHEAT; squares force honest 2D navigation). One script, rendered
# SEQUENTIALLY (render_torch rasterizes on the GPU -> parallel renders would contend/OOM the single device).
import os, sys, numpy as np, torch, imageio.v3 as iio, time
os.makedirs('runs/latest/videos', exist_ok=True)
from world_config_drone import WorldConfig
import schedule_drone as S
from env_drone import EnvDrone
import policy_recur as RE, policy_attn as AT
import render_drone_torch as RT

OC = S.ObstacleClass
# SQUARE scenarios (arena 30 / combat 10, exactly the training geometry -> in-distribution). obstacle_field=None
# falls back to the DEFAULT (the eval/train distribution). Every field uses region='combat' (fills the central
# square, no x/y bands).
SCEN = {
    "open":   [],                                                                    # bare field: pure swarm vs enemies
    "forest": [OC("tree", "cyl", (7, 9), (0.5, 1.0), (0.5, 1.0), (3.0, 6.0), "combat", 0.9, 3.0)],   # dense trees
    "city":   [OC("building", "box", (4, 6), (1.6, 2.8), (1.6, 2.8), (2.5, 4.5), "combat", 0.85, 5.0)],  # buildings
    "mixed":  [OC("tree", "cyl", (5, 7), (0.5, 1.0), (0.5, 1.0), (3.0, 6.0), "combat", 0.9, 3.5),        # trees +
               OC("building", "box", (3, 4), (1.6, 2.6), (1.6, 2.6), (2.5, 4.0), "combat", 0.9, 5.0)],   #   buildings
    "eval":   None,                                                                  # the DEFAULT train/eval field
}
NENV = 4
cam_kw = dict(back_base=22.0, back_k=0.5, back_hi=60.0, height_base=17.0, height_k=0.42, height_hi=50.0)
dp, dls, dm = RE.load_safetensors('runs/latest/models/drone.safetensors')
ep, els, em = AT.load_safetensors('runs/latest/models/enemy.safetensors')

only = sys.argv[1:] if len(sys.argv) > 1 else list(SCEN)                              # optional subset via argv
for name in only:
    field = SCEN[name]
    cfg = WorldConfig(); cfg.arena_half = 30; cfg.combat_half = 10; cfg.ceiling = 10; cfg.engage_range = 8; cfg.terrain_amp = 3
    sched = S.build_eval(cfg, NENV, D=8, E=8, O=16, T=900, base_seed=303, obstacle_field=field)
    env = EnvDrone(sched, device='cpu', cfg=cfg); env.aa_enabled = False
    out = f'runs/latest/videos/swarm_{name}.mp4'
    t0 = time.time()
    RT.render_torch(env, dp, dls, ep, els, K_dec=240, H=dm['H'], out_path=out,
                    W=900, Hp=520, n_panel=NENV, cols=2, chunk=64, cam_mode='chase', cam_kw=cam_kw, max_seconds=50)
    fr = iio.imread(out, index=None)
    print(f'[{name}] {out}  {fr.shape}  {time.time()-t0:.1f}s')
print('ALL SCENARIOS DONE')
