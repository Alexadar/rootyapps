"""Parity + throughput harness for the JAX rollout (env_jax) vs the torch rollout (env_torch).
Runs the SAME schedule + model weights through both engines. Parity at P=1 must match bit-for-bit;
throughput is timed at a representative population. NOTE: on this Mac it times CPU JAX vs MPS/CPU torch
(not apples-to-apples) — the real comparison is on the 3090: `pip install -U "jax[cuda12]"` then rerun.
"""
import sys, time, statistics as st; sys.path.insert(0, ".")
import numpy as np, torch
import data, schedule, policy_torch as P
from env_torch import EnvTorch
from world_config import WorldConfig
from types import SimpleNamespace
import jax, jax.numpy as jnp, env_jax


def build():
    gd = data.GameData("../monstro_client")
    lv = data.sim_level(data.load_map("datasets/surround/eval/e1.json"))
    cfg = WorldConfig(); B = 24
    sched = schedule.build(lv, gd.monsters, base_seed=123, n_envs=8, cap=16)
    weapon = gd.weapons.get(1) or next(iter(gd.weapons.values()))
    exo = gd.exoskeletons.get(1) or next(iter(gd.exoskeletons.values()))
    env = EnvTorch(sched, weapon, exo, device="cpu", bullets=B, cfg=cfg)
    pl, _ = P.from_json("../MonstroSim/models/player.json", "cpu")
    en, _ = P.from_json("../MonstroSim/models/monster.json", "cpu")
    a = lambda x: jnp.asarray(x.detach().cpu().numpy())
    sj = dict(N=env.N, M=env.M, B=B, spawn_tick=a(env.spawn_tick), offset=a(env.offset), mon_speed=a(env.mon_speed),
              mon_boxW=a(env.mon_boxW), mon_dmg=a(env.mon_dmg), mon_direct=a(env.mon_direct), hp0=a(env.hp0),
              map_half=a(env.map_half), bullet_speed=env.bullet_speed, bullet_damage=env.bullet_damage,
              bullet_range=env.bullet_range, fire_interval=env.fire_interval, contact_interval=env.contact_interval,
              defense=env.defense, bullets_per_shot=env.bullets_per_shot, penetration=env.penetration,
              mag_size=env.mag_size, reload_ticks=env.reload_ticks, max_dev=env.max_dev, exo_speed=env.exo_speed)
    cj = SimpleNamespace(dt=cfg.dt, player_speed=cfg.player_speed, player_half=cfg.player_half,
                         player_radius=cfg.player_radius, buffer=cfg.buffer, bullet_radius=cfg.bullet_radius,
                         eps=cfg.eps, defense_min_floor=cfg.defense_min_floor, player_max_hp=cfg.player_max_hp,
                         dist_norm=cfg.dist_norm, monster_speed_norm=cfg.monster_speed_norm,
                         monster_count_norm=cfg.monster_count_norm, bullet_norm=cfg.bullet_norm)
    plj = [(jnp.asarray(W.numpy()), jnp.asarray(b.numpy())) for W, b in pl]
    enj = [(jnp.asarray(W.numpy()), jnp.asarray(b.numpy())) for W, b in en]
    return env, pl, en, cj, sj, plj, enj


def _cj(cfg):
    return SimpleNamespace(dt=cfg.dt, player_speed=cfg.player_speed, player_half=cfg.player_half,
                           player_radius=cfg.player_radius, buffer=cfg.buffer, bullet_radius=cfg.bullet_radius,
                           eps=cfg.eps, defense_min_floor=cfg.defense_min_floor, player_max_hp=cfg.player_max_hp,
                           dist_norm=cfg.dist_norm, monster_speed_norm=cfg.monster_speed_norm,
                           monster_count_norm=cfg.monster_count_norm, bullet_norm=cfg.bullet_norm)


def _sj(env, B):
    a = lambda x: jnp.asarray(x.detach().cpu().numpy())
    return dict(N=env.N, M=env.M, B=B, spawn_tick=a(env.spawn_tick), offset=a(env.offset), mon_speed=a(env.mon_speed),
                mon_boxW=a(env.mon_boxW), mon_dmg=a(env.mon_dmg), mon_direct=a(env.mon_direct), hp0=a(env.hp0),
                map_half=a(env.map_half), bullet_speed=env.bullet_speed, bullet_damage=env.bullet_damage,
                bullet_range=env.bullet_range, fire_interval=env.fire_interval, contact_interval=env.contact_interval,
                defense=env.defense, bullets_per_shot=env.bullets_per_shot, penetration=env.penetration,
                mag_size=env.mag_size, reload_ticks=env.reload_ticks, max_dev=env.max_dev, exo_speed=env.exo_speed)


