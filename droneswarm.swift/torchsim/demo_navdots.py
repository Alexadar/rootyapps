# Demo: visualize the SUPERVISOR field on CPU (no GPU needed, arbitrary model). Renders the quantized
# allowed-state DOTS (red=forbidden, green=allowed), the SOLID-GREEN flow path, and the ORANGE actual
# drone trajectory -- so you can see the calculated flow field + a drone moving through it.
import sys, time, numpy as np, torch
import schedule_drone as S
from schedule_drone import ObstacleClass as OC
from env_drone import EnvDrone
import policy_recur as RE, policy_attn as AT
import render_drone_torch as RT
from world_config_drone import WorldConfig

DEV = "cuda" if torch.cuda.is_available() else "cpu"               # GPU (tiny footprint -> fits the ~1.8GB free)
SC = sys.argv[1] if len(sys.argv) > 1 else "runs/latest/models"    # model dir (arbitrary; only the field matters)
OUT = sys.argv[2] if len(sys.argv) > 2 else "runs/latest/videos/demo_navdots.mp4"
cfg = WorldConfig(); cfg.arena_half = 30; cfg.combat_half = 10; cfg.ceiling = 10; cfg.engage_range = 8; cfg.terrain_amp = 3
NENV, D, E, O, T = 1, 8, 8, 16, 420                                 # 1 panel (VRAM-light), short clip
field = [OC("building", "box", (4, 6), (1.6, 2.8), (1.6, 2.8), (2.5, 4.5), 0.85, 5.0)]   # CITY: buildings show red obstacle dots best
env = EnvDrone(S.build_eval(cfg, NENV, D, E, O, T, base_seed=7), device=DEV, cfg=cfg); env.aa_enabled = False
dp, dls, dm = RE.load_safetensors(f"{SC}/drone.safetensors", device=DEV)
ep, els, em = AT.load_safetensors(f"{SC}/enemy.safetensors", device=DEV)
env.ctrl_gains = RE.ctrl_gains(dp)                                  # base-controller gains from the model
t0 = time.time()
RT.render_torch(env, dp, dls, ep, els, K_dec=T // cfg.act_every, H=dm["H"], out_path=OUT,
                W=720, Hp=440, n_panel=NENV, cols=1, chunk=24, cam_mode="chase",
                cam_kw=dict(back_base=22.0, back_k=0.5, back_hi=60.0, height_base=17.0, height_k=0.42, height_hi=50.0),
                max_seconds=9.0, show_nav=True)
print(f"[demo] wrote {OUT} in {time.time()-t0:.1f}s")
