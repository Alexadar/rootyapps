"""JAX port of env_torch — the SAME [P,N,M,B] game program, but the whole rollout is one `lax.scan`
(zero Python per-tick) wrapped in `jax.jit`, so XLA fuses the entire episode into a single GPU program.
This is the structural speedup the torch loop can't get (no per-tick dispatch at all). Parity-faithful:
same det_rand spread, same WorldConfig constants, same step order as env_torch.step.

Pure functional (no torch). Takes numpy schedule arrays + {W,b} weight lists + a WorldConfig-like cfg.
Run the bench/parity harness in bench_jax.py. On the 3090: `pip install -U "jax[cuda12]"`.
"""
import numpy as np
import jax
import jax.numpy as jnp
from jax import lax
from functools import partial


# ---- per-tick tables (precomputed once; the xs that lax.scan iterates) -------------------------------
def make_tables(cfg, sched, ticks):
    K, B = int(sched["bullets_per_shot"]), int(sched["B"])
    fi, ci = int(sched["fire_interval"]), int(sched["contact_interval"])
    t_arr = np.arange(1, ticks + 1, dtype=np.int64)
    ks = np.arange(K, dtype=np.int64)
    h = (t_arr[:, None] * 2654435761 + ks[None, :] * 340573 + 12345) & 0xffffffff   # det_rand(t,k)
    dr = h / 2147483647.5 - 1.0
    theta = np.arctan2(float(sched["max_dev"]) * dr, 500.0)
    slots = ((t_arr // fi)[:, None] * K + ks[None, :]) % B
    oh = np.zeros((ticks, K, B), np.float32)
    oh[np.arange(ticks)[:, None], np.arange(K)[None, :], slots] = 1.0
    return dict(
        elapsed=jnp.asarray((t_arr * cfg.dt).astype(np.float32)),                 # [T]
        gate_fire=jnp.asarray((t_arr % fi == 0).astype(np.float32)),              # [T]
        gate_contact=jnp.asarray((t_arr % ci == 0).astype(np.float32)),           # [T]
        ct=jnp.asarray(np.cos(theta).astype(np.float32)),                         # [T,K]
        st=jnp.asarray(np.sin(theta).astype(np.float32)),                         # [T,K]
        onehot=jnp.asarray(oh))                                                   # [T,K,B]


def reset(cfg, sched, P):
    N, M, B = int(sched["N"]), int(sched["M"]), int(sched["B"])
    z = lambda *s: jnp.zeros(s, jnp.float32)
    return dict(
        player_pos=z(P, N, 2), player_hp=jnp.full((P, N), cfg.player_max_hp, jnp.float32),
        mon_pos=z(P, N, M, 2), mon_vel=z(P, N, M, 2),
        mon_hp=jnp.broadcast_to(sched["hp0"][None], (P, N, M)).astype(jnp.float32),
        mon_act=z(P, N, M), mon_contact=z(P, N, M),
        bul_pos=z(P, N, B, 2), bul_vel=z(P, N, B, 2), bul_alive=z(P, N, B), bul_dist=z(P, N, B), bul_pen=z(P, N, B),
        ammo=jnp.full((P, N), float(sched["mag_size"]), jnp.float32), reload_t=z(P, N), kills=z(P, N))


def apply_mlp(params, x):
    h = x
    for i, (W, b) in enumerate(params):
        h = jnp.matmul(h, W) + b                                    # batched over leading dims (incl. P)
        if i < len(params) - 1:
            h = jnp.maximum(h, 0.0)
    return h


def apply_enemy(params, obs):                                       # obs [P,N,M,in]
    W0 = params[0][0]
    if W0.ndim == 2:
        return apply_mlp(params, obs)
    Pn, N, M, inp = obs.shape
    return apply_mlp(params, obs.reshape(Pn, N * M, inp)).reshape(Pn, N, M, -1)


def player_obs(cfg, sched, s):
    eps = cfg.eps
    rel = s["mon_pos"] - s["player_pos"][:, :, None, :]
    dist = jnp.sqrt((rel * rel).sum(-1)) + eps
    alive = ((s["mon_act"] > 0.5) & (s["mon_hp"] > 0)).astype(jnp.float32)
    cnt = alive.sum(-1)
    dirv = rel / dist[..., None]
    threat = (dirv * alive[..., None]).sum(2)
    threatN = threat / (jnp.sqrt((threat * threat).sum(-1, keepdims=True)) + eps)
    masked = jnp.where(alive > 0.5, dist, 1e9)
    nearest = masked.min(-1)
    meanD = (dist * alive).sum(-1) / (cnt + eps)
    wall = s["player_pos"] / sched["map_half"].reshape(1, -1, 1)
    return jnp.concatenate([(s["player_hp"] / cfg.player_max_hp)[..., None], (cnt / cfg.monster_count_norm)[..., None],
                            threatN, (nearest / cfg.dist_norm)[..., None], (meanD / cfg.dist_norm)[..., None], wall], -1)


def enemy_obs(cfg, sched, s):
    eps = cfg.eps
    rel = s["player_pos"][:, :, None, :] - s["mon_pos"]
    dist = jnp.sqrt((rel * rel).sum(-1)) + eps
    dirv = rel / dist[..., None]
    spd = sched["mon_speed"][None]
    vel_n = s["mon_vel"] / (spd[..., None] + eps)
    brel = s["bul_pos"][:, :, None, :, :] - s["mon_pos"][:, :, :, None, :]        # [P,N,M,B,2]
    bd2 = (brel * brel).sum(-1)
    bd2 = jnp.where(s["bul_alive"][:, :, None, :] > 0.5, bd2, 1e18)
    bmin = bd2.min(-1)
    bidx = bd2.argmin(-1)
    has = (bmin < 1e17).astype(jnp.float32)
    idx = jnp.broadcast_to(bidx[..., None, None], bidx.shape + (1, 2))
    bnear = jnp.take_along_axis(brel, idx, axis=3).squeeze(3)
    bdist = jnp.sqrt(jnp.maximum(bmin, 0.0)) + eps
    bdir = bnear / bdist[..., None] * has[..., None]
    bdist_n = jnp.where(has > 0.5, jnp.minimum(bdist / cfg.bullet_norm, 2.0), 2.0)
    return jnp.concatenate([dirv, (dist / cfg.dist_norm)[..., None], vel_n,
                            jnp.broadcast_to((spd / cfg.monster_speed_norm)[..., None], dist[..., None].shape),
                            (s["mon_hp"] / (sched["hp0"][None] + eps))[..., None],
                            bdir, bdist_n[..., None]], -1)


def step(cfg, sched, player_params, enemy_params, s, xs):
    elapsed, gate_fire, gate_contact = xs["elapsed"], xs["gate_fire"], xs["gate_contact"]
    pct, pst, onehot = xs["ct"], xs["st"], xs["onehot"]            # lax.scan slices the tables dict
    eps, dt = cfg.eps, cfg.dt
    a_player = apply_mlp(player_params, player_obs(cfg, sched, s))
    a_move, a_aim = a_player[..., 0:2], a_player[..., 2:4]

    st = sched["spawn_tick"][None]                                  # [1,N,M]
    due = st <= elapsed
    just = due & (s["mon_act"] < 0.5)
    mon_pos = jnp.where(just[..., None], s["player_pos"][:, :, None, :] + sched["offset"][None], s["mon_pos"])
    mon_act = jnp.maximum(s["mon_act"], just.astype(jnp.float32))
    alive_b = due & (s["mon_hp"] > 0)

    rel = s["player_pos"][:, :, None, :] - mon_pos
    dist = jnp.sqrt((rel * rel).sum(-1)) + eps
    spd = sched["mon_speed"][None]
    stop = cfg.player_radius + sched["mon_boxW"][None] / 2
    move_mask = (alive_b & (dist > stop)).astype(jnp.float32)
    s2 = dict(s); s2["mon_pos"] = mon_pos
    a_e = apply_enemy(enemy_params, enemy_obs(cfg, sched, s2))
    v = jnp.tanh(a_e)
    vn = v / (jnp.sqrt((v * v).sum(-1, keepdims=True)) + eps)
    mon_vel = vn * spd[..., None] * move_mask[..., None]
    mon_pos = mon_pos + mon_vel * dt

    reload_t = jnp.maximum(s["reload_t"] - 1.0, 0.0)
    just_reloaded = (s["reload_t"] > 0) & (reload_t == 0)
    ammo = jnp.where(just_reloaded, float(sched["mag_size"]), s["ammo"])
    fire = ((gate_fire > 0.5) & (ammo > 0) & (reload_t == 0)).astype(jnp.float32)
    ammo = ammo - fire
    need_reload = (ammo <= 0) & (reload_t == 0)
    reload_t = jnp.where(need_reload, float(sched["reload_ticks"]), reload_t)

    aim = a_aim / (jnp.sqrt((a_aim * a_aim).sum(-1, keepdims=True)) + eps)
    aimx, aimy = aim[..., 0:1], aim[..., 1:2]
    pa = jnp.stack([aimx * pct - aimy * pst, aimx * pst + aimy * pct], -1)        # [P,N,K,2]
    vel_k = pa * float(sched["bullet_speed"])
    write_b = jnp.minimum(onehot.sum(0), 1.0)                                  # [B]
    vel_b = jnp.einsum("kb,pnkc->pnbc", onehot, vel_k)
    writeB = write_b[None, None, :] * fire[:, :, None]
    w1 = writeB[..., None]
    bul_pos = jnp.where(w1 > 0.5, s["player_pos"][:, :, None, :], s["bul_pos"])
    bul_vel = jnp.where(w1 > 0.5, vel_b, s["bul_vel"])
    bul_alive = jnp.where(writeB > 0.5, 1.0, s["bul_alive"])
    bul_dist = jnp.where(writeB > 0.5, 0.0, s["bul_dist"])
    bul_pen = jnp.where(writeB > 0.5, float(sched["penetration"]), s["bul_pen"])

    bul_pos = bul_pos + bul_vel * dt
    bul_dist = bul_dist + jnp.sqrt((bul_vel * bul_vel).sum(-1)) * dt
    bul_alive = ((bul_alive > 0.5) & (bul_dist < float(sched["bullet_range"]))).astype(jnp.float32)

    diff = bul_pos[:, :, :, None, :] - mon_pos[:, :, None, :, :]                  # [P,N,B,M,2]
    d2 = (diff * diff).sum(-1)
    hitR = cfg.bullet_radius + sched["mon_boxW"][None] / 2
    hit = ((d2 < (hitR * hitR)[:, :, None, :]) & (bul_alive > 0.5)[..., None] & alive_b[:, :, None, :]).astype(jnp.float32)
    mon_hp = s["mon_hp"] - (hit * float(sched["bullet_damage"])).sum(2)
    bul_pen = bul_pen - hit.sum(3)
    bul_alive = ((bul_alive > 0.5) & (bul_pen > 0.5)).astype(jnp.float32)

    alive_a = due & (mon_hp > 0)
    killed = (alive_b & (~alive_a)).astype(jnp.float32).sum(2)
    kills = s["kills"] + killed

    contact_now = (alive_a & (dist < (cfg.player_radius + sched["mon_boxW"][None] / 2 + cfg.buffer))).astype(jnp.float32)
    newly = contact_now * (1.0 - s["mon_contact"])
    sustained = contact_now * s["mon_contact"]
    dmg = ((newly + sustained * gate_contact) * sched["mon_dmg"][None]).sum(2)
    applied = jnp.where(dmg > 0, jnp.maximum(dmg - float(sched["defense"]), cfg.defense_min_floor), 0.0)
    player_hp = s["player_hp"] - applied
    mon_contact = contact_now

    mv = jnp.tanh(a_move)
    lo = (-sched["map_half"] + cfg.player_half).reshape(1, -1, 1)
    hi = (sched["map_half"] - cfg.player_half).reshape(1, -1, 1)
    player_pos = jnp.minimum(jnp.maximum(
        s["player_pos"] + mv * (cfg.player_speed * float(sched["exo_speed"]) * dt), lo), hi)

    threat_raw = ((mon_pos - player_pos[:, :, None, :]) * alive_a.astype(jnp.float32)[..., None]).sum(2)
    threatN = threat_raw / (jnp.sqrt((threat_raw * threat_raw).sum(-1, keepdims=True)) + eps)
    aim_align = (aim * threatN).sum(-1)
    alive_env = (player_hp > 0).astype(jnp.float32)
    r_player = (0.01 + 0.005 * aim_align + killed - applied * 0.05) * alive_env
    approach = (jnp.maximum(1.0 - dist / 3000.0, 0.0) * alive_a.astype(jnp.float32)).sum(2)
    r_enemy = 0.1 * applied + 0.0008 * approach - 0.02 * killed

    ns = dict(player_pos=player_pos, player_hp=player_hp, mon_pos=mon_pos, mon_vel=mon_vel,
              mon_hp=mon_hp, mon_act=mon_act, mon_contact=mon_contact,
              bul_pos=bul_pos, bul_vel=bul_vel, bul_alive=bul_alive, bul_dist=bul_dist, bul_pen=bul_pen,
              ammo=ammo, reload_t=reload_t, kills=kills)
    return ns, (r_player, r_enemy)


def make_rollout(P, cfg, sched, tables):
    """Return a jitted rollout f(player_params, enemy_params) -> (reward_player[P,N], reward_enemy[P,N],
    kills[P,N], hp[P,N]). cfg/sched/tables are CLOSED OVER (baked as constants), so jit only traces the
    net params — the only thing that varies across ES members. The whole episode is one lax.scan: zero
    Python per-tick, one fused XLA program."""
    @jax.jit
    def f(player_params, enemy_params):
        s0 = reset(cfg, sched, P)
        body = partial(step, cfg, sched, player_params, enemy_params)
        s, (rps, res) = lax.scan(body, s0, tables)
        return rps.sum(0), res.sum(0), s["kills"], s["player_hp"]
    return f
