"""Fully-fused JAX PPO for the player (T4) — the all-XLA counterpart to ppo_torch.py.

Where torch-PPO gets Inductor FUSION but still drives 600 sequential per-tick kernel launches in the
rollout, JAX-PPO runs the WHOLE rollout as one `lax.scan` (zero Python/dispatch per tick) and the GAE as
a reverse `lax.scan` — the same structural win env_jax already gives ES, now for the policy-gradient path.
The clipped-surrogate update is jax.grad + optax Adam, minibatched under jit.

Parity: identical dynamics to env_torch (env_jax is the bit-identical port; we reuse its step_pa, so a
JAX-trained net runs in the Swift game exactly like a torch-trained one). Deploy stays torch (Core ML
export reads the same {sizes,w,b} JSON) — JAX-PPO is a TRAINING-throughput engine only.

Run the A/B benchmark (jax vs torch PPO, same frozen enemy, same budget):
  python jax_ppo.py --budget 60
"""
import math, time
from functools import partial
import numpy as np
import jax
import jax.numpy as jnp
from jax import lax
import optax

import env_jax
import jax_engine  # _cj / _sj / _to_jax converters (torch env -> jax cfg/sched/params)

LOG2PI = math.log(2 * math.pi)


# ---- params (pure-jax pytrees) ----------------------------------------------------------------------
def init_mlp_jax(sizes, key, scale=0.1):
    """Mirror policy_torch.init_mlp draw order is NOT required (jax trains its own net); a fresh Gaussian
    init is fine — only the SIM must match torch, not the initial weights. Returns list of (W[in,out], b)."""
    params = []
    for i in range(1, len(sizes)):
        key, sub = jax.random.split(key)
        W = jax.random.normal(sub, (sizes[i - 1], sizes[i]), jnp.float32) * scale
        params.append((W, jnp.zeros((sizes[i],), jnp.float32)))
    return params, key


def _logp(a, mu, log_std):
    std = jnp.exp(log_std)
    return (-0.5 * ((a - mu) / std) ** 2 - log_std - 0.5 * LOG2PI).sum(-1)


# ---- rollout: one jitted lax.scan, PRNG threaded through the carry --------------------------------
def make_ppo_rollout(P, cfg, sched, tables):
    """f(pparams, log_std, vparams, eparams, key) -> (obs,a,logp,val,rew) each [T,P,N,*]. cfg/sched/tables
    are closed over (baked constants); only the nets + key vary, so this jits once and replays."""
    @jax.jit
    def f(pparams, log_std, vparams, eparams, key):
        s0 = env_jax.reset(cfg, sched, P)
        std = jnp.exp(log_std)

        def body(carry, xs):
            s, key = carry
            obs = env_jax.player_obs(cfg, sched, s)              # [P,N,8]
            mu = env_jax.apply_mlp(pparams, obs)                 # [P,N,4]
            val = env_jax.apply_mlp(vparams, obs)[..., 0]        # [P,N]
            key, sub = jax.random.split(key)
            a = mu + std * jax.random.normal(sub, mu.shape)      # sampled action
            logp = _logp(a, mu, log_std)                         # [P,N]
            ns, (r_p, _r_e) = env_jax.step_pa(cfg, sched, a, eparams, s, xs)
            return (ns, key), (obs, a, logp, val, r_p)

        (_, _), (obs, a, logp, val, rew) = lax.scan(body, (s0, key), tables)
        return obs, a, logp, val, rew
    return f


def gae(rew, val, gamma, lam):
    """rew,val [T,P,N] -> (adv, ret). Bootstrap V_T = 0 (full-horizon). Reverse lax.scan (no Python loop)."""
    val_next = jnp.concatenate([val[1:], jnp.zeros_like(val[:1])], 0)
    deltas = rew + gamma * val_next - val

    def body(acc, delta):
        acc = delta + gamma * lam * acc
        return acc, acc

    _, adv = lax.scan(body, jnp.zeros_like(val[0]), deltas, reverse=True)
    return adv, adv + val


