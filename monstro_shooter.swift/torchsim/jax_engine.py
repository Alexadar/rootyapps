"""Hybrid engine for `train_torch.py --engine jax`: the torch ES/eval/save loop drives a JAX `lax.scan`
rollout for fitness (the only expensive part — ~1.23x over torch-fusion on cuda; T3). Weights stay torch
(ES math is torch); each ES iter the population weights are copied to JAX, the whole episode runs as one
fused XLA program, and per-member mean reward comes back as a torch [2*pop] tensor for the ES update.

env_jax is the parity-proven port (bit-identical to env_torch on CPU at P=1), so a model trained here runs
correctly in the Swift/Metal game just like a torch-trained one — the engine choice only affects speed."""
import numpy as np, torch
import jax.numpy as jnp
from types import SimpleNamespace
import env_jax


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


def _to_jax(params):
    # env_jax.apply_mlp does matmul(h,W)+b. For a POPULATION (W [P,in,out]) the matmul output is
    # [P, <middle>, out] and the bias [P,out] must gain a middle singleton -> [P,1,out] to broadcast.
    # Single nets (W [in,out], b [out]) are left as-is (preserves env_jax's P=1 parity).
    out = []
    for W, b in params:
        Wj = jnp.asarray(W.detach().cpu().numpy()); bj = jnp.asarray(b.detach().cpu().numpy())
        if Wj.ndim == 3:
            bj = bj[:, None, :]
        out.append((Wj, bj))
    return out


class JaxRollout:
    """Built once for a fixed population P=2*pop and tick count. .reward_player/_enemy run the jitted
    rollout (compiled on first call, replayed after) and return torch [P] mean-reward tensors."""

    def __init__(self, env, ticks, P, device):
        self.device = device
        cj, sj = _cj(env.cfg), _sj(env, env.B)
        self.f = env_jax.make_rollout(P, cj, sj, env_jax.make_tables(cj, sj, ticks))

    def _run(self, player_params, enemy_params):
        return self.f(_to_jax(player_params), _to_jax(enemy_params))   # (rps,res,kills,hp) each [P,N]

    def _t(self, arr):
        return torch.from_numpy(np.asarray(arr)).to(self.device)

    def reward_player(self, player_params, enemy_params):
        rps, _, _, _ = self._run(player_params, enemy_params)
        return self._t(rps.mean(1))

    def reward_enemy(self, player_params, enemy_params):
        _, res, _, _ = self._run(player_params, enemy_params)
        return self._t(res.mean(1))
