"""PPO for the single-query attention player (policy_attn) — the set-obs counterpart to ppo_torch.

Same clipped-surrogate + GAE math as ppo_torch (reused verbatim), but the policy consumes the per-monster
BUNDLE (self_feat, mon_feat, alive) from env.player_set_obs instead of a flat [P,N,8] vector, and the CRITIC
SHARES the attention encoder (value head of apply_attn) — so there's one param set, no separate vparams.
Rollout is collected under no_grad (detached transitions); the update recomputes mu/value with grad per
minibatch. The minibatch flatten collapses [T,P,N] -> B for every bundle component IN THE SAME ORDER, so a
minibatch index selects whole monster-sets (self/mon/alive/action stay aligned)."""
import math
import torch
import policy_torch as P
import policy_attn as AT

LOG2PI = math.log(2 * math.pi)


def _logp(a, mu, log_std):
    std = log_std.exp()
    return (-0.5 * ((a - mu) / std) ** 2 - log_std - 0.5 * LOG2PI).sum(-1)


def _entropy(log_std):
    return (log_std + 0.5 * math.log(2 * math.e * math.pi)).sum()


def _gae(rew, val, gamma, lam):
    T = rew.shape[0]
    adv = torch.zeros_like(rew)
    last = torch.zeros_like(rew[0])
    for t in range(T - 1, -1, -1):
        v_next = val[t + 1] if t + 1 < T else torch.zeros_like(val[0])
        delta = rew[t] + gamma * v_next - val[t]
        last = delta + gamma * lam * last
        adv[t] = last
    return adv, adv + val


@torch.no_grad()
def rollout(env, ticks, params, log_std, enemy_params, P_group, mm_dtype=None):
    """Collect the bundle + actions vs a frozen enemy. Returns SF[T,P,N,Fs] MF[T,P,N,M,Fm] AL[T,P,N,M]
    A[T,P,N,act] LP/REW/VAL[T,P,N]."""
    ef = lambda obs: P.apply_enemy(enemy_params, obs, mm_dtype)
    s = env.reset(P_group)
    sf_l, mf_l, al_l, a_l, lp_l, r_l, v_l = ([] for _ in range(7))
    std = log_std.exp()
    for t in range(1, ticks + 1):
        sf, mf, al = env.player_set_obs(s)                 # [P,N,Fs],[P,N,M,Fm],[P,N,M]
        mu, val = AT.apply_attn(params, sf, mf, al, mm_dtype)
        a = mu + std * torch.randn_like(mu)
        sf_l.append(sf); mf_l.append(mf); al_l.append(al)
        a_l.append(a); lp_l.append(_logp(a, mu, log_std)); v_l.append(val)
        s, r_p, _ = env.step_pa(s, t, a, ef)
        r_l.append(r_p)
    return (torch.stack(sf_l), torch.stack(mf_l), torch.stack(al_l),
            torch.stack(a_l), torch.stack(lp_l), torch.stack(r_l), torch.stack(v_l))


def ppo_step(env, ticks, params, log_std, opt, enemy_params, P_group,
             gamma=0.99, lam=0.95, clip=0.2, epochs=4, minibatch=16384, vcoef=0.5, ent=0.0, mm_dtype=None):
    """One PPO update of the attention player vs a frozen enemy. Returns (policy_loss, value_loss, mean_return)."""
    SF, MF, AL, A, LP, REW, VAL = rollout(env, ticks, params, log_std, enemy_params, P_group, mm_dtype)
    with torch.no_grad():
        adv, ret = _gae(REW, VAL, gamma, lam)
        adv = (adv - adv.mean()) / (adv.std() + 1e-6)
    Fs, Fm, M = SF.shape[-1], MF.shape[-1], MF.shape[-2]
    SFb = SF.reshape(-1, Fs); MFb = MF.reshape(-1, M, Fm); ALb = AL.reshape(-1, M)   # same row order -> aligned
    Ab = A.reshape(-1, A.shape[-1]); LPb = LP.reshape(-1); ADb = adv.reshape(-1); RETb = ret.reshape(-1)
    B = SFb.shape[0]
    pls, vls = [], []
    for _ in range(epochs):
        perm = torch.randperm(B, device=SFb.device)
        for i in range(0, B, minibatch):
            mb = perm[i:i + minibatch]
            mu, val = AT.apply_attn(params, SFb[mb], MFb[mb], ALb[mb], mm_dtype)
            ratio = (_logp(Ab[mb], mu, log_std) - LPb[mb]).exp()
            s1 = ratio * ADb[mb]
            s2 = torch.clamp(ratio, 1 - clip, 1 + clip) * ADb[mb]
            pl = -torch.min(s1, s2).mean()
            vl = (val - RETb[mb]).pow(2).mean()
            loss = pl + vcoef * vl - ent * _entropy(log_std)
            opt.zero_grad(set_to_none=True); loss.backward(); opt.step()
            pls.append(float(pl.detach())); vls.append(float(vl.detach()))
    return sum(pls) / len(pls), sum(vls) / len(vls), float(REW.sum(0).mean())
