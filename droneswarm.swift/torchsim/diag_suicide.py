# diag_suicide.py — WHY do drones "move to a ground and suicide"? Measure, for every drone that earth-hits,
# its HORIZONTAL distance to the nearest LIVE enemy at the crash instant. That single number discriminates the
# competing root causes (no speculation):
#   * dde <= kill_radius          -> crashed ON the enemy: a precision/timing near-miss (warhead didn't trigger).
#   * kill_radius < dde <= commit -> crashed SHORT, inside the commit zone: descended too early (structural:
#                                    commit_radius too wide / ground-brake gated off once "committed").
#   * dde > commit_radius         -> crashed FAR from any enemy: wandering / not actually homing there.
# Also reports the descent profile (agl + vz over the last few ticks before impact) to see if the dive is a
# steep terminal plunge vs a shallow drift into terrain. Pure diagnostic (offline) -> loops are fine here.
import sys, numpy as np, torch
from world_config_drone import WorldConfig
import schedule_drone as S
from env_drone import EnvDrone
import policy_recur as RE, policy_attn as AT
from render_drone import capture

DEV = 'cuda' if torch.cuda.is_available() else 'cpu'
NENV = 16                                                        # more envs -> more crash samples
cfg = WorldConfig(); cfg.arena_half = 30; cfg.combat_half = 10; cfg.ceiling = 10; cfg.engage_range = 8; cfg.terrain_amp = 3
# SAME obstacle fields as render_all.py so the crash geometry matches the rendered videos scenario-for-scenario.
OC = S.ObstacleClass
SCEN = {
    "open":   [],
    "forest": [OC("tree", "cyl", (7, 9), (0.5, 1.0), (0.5, 1.0), (3.0, 6.0), 0.9, 3.0)],
    "city":   [OC("building", "box", (4, 6), (1.6, 2.8), (1.6, 2.8), (2.5, 4.5), 0.85, 5.0)],
    "mixed":  [OC("tree", "cyl", (5, 7), (0.5, 1.0), (0.5, 1.0), (3.0, 6.0), 0.9, 3.5),
               OC("building", "box", (3, 4), (1.6, 2.6), (1.6, 2.6), (2.5, 4.0), 0.9, 5.0)],
    "eval":   None,
}
name = sys.argv[1] if len(sys.argv) > 1 else 'open'
field = SCEN.get(name, [])
sched = S.build_eval(cfg, NENV, D=8, E=8, O=16, T=900, base_seed=303, obstacle_field=field)
env = EnvDrone(sched, device=DEV, cfg=cfg); env.aa_enabled = False
dp, dls, dm = RE.load_safetensors('runs/latest/models/drone.safetensors', device=DEV)
ep, els, em = AT.load_safetensors('runs/latest/models/enemy.safetensors', device=DEV)
snaps = capture(env, dp, dls, ep, els, K_dec=240, H=dm['H'])    # per-tick CPU snapshots (mean-action roll)

kill_r = float(cfg.drone_kill_radius)
commit = float(getattr(env, 'stop_dist', 10.0)); ceiling = float(cfg.ceiling)   # terrain-grace radius (physical stopping dist)
print(f"kill_radius={kill_r:.2f}  commit_radius={commit:.2f}  ceiling={ceiling:.1f}  envs={NENV}  ticks={len(snaps)}")

# stack the per-tick fields into [T,P,...]
dposs = np.stack([s['d_pos'][0] for s in snaps])               # [T,P,D,3]
dcr   = np.stack([s['d_crash'][0] for s in snaps]) > 0.5        # [T,P,D] sticky crash flag
epos  = np.stack([s['e_pos'][0] for s in snaps])               # [T,P,E,2]
ealive= np.stack([s['e_alive'][0] for s in snaps]) > 0.5       # [T,P,E]
oxyz  = np.stack([s['obst_xyz'] for s in snaps]) if 'obst_xyz' in snaps[0] else None   # [T,P,O,3] (obst_xyz is [P,O,3])
ohalf = env.obst_half.detach().cpu().numpy()                   # [P,O,3] obstacle half-extents (static)
omask = env.obst_mask.detach().cpu().numpy() > 0.5             # [P,O] active obstacle
orad  = np.maximum(ohalf[..., 0], ohalf[..., 1])               # [P,O] horizontal "radius" proxy
T, P, D, _ = dposs.shape

# --- per-drone SPAWN geometry (tests the "drones spawn near enemies in training -> far spawns diverge"
#     hypothesis): each drone's launch xy = base_pos + spawn_off, its distance to the nearest LIVE enemy at
#     t=0, and whether it EVER crashed. Binning the crash rate by spawn distance shows if far launches suicide. ---
base_pos = env.base_pos.detach().cpu().numpy()                 # [P,3] per-env launch point
spawn_off = env.spawn_off.detach().cpu().numpy()               # [P,D,3] per-drone launch offset
spawn_xy = base_pos[:, None, :2] + spawn_off[:, :, :2]         # [P,D,2] each drone's launch xy
e0 = epos[0]; ea0 = ealive[0]                                  # enemy pos/alive at t=0
launch_r = np.linalg.norm(base_pos[:, :2], axis=-1)            # [P] env launch radius from centre

