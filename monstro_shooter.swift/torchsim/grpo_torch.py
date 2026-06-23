"""GRPO (Group Relative Policy Optimization) for the PLAYER policy — a critic-free policy-gradient that's
far more sample-efficient than ES. The [P,N,M,B] batch's **P dim is the GROUP**: P copies of ONE policy
that diverge only by action-sampling noise, so the advantage is normalized over P per env (the critic-free
group baseline). The sim runs grad-free (actions detached into env.step_pa, which uses the compiled _core
→ fusion kept); grad flows only through the Gaussian log_prob. Deployed model = the **mean net** (saved as
the same {sizes,w,b} JSON — parity with the Swift game unchanged).

Player-only here: env_torch computes the enemy obs MID-step (post-spawn), so enemy-GRPO needs a further
refactor — train_torch alternates GRPO-player / ES-enemy for the co-evolution.
"""
import math
import torch
import policy_torch as P

LOG2PI = math.log(2 * math.pi)


def init_player(sizes, device, seed, std0=0.6):
    """Leaf (W,b) params (grad) + a shared learnable log_std [act_dim]. Adam optimizes all of them."""
    base = P.init_mlp(sizes, device=device, seed=seed)
    params = [(W.clone().detach().requires_grad_(True), b.clone().detach().requires_grad_(True)) for W, b in base]
    log_std = torch.full((sizes[-1],), math.log(std0), device=device, requires_grad=True)
    return params, log_std


def opt_params(params, log_std):
    return [w for wb in params for w in wb] + [log_std]


def mean_params(params):
    """Detached copy — the frozen opponent / the deployed mean net (saved via policy_torch.to_json)."""
    return [(W.detach(), b.detach()) for W, b in params]


def _reward_to_go(rew, gamma):
    """rew [T,P,N] -> discounted reward-to-go [T,P,N] (dense per-tick reward credit assignment)."""
    out = torch.empty_like(rew)
    acc = torch.zeros_like(rew[0])
    for t in range(rew.shape[0] - 1, -1, -1):
        acc = rew[t] + gamma * acc
        out[t] = acc
    return out


def grpo_player_step(env, ticks, params, log_std, opt, enemy_params, P_group, gamma=0.99, ent_coef=0.0):
    """One GRPO update of the player vs a frozen enemy. Returns (loss, mean_return)."""
    ef = lambda obs: P.apply_enemy(enemy_params, obs)        # frozen enemy (plain tensors, no grad)
    s = env.reset(P_group)
    logps, rews = [], []
    for t in range(1, ticks + 1):
        with torch.no_grad():
            obs = env.player_obs_vec(s)                      # [P,N,8]
        mu = P.apply_mlp(params, obs)                        # [P,N,4]  (grad)
        std = log_std.exp()
        a = (mu + std * torch.randn_like(mu)).detach()       # realized action (sampled, no grad)
        logp = (-0.5 * ((a - mu) / std) ** 2 - log_std - 0.5 * LOG2PI).sum(-1)   # [P,N] grad wrt mu,log_std
        with torch.no_grad():
            s, r_p, _ = env.step_pa(s, t, a, ef)             # sim grad-free (action + enemy detached)
        logps.append(logp); rews.append(r_p)
    logp = torch.stack(logps)                                # [T,P,N]  (graph)
    rew = torch.stack(rews)                                  # [T,P,N]  (detached)
    R = _reward_to_go(rew, gamma)                            # [T,P,N]
    A = (R - R.mean(1, keepdim=True)) / (R.std(1, keepdim=True) + 1e-6)   # group-normalize over P (critic-free)
    loss = -(A.detach() * logp).mean() - ent_coef * log_std.sum()        # + entropy bonus (exploration)
    opt.zero_grad(set_to_none=True)
    loss.backward()
    opt.step()
    return float(loss.detach()), float(rew.sum(0).mean())
