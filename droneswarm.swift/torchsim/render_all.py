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
# falls back to the DEFAULT (the eval/train distribution). Obstacles spread across the arena (no x/y bands).
SCEN = {
    "open":   [],                                                                    # bare field: pure swarm vs enemies
    "forest": [OC("tree", "cyl", (7, 9), (0.5, 1.0), (0.5, 1.0), (3.0, 6.0), 0.9, 3.0)],   # dense trees
    "city":   [OC("building", "box", (4, 6), (1.6, 2.8), (1.6, 2.8), (2.5, 4.5), 0.85, 5.0)],  # buildings
    "mixed":  [OC("tree", "cyl", (5, 7), (0.5, 1.0), (0.5, 1.0), (3.0, 6.0), 0.9, 3.5),        # trees +
               OC("building", "box", (3, 4), (1.6, 2.6), (1.6, 2.6), (2.5, 4.0), 0.9, 5.0)],   #   buildings
    "eval":   None,                                                                  # the DEFAULT train/eval field
    "dense_forest": [OC("tree", "cyl", (14, 16), (0.4, 0.9), (0.4, 0.9), (3.0, 7.0), 0.85, 1.2)],   # PACKED trees (near O=16 cap, tight min_sep)
    "dense_city":   [OC("building", "box", (9, 12), (1.5, 2.6), (1.5, 2.6), (2.5, 4.5), 0.80, 2.5)],  # PACKED buildings
    "dense_forest4x": [OC("tree", "cyl", (56, 64), (0.4, 0.8), (0.4, 0.8), (3.0, 7.0), 0.9, 0.7)],   # 4x: ~60 trees (needs O=64)
    "dense_city4x":   [OC("building", "box", (40, 48), (1.3, 2.2), (1.3, 2.2), (2.5, 4.5), 0.85, 1.6)],  # 4x: ~44 buildings (needs O=64)
}
DENSE4X_O = 64                                                                        # scenarios ending '4x' need a bigger obstacle cap
NENV = 4
cam_kw = dict(back_base=22.0, back_k=0.5, back_hi=60.0, height_base=17.0, height_k=0.42, height_hi=50.0)
DEV = 'cuda' if torch.cuda.is_available() else 'cpu'   # roll + rasterize on the GPU
dp, dls, dm = RE.load_safetensors('runs/latest/models/drone.safetensors', device=DEV)
ep, els, em = AT.load_safetensors('runs/latest/models/enemy.safetensors', device=DEV)

only = sys.argv[1:] if len(sys.argv) > 1 else list(SCEN)                              # optional subset via argv
for name in only:
    field = SCEN[name]
    cfg = WorldConfig(); cfg.arena_half = 30; cfg.combat_half = 10; cfg.ceiling = 10; cfg.engage_range = 8; cfg.terrain_amp = 3
    O = DENSE4X_O if name.endswith("4x") else 16                                      # bigger obstacle cap for 4x-dense scenes
    sched = S.build_eval(cfg, NENV, D=8, E=8, O=O, T=900, base_seed=303, obstacle_field=field)
    env = EnvDrone(sched, device=DEV, cfg=cfg); env.aa_enabled = False
    env.ctrl_gains = RE.ctrl_gains(dp)                                                    # base-controller gains from the model
    out = f'runs/latest/videos/swarm_{name}.mp4'
    t0 = time.time()
    RT.render_torch(env, dp, dls, ep, els, K_dec=240, H=dm['H'], out_path=out,
                    W=900, Hp=520, n_panel=NENV, cols=2, chunk=64, cam_mode='chase', cam_kw=cam_kw, max_seconds=50)
    fr = iio.imread(out, index=None)
    print(f'[{name}] {out}  {fr.shape}  {time.time()-t0:.1f}s')
print('ALL SCENARIOS DONE')