dde_at_crash = []; agl_at_crash = []; oclr_at_crash = []; short=onenemy=far=0; near_obst=0
spawn_d2e = np.full((P, D), np.nan); crashed = np.zeros((P, D), bool)
for p in range(P):
    de0 = np.linalg.norm(e0[p][None, :, :] - spawn_xy[p][:, None, :], axis=-1)   # [D,E] spawn->enemy dist
    de0 = np.where(ea0[p][None, :], de0, np.inf)
    spawn_d2e[p] = de0.min(1)                                                    # [D] nearest enemy at spawn
    for d in range(D):
        onset = np.argmax(dcr[:, p, d]) if dcr[:, p, d].any() else -1   # first tick the crash flag flips on
        if onset <= 0:
            continue
        crashed[p, d] = True
        t = onset
        dxy = dposs[t, p, d, :2]                                        # drone xy at crash
        live = ealive[t, p]                                            # [E] live enemies this tick
        if not live.any():
            continue
        de = np.linalg.norm(epos[t, p] - dxy[None, :], axis=-1)         # [E] horiz dist to each enemy
        de = np.where(live, de, np.inf)
        dd = float(de.min())                                          # nearest LIVE enemy
        dde_at_crash.append(dd)
        agl_at_crash.append(float(dposs[t, p, d, 2]))                  # drone z at crash (>terrain => hit an obstacle)
        if dd <= kill_r: onenemy += 1
        elif dd <= commit: short += 1
        else: far += 1
        # obstacle clearance at crash: signed dist to nearest active obstacle EDGE (<~1.5 m => clipping cover)
        if oxyz is not None and omask[p].any():
            od = np.linalg.norm(oxyz[t, p, :, :2] - dxy[None, :], axis=-1) - orad[p]   # [O] edge clearance
            od = np.where(omask[p], od, np.inf)
            oclr_at_crash.append(float(od.min()))
            if od.min() < 1.5: near_obst += 1

n = len(dde_at_crash)
if n == 0:
    print("NO crashes captured (drones didn't earth-hit in this rollout).")
else:
    a = np.array(dde_at_crash)
    print(f"\ncrashed drones sampled: {n}")
    print(f"  ON enemy   (dde<= {kill_r:.1f})            : {onenemy:3d}  ({100*onenemy/n:.0f}%)  <- precision/timing near-miss")
    print(f"  SHORT      ({kill_r:.1f}<dde<= {commit:.1f})     : {short:3d}  ({100*short/n:.0f}%)  <- early descent / commit too wide")
    print(f"  FAR        (dde> {commit:.1f})             : {far:3d}  ({100*far/n:.0f}%)  <- wandering / not homing there")
    print(f"  dde-to-nearest-enemy  min/median/mean/max = {a.min():.2f}/{np.median(a):.2f}/{a.mean():.2f}/{a.max():.2f} m")
    print(f"  drone z at crash      median/mean         = {np.median(agl_at_crash):.2f}/{np.mean(agl_at_crash):.2f} m")
    if oclr_at_crash:
        print(f"  OBSTACLE-CLIP (edge-clr< 1.5 m)         : {near_obst:3d}  ({100*near_obst/n:.0f}%)  <- hit a tree/building")

# --- SPAWN-DISTANCE vs SUICIDE (the hypothesis test) ---
print(f"\nlaunch radius from centre (per env): min/median/max = {launch_r.min():.1f}/{np.median(launch_r):.1f}/{launch_r.max():.1f} m  (train+eval range 5-27)")
print("crash rate BINNED by spawn->nearest-enemy distance:")
bins = [(0, 8), (8, 14), (14, 20), (20, 999)]
sd = spawn_d2e.reshape(-1); cr = crashed.reshape(-1)
for lo, hi in bins:
    m = (sd >= lo) & (sd < hi)
    tot = int(m.sum()); crs = int(cr[m].sum())
    rate = f"{100*crs/tot:.0f}%" if tot else "  -"
    print(f"  spawn {lo:2d}-{hi if hi<999 else '+ ':>2} m : {crs:3d}/{tot:3d} crashed  ({rate})")
# correlation: mean spawn distance of crashers vs survivors
if crashed.any() and (~crashed).any():
    print(f"  mean spawn->enemy dist: CRASHERS {np.nanmean(sd[cr]):.1f} m  vs  SURVIVORS {np.nanmean(sd[~cr]):.1f} m")