def bench_big(pop=128, perm=32, ticks=600, bullets=32):
    """Apples-to-apples cuda comparison at the TRAINING config: torch-eager vs torch-fusion vs JAX-jit.
    Same env/schedule (N=maps*perm) and the SAME single net broadcast over P on both engines."""
    import train_torch as T
    dev = "cuda"; T._perf_setup(dev); Pp = 2 * pop
    a = type("A", (), {})(); a.client = "../monstro_client"; a.dataset = "datasets/surround"; a.map = ""
    a.perm = perm; a.cap = 16; a.bullets = bullets; a.device = dev
    env, nmaps, nenv = T.build_env(a)
    pl = P.init_mlp(T.PLAYER_SIZES, device=dev, seed=7); en = P.init_mlp(T.ENEMY_SIZES, device=dev, seed=11)
    pf = lambda o: P.apply_mlp(pl, o); ef = lambda o: P.apply_enemy(en, o)
    cj, sj = _cj(env.cfg), _sj(env, bullets)
    plj = [(jnp.asarray(W.detach().cpu().numpy()), jnp.asarray(b.detach().cpu().numpy())) for W, b in pl]
    enj = [(jnp.asarray(W.detach().cpu().numpy()), jnp.asarray(b.detach().cpu().numpy())) for W, b in en]
    f = env_jax.make_rollout(Pp, cj, sj, env_jax.make_tables(cj, sj, ticks))

    def tbench(fn, n=5, warm=2):
        for _ in range(warm): fn(); torch.cuda.synchronize()
        xs = []
        for _ in range(n):
            torch.cuda.synchronize(); t0 = time.perf_counter(); fn(); torch.cuda.synchronize(); xs.append(time.perf_counter() - t0)
        return st.median(xs)
    def jbench(fn, n=5, warm=2):
        for _ in range(warm): jax.block_until_ready(fn())
        xs = []
        for _ in range(n):
            t0 = time.perf_counter(); jax.block_until_ready(fn()); xs.append(time.perf_counter() - t0)
        return st.median(xs)

    roll = lambda: env.rollout(Pp, ticks, pf, ef)
    te = tbench(roll)
    env._core = torch.compile(env._core, mode=None)
    tf = tbench(roll, warm=3)
    tj = jbench(lambda: f(plj, enj))
    print(f"\nCUDA BIG (P={Pp} N={nenv} M={env.M} B={bullets} ticks={ticks}):")
    print(f"  torch-eager : {te*1000:8.1f} ms   (1.00x)")
    print(f"  torch-fusion: {tf*1000:8.1f} ms   ({te/tf:.2f}x)")
    print(f"  jax-jit     : {tj*1000:8.1f} ms   ({te/tj:.2f}x vs eager, {tf/tj:.2f}x vs fusion)")


def main():
    if "--big" in sys.argv:
        bench_big()
        return
    env, pl, en, cj, sj, plj, enj = build()
    pf = lambda o: P.apply_mlp(pl, o); ef = lambda o: P.apply_enemy(en, o)
    ticks = 200

    # ---- parity (P=1) ----
    o = env.rollout(1, ticks, pf, ef)
    rp, re, k, hp = env_jax.make_rollout(1, cj, sj, env_jax.make_tables(cj, sj, ticks))(plj, enj)
    jax.block_until_ready((rp, re, k, hp))
    print("PARITY (P=1):")
    print("  torch: kills=%.1f hp=%.4f rp=%.5f re=%.5f" % (o["kills"].sum(), o["hp"].sum(),
                                                           o["reward_player"].sum(), o["reward_enemy"].sum()))
    print("  jax  : kills=%.1f hp=%.4f rp=%.5f re=%.5f" % (float(k.sum()), float(hp.sum()),
                                                          float(rp.sum()), float(re.sum())))

    # ---- throughput (P=96) ----
    Pp = 96
    tb = env_jax.make_tables(cj, sj, ticks)
    f = env_jax.make_rollout(Pp, cj, sj, tb)
    env.rollout(Pp, ticks, pf, ef)                                    # torch warmup
    jax.block_until_ready(f(plj, enj))                               # jax jit warmup

    def bench(fn, n=5):
        xs = []
        for _ in range(n):
            t0 = time.perf_counter(); fn(); xs.append(time.perf_counter() - t0)
        return st.median(xs)
    te = bench(lambda: env.rollout(Pp, ticks, pf, ef))
    tj = bench(lambda: jax.block_until_ready(f(plj, enj)))
    print(f"\nTHROUGHPUT (P={Pp} N={env.N} ticks={ticks}, CPU here — GPU on the 3090 is the real test):")
    print(f"  torch rollout: {te*1000:7.0f} ms")
    print(f"  jax rollout:   {tj*1000:7.0f} ms   ({te/tj:.2f}x vs torch)")


if __name__ == "__main__":
    main()
