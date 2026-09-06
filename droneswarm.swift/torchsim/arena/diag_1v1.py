# diag_1v1.py — WHY does a lone drone struggle to home the LAST enemy? Isolate the 1-drone-vs-1-enemy endgame
# (open field, no obstacles) and measure whether the drone CLOSES and kills, or ORBITS at a fixed radius. Run
# twice: (A) real ENEMY policy (it evades) vs (B) FROZEN enemy (zero action) -> if the drone kills the frozen
# one but orbits the active one, the problem is that a single kamikaze can't corner an EVADER (the swarm wins by
# numbers), not a targeting bug. Pure diagnostic (offline).
# --- path bootstrap: run from any cwd; expose sibling arena modules + the shared `common` package ---
import os as _bo, sys as _bs                                                        # stdlib only (safe pre-import)
_bs.path.insert(0, _bo.path.dirname(_bo.path.abspath(__file__)))                    # arena/  (env_drone, schedule_drone, ...)
_bs.path.insert(0, _bo.path.dirname(_bo.path.dirname(_bo.path.abspath(__file__))))  # torchsim/  (the `common` package)
import sys, numpy as np, torch
from world_config_drone import WorldConfig
import schedule_drone as S
from env_drone import EnvDrone, game_loop
import policy_recur as RE, policy_attn as AT

DEV = 'cuda' if torch.cuda.is_available() else 'cpu'
NENV = 48
cfg = WorldConfig(); cfg.arena_half = 30; cfg.combat_half = 10; cfg.ceiling = 10; cfg.engage_range = 8; cfg.terrain_amp = 3
sched = S.build_eval(cfg, NENV, D=1, E=1, O=16, T=900, base_seed=303, obstacle_field=[])   # 1v1, open field
env = EnvDrone(sched, device=DEV, cfg=cfg); env.aa_enabled = False
dp, dls, dm = RE.load_safetensors('runs/latest/models/drone.safetensors', device=DEV)
ep, els, em = AT.load_safetensors('runs/latest/models/enemy.safetensors', device=DEV)
env.ctrl_gains = RE.ctrl_gains(dp)                                  # base-controller gains from the model
mode = sys.argv[1] if len(sys.argv) > 1 else 'active'     # 'active' (real enemy) | 'frozen' (zero-action enemy)

def dfn(sf, tk, mk, ef, em, dm, dpxy, h_in):
    mu, _, h_new, a_hard = RE.apply_recur(dp, sf, tk, mk, ef, em, dm, dpxy, h_in, None)
    return mu, h_new, a_hard
def efn_active(sf, tk, mk):
    return AT.apply_attn(ep, sf, tk, mk, None)[0]
def efn_frozen(sf, tk, mk):
    return torch.zeros_like(AT.apply_attn(ep, sf, tk, mk, None)[0])   # zero steering -> non-evasive enemy
efn = efn_frozen if mode == 'frozen' else efn_active

snaps = []
game_loop(env, dfn, efn, 1, 240, record=snaps, record_stride=2, drone_recur=True, latent_h=dm['H'])

dpos = np.stack([s['d_pos'][0] for s in snaps])            # [T,P,1,3]
epos = np.stack([s['e_pos'][0] for s in snaps])            # [T,P,1,2]
ea   = np.stack([s['e_alive'][0] for s in snaps]) > 0.5    # [T,P,1]
dcr  = np.stack([s['d_crash'][0] for s in snaps]) > 0.5    # [T,P,1]
T, P = dpos.shape[0], dpos.shape[1]
dist = np.linalg.norm(dpos[..., 0, :2] - epos[..., 0, :], axis=-1)   # [T,P] horizontal drone->enemy
kill_r = float(cfg.drone_kill_radius)

killed  = ea[0, :, 0] & ~ea[-1, :, 0]                     # enemy alive at start, dead at end
crashed = dcr[-1, :, 0]
mind = dist.min(0)                                        # closest approach per env
# late-phase mean distance (last third) -> a stable orbit radius shows as a flat, nonzero band
late = dist[int(0.66 * T):].mean(0)

print(f"=== 1v1 OPEN, enemy={mode}, {P} envs, {T} ticks, kill_radius={kill_r:.1f} m ===")
print(f"enemy KILLED : {killed.sum():2d}/{P}  ({100*killed.mean():.0f}%)")
print(f"drone CRASHED: {crashed.sum():2d}/{P}")
nk = ~killed
if nk.any():
    print(f"NON-KILL envs ({nk.sum()}):")
    print(f"  closest approach  min/median/mean = {mind[nk].min():.1f}/{np.median(mind[nk]):.1f}/{mind[nk].mean():.1f} m")
    print(f"  late-phase dist   median/mean      = {np.median(late[nk]):.1f}/{late[nk].mean():.1f} m  (flat & >kill_r => ORBIT)")
    print(f"  got within 3*kill_r ({3*kill_r:.1f} m) but never killed : {int((mind[nk] < 3*kill_r).sum())}")
    print(f"  never got closer than 8 m                              : {int((mind[nk] > 8).sum())}")