# ---- PPO update: jax.grad + optax, minibatched epoch scanned under jit ----------------------------
def make_update(opt, clip, vcoef, ent_coef, n_mb, mb):
    def loss_fn(tp, obs, a, lp_old, adv, ret):
        pparams, log_std, vparams = tp["p"], tp["ls"], tp["v"]
        mu = env_jax.apply_mlp(pparams, obs)
        logp = _logp(a, mu, log_std)
        ratio = jnp.exp(logp - lp_old)
        s1 = ratio * adv
        s2 = jnp.clip(ratio, 1 - clip, 1 + clip) * adv
        pl = -jnp.minimum(s1, s2).mean()
        v = env_jax.apply_mlp(vparams, obs)[..., 0]
        vl = ((v - ret) ** 2).mean()
        ent = (log_std + 0.5 * math.log(2 * math.e * math.pi)).sum()
        return pl + vcoef * vl - ent_coef * ent

    @jax.jit
    def epoch(tp, opt_state, perm, O, A, LP, AD, RET):
        """One epoch: shuffle by `perm`, scan over the n_mb minibatches applying Adam each."""
        idx = perm[: n_mb * mb].reshape(n_mb, mb)

        def mb_step(carry, mb_idx):
            tp, opt_state = carry
            g = jax.grad(loss_fn)(tp, O[mb_idx], A[mb_idx], LP[mb_idx], AD[mb_idx], RET[mb_idx])
            updates, opt_state = opt.update(g, opt_state, tp)
            tp = optax.apply_updates(tp, updates)
            return (tp, opt_state), None

        (tp, opt_state), _ = lax.scan(mb_step, (tp, opt_state), idx)
        return tp, opt_state
    return epoch


