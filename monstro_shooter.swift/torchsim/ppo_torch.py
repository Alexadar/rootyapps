"""PPO (clipped surrogate + value critic + GAE) for the player — the variance reduction GRPO lacked.
Reuses grpo_torch's Gaussian policy (mean MLP + log_std) and env.step_pa (compiled _core, parity-neutral).
The critic V(obs) predicts returns; GAE gives low-variance advantages; the clipped objective lets us reuse
each collected batch over K epochs (the sample-efficiency win over ES/GRPO). The rollout is collected under
no_grad (detached transitions) and the update recomputes log_prob/value with grad per minibatch — so no
T-deep graph is retained. Deployed model = the mean policy net (same {sizes,w,b} JSON, parity-safe)."""
import math
import torch
import policy_torch as P

LOG2PI = math.log(2 * math.pi)


def init_value(device, seed, in_dim=8):
    """Critic V(obs) -> scalar. Leaf params (grad). Training only; discarded at save."""
    base = P.init_mlp([in_dim, 32, 32, 1], device=device, seed=seed)
    return [(W.clone().detach().requires_grad_(True), b.clone().detach().requires_grad_(True)) for W, b in base]


def value_params_flat(vparams):
    return [w for wb in vparams for w in wb]


def _value(vparams, obs):
    return P.apply_mlp(vparams, obs).squeeze(-1)            # [...,1] -> [...]


def _logp(a, mu, log_std):
    std = log_std.exp()
    return (-0.5 * ((a - mu) / std) ** 2 - log_std - 0.5 * LOG2PI).sum(-1)


def _entropy(log_std):
    return (log_std + 0.5 * math.log(2 * math.e * math.pi)).sum()


@torch.no_grad()
def rollout(env, ticks, params, log_std, vparams, enemy_params, P_group):
    """Collect detached transitions vs a frozen enemy. Returns obs,a,logp_old,rew,val each [T,P,N,*]."""
    ef = lambda obs: P.apply_enemy(enemy_params, obs)
    s = env.reset(P_group)
    obs_l, a_l, lp_l, r_l, v_l = [], [], [], [], []
    for t in range(1, ticks + 1):
        obs = env.player_obs_vec(s)                        # [P,N,8]
        mu = P.apply_mlp(params, obs)
        std = log_std.exp()
        a = mu + std * torch.randn_like(mu)                # [P,N,4]
        obs_l.append(obs); a_l.append(a)
        lp_l.append(_logp(a, mu, log_std)); v_l.append(_value(vparams, obs))
        s, r_p, _, _ = env.step_pa(s, t, a, ef)
        r_l.append(r_p)
    return (torch.stack(obs_l), torch.stack(a_l), torch.stack(lp_l), torch.stack(r_l), torch.stack(v_l))


def _gae(rew, val, gamma, lam):
    """rew,val [T,P,N] -> (advantage, return) [T,P,N]; bootstrap V_T = 0 (full-horizon episodes)."""
    T = rew.shape[0]
    adv = torch.zeros_like(rew)
    last = torch.zeros_like(rew[0])
    for t in range(T - 1, -1, -1):
        v_next = val[t + 1] if t + 1 < T else torch.zeros_like(val[0])
        delta = rew[t] + gamma * v_next - val[t]
        last = delta + gamma * lam * last
        adv[t] = last
    return adv, adv + val


def ppo_step(env, ticks, params, log_std, vparams, opt, enemy_params, P_group,
             gamma=0.99, lam=0.95, clip=0.2, epochs=4, minibatch=16384, vcoef=0.5, ent=0.0):
    """One PPO update of the player vs a frozen enemy. Returns (policy_loss, value_loss, mean_return)."""
    obs, a, lp_old, rew, val = rollout(env, ticks, params, log_std, vparams, enemy_params, P_group)
    with torch.no_grad():
        adv, ret = _gae(rew, val, gamma, lam)
        adv = (adv - adv.mean()) / (adv.std() + 1e-6)
    O = obs.reshape(-1, obs.shape[-1]); A = a.reshape(-1, a.shape[-1])
    LP = lp_old.reshape(-1); AD = adv.reshape(-1); RET = ret.reshape(-1)
    B = O.shape[0]
    pls, vls = [], []
    for _ in range(epochs):
        perm = torch.randperm(B, device=O.device)
        for i in range(0, B, minibatch):
            mb = perm[i:i + minibatch]
            mu = P.apply_mlp(params, O[mb])
            ratio = (_logp(A[mb], mu, log_std) - LP[mb]).exp()
            s1 = ratio * AD[mb]
            s2 = torch.clamp(ratio, 1 - clip, 1 + clip) * AD[mb]
            pl = -torch.min(s1, s2).mean()
            vl = (_value(vparams, O[mb]) - RET[mb]).pow(2).mean()
            loss = pl + vcoef * vl - ent * _entropy(log_std)
            opt.zero_grad(set_to_none=True); loss.backward(); opt.step()
            pls.append(float(pl.detach())); vls.append(float(vl.detach()))
    return sum(pls) / len(pls), sum(vls) / len(vls), float(rew.sum(0).mean())