class JaxPPO:
    """Player PPO in pure JAX vs a FIXED (frozen) enemy net. Mirrors ppo_torch knobs. The enemy is passed
    as torch params each step (the co-evo opponent); it's converted to jax once per step (cheap)."""

    def __init__(self, env, ticks, group, sizes, seed=0, std0=0.6, lr=3e-4, gamma=0.99, lam=0.95,
                 clip=0.2, epochs=4, minibatch=262144, vcoef=0.5, ent=0.0):
        self.cfg = jax_engine._cj(env.cfg)
        self.sched = jax_engine._sj(env, env.B)
        self.tables = env_jax.make_tables(self.cfg, self.sched, ticks)
        self.P, self.N, self.T = group, env.N, ticks
        self.epochs, self.gamma, self.lam = epochs, gamma, lam
        key = jax.random.PRNGKey(seed)
        self.pparams, key = init_mlp_jax(sizes, key)
        self.vparams, key = init_mlp_jax([sizes[0], 32, 32, 1], key)
        self.log_std = jnp.full((sizes[-1],), math.log(std0), jnp.float32)
        self.key = key
        self.rollout = make_ppo_rollout(group, self.cfg, self.sched, self.tables)
        B = ticks * group * env.N
        self.mb = min(minibatch, B)
        self.n_mb = max(1, B // self.mb)
        self.opt = optax.adam(lr)
        self.tp = {"p": self.pparams, "ls": self.log_std, "v": self.vparams}
        self.opt_state = self.opt.init(self.tp)
        self.update = make_update(self.opt, clip, vcoef, ent, self.n_mb, self.mb)

    def step(self, enemy_params_torch):
        """One PPO update vs the frozen enemy. Returns mean episode return (float)."""
        eparams = jax_engine._to_jax(enemy_params_torch)
        self.key, kr = jax.random.split(self.key)
        obs, a, logp, val, rew = self.rollout(self.tp["p"], self.tp["ls"], self.tp["v"], eparams, kr)
        adv, ret = gae(rew, val, self.gamma, self.lam)
        adv = (adv - adv.mean()) / (adv.std() + 1e-6)
        F = lambda x: x.reshape(-1, x.shape[-1]) if x.ndim == 4 else x.reshape(-1)
        O, A, LP, AD, RET = F(obs), F(a), F(logp), F(adv), F(ret)
        B = O.shape[0]
        for _ in range(self.epochs):
            self.key, kp = jax.random.split(self.key)
            perm = jax.random.permutation(kp, B)
            self.tp, self.opt_state = self.update(self.tp, self.opt_state, perm, O, A, LP, AD, RET)
        return float(jnp.asarray(rew).sum(0).mean())

    def player_torch(self, device):
        """Export the current player net as torch params [(W,b)] for eval / Core ML save."""
        import torch
        return [(torch.tensor(np.asarray(W), device=device), torch.tensor(np.asarray(b), device=device))
                for W, b in self.tp["p"]]


# ---- A/B benchmark: jax-PPO vs torch-PPO, same frozen enemy, same budget --------------------------
def _bench(args):
    import torch, types
    import train_torch as T, policy_torch as P, ppo_torch as PPO, grpo_torch as G

    dev = "cuda" if torch.cuda.is_available() else "cpu"
    a = types.SimpleNamespace(client="../monstro_client", dataset=args.dataset, map="", perm=args.perm,
                              cap=16, bullets=args.bullets, device=dev)
    a.device = dev
    env, n_maps, n_envs = T.build_env(a)
    env.rw_kill, env.rw_survive = 1.0, 0.01
    enemy = P.init_mlp(T.ENEMY_SIZES, device=dev, seed=11)        # FROZEN shared opponent (same for both)
    gd = T.data.GameData(a.client)
    weapon = gd.weapons.get(1) or next(iter(gd.weapons.values()))
    exo = gd.exoskeletons.get(1) or next(iter(gd.exoskeletons.values()))
    ev = lambda pl: T.eval_line(T.run_eval(gd, weapon, exo, a, pl, enemy, dev, seeds=3)[0])
    a.eval_map = ""; a.eval_ticks = 0; a.eval_seeds = 3

    print(f"A/B: ticks={args.ticks} group={args.group} N={n_envs} mb={args.minibatch} budget={args.budget}s/engine  dev={dev}")

    # ---- torch PPO (Inductor fusion) ----
    if dev == "cuda":                                                # fair fight: give torch its TF32 fast-path
        torch.backends.cuda.matmul.allow_tf32 = True
        torch.backends.cudnn.allow_tf32 = True
        torch.set_float32_matmul_precision("high")
    torch.manual_seed(0)
    gparams, glog = G.init_player(T.PLAYER_SIZES, dev, seed=7, std0=args.std)
    vparams = PPO.init_value(dev, seed=23)
    popt = torch.optim.Adam(G.opt_params(gparams, glog) + PPO.value_params_flat(vparams), lr=args.lr)
    env._core = torch.compile(env._core)
    PPO.ppo_step(env, args.ticks, gparams, glog, vparams, popt, enemy, args.group,
                 epochs=args.epochs, minibatch=args.minibatch)        # warmup (compile)
    torch.cuda.synchronize() if dev == "cuda" else None
    t0 = time.time(); it = 0
    while time.time() - t0 < args.budget:
        PPO.ppo_step(env, args.ticks, gparams, glog, vparams, popt, enemy, args.group,
                     epochs=args.epochs, minibatch=args.minibatch); it += 1
    torch.cuda.synchronize() if dev == "cuda" else None
    t_torch = time.time() - t0
    torch_eval = ev(G.mean_params(gparams)); torch_it = it
    print(f"  torch-PPO : {it} updates in {t_torch:.1f}s  ({it/t_torch:.2f}/s)   eval: {torch_eval}")

    # ---- jax PPO (full lax.scan) ----
    jp = JaxPPO(env, args.ticks, args.group, T.PLAYER_SIZES, seed=0, std0=args.std, lr=args.lr,
                epochs=args.epochs, minibatch=args.minibatch)
    jp.step(enemy)                                                   # warmup (jit compile)
    t0 = time.time(); it = 0
    while time.time() - t0 < args.budget:
        jp.step(enemy); it += 1
    t_jax = time.time() - t0
    jax_eval = ev(jp.player_torch(dev)); jax_it = it
    print(f"  jax-PPO   : {it} updates in {t_jax:.1f}s  ({it/t_jax:.2f}/s)   eval: {jax_eval}")
    print(f"  THROUGHPUT: jax/torch = {(jax_it/t_jax)/(torch_it/t_torch):.2f}x updates/sec")


if __name__ == "__main__":
    import argparse
    ap = argparse.ArgumentParser()
    ap.add_argument("--dataset", default="datasets/tiny")
    ap.add_argument("--perm", type=int, default=32)
    ap.add_argument("--bullets", type=int, default=32)
    ap.add_argument("--ticks", type=int, default=600)
    ap.add_argument("--group", type=int, default=128)
    ap.add_argument("--minibatch", type=int, default=262144)
    ap.add_argument("--epochs", type=int, default=4)
    ap.add_argument("--lr", type=float, default=3e-4)
    ap.add_argument("--std", type=float, default=0.6)
    ap.add_argument("--budget", type=float, default=60.0)
    _bench(ap.parse_args())
