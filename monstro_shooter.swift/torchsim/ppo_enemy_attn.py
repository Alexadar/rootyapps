"""PPO for the ATTENTION enemy — each monster is a single-query cross-attention over its K nearest neighbors
(env.enemy_set_obs), reusing policy_attn VERBATIM (shared encoder + value head, like the player). Cooperative
multi-agent: shared team reward broadcast to every monster, per-monster GAE, update on ALIVE monster-samples
only, player FROZEN (mean action injected; enemy action injected via a closure so compiled _core is untouched).
The monster dim M is folded into the batch so AT.apply_attn (single leading batch dim + a token axis) runs per
monster over its K neighbor tokens. Deployed enemy = the attention mean net (AT.to_json, kind=attention)."""
import math
import torch
import policy_attn as AT

LOG2PI = math.log(2 * math.pi)


def _logp(a, mu, log_std):
    std = log_std.exp()
    return (-0.5 * ((a - mu) / std) ** 2 - log_std - 0.5 * LOG2PI).sum(-1)


def _entropy(log_std):
    return (log_std + 0.5 * math.log(2 * math.e * math.pi)).sum()


def apply(params, sf, nbr, mask, mm_dtype=None):
    """sf [...,Fs], nbr [...,K,Fn], mask [...,K] (arbitrary leading dims) -> mu [...,act], val [...].
    Folds all leading dims into one batch for AT.apply_attn (per-monster query over K neighbor tokens)."""
    lead = sf.shape[:-1]
    mu, val = AT.apply_attn(params, sf.reshape(-1, sf.shape[-1]),
                            nbr.reshape(-1, nbr.shape[-2], nbr.shape[-1]), mask.reshape(-1, mask.shape[-1]), mm_dtype)
    return mu.reshape(*lead, mu.shape[-1]), val.reshape(*lead)


def _gae(team_rew, val, gamma, lam):
    T = val.shape[0]
    rewM = team_rew.unsqueeze(-1).expand_as(val)
    adv = torch.zeros_like(val)
    last = torch.zeros_like(val[0])
    for t in range(T - 1, -1, -1):
        v_next = val[t + 1] if t + 1 < T else torch.zeros_like(val[0])
        delta = rewM[t] + gamma * v_next - val[t]
        last = delta + gamma * lam * last
        adv[t] = last
    return adv, adv + val


@torch.no_grad()
def rollout(env, ticks, params, log_std, player, P_group, mm_dtype=None):
    pf = lambda b: AT.apply_attn(player, b[0], b[1], b[2], mm_dtype)[0]
    s = env.reset(P_group)
    std = log_std.exp()
    sf_l, nb_l, mk_l, a_l, lp_l, r_l, v_l, al_l = ([] for _ in range(8))
    for t in range(1, ticks + 1):
        sf, nbr, mask = env.enemy_set_obs(s)                        # [P,N,M,*]
        mu, val = apply(params, sf, nbr, mask, mm_dtype)            # [P,N,M,2],[P,N,M]
        a = mu + std * torch.randn_like(mu)
        alive = ((s["mon_act"] > 0.5) & (s["mon_hp"] > 0)).float()
        sf_l.append(sf); nb_l.append(nbr); mk_l.append(mask)
        a_l.append(a); lp_l.append(_logp(a, mu, log_std)); v_l.append(val); al_l.append(alive)
        a_player = pf(env.player_set_obs(s))                        # frozen player, mean action
        s, _rp, r_e, _ = env.step_pa(s, t, a_player, lambda _o: a)  # inject enemy action
        r_l.append(r_e)                                            # [P,N] shared team reward
    return (torch.stack(sf_l), torch.stack(nb_l), torch.stack(mk_l), torch.stack(a_l),
            torch.stack(lp_l), torch.stack(r_l), torch.stack(v_l), torch.stack(al_l))


def ppo_step(env, ticks, params, log_std, opt, player, P_group,
             gamma=0.99, lam=0.95, clip=0.2, epochs=4, minibatch=262144, vcoef=0.5, ent=0.003, mm_dtype=None):
    """One PPO update of the attention enemy vs the frozen player. Returns (policy_loss, value_loss, team_return)."""
    SF, NB, MK, A, LP, REW, VAL, AL = rollout(env, ticks, params, log_std, player, P_group, mm_dtype)
    with torch.no_grad():
        adv, ret = _gae(REW, VAL, gamma, lam)
        m = AL > 0.5
        adv = (adv - adv[m].mean()) / (adv[m].std() + 1e-6)
    Fs, K, Fn = SF.shape[-1], NB.shape[-2], NB.shape[-1]
    SFb = SF.reshape(-1, Fs); NBb = NB.reshape(-1, K, Fn); MKb = MK.reshape(-1, K)
    Ab = A.reshape(-1, A.shape[-1]); LPb = LP.reshape(-1); ADb = adv.reshape(-1); RETb = ret.reshape(-1)
    keep = AL.reshape(-1) > 0.5
    SFb, NBb, MKb, Ab, LPb, ADb, RETb = SFb[keep], NBb[keep], MKb[keep], Ab[keep], LPb[keep], ADb[keep], RETb[keep]
    B = SFb.shape[0]
    pls, vls = [], []
    for _ in range(epochs):
        perm = torch.randperm(B, device=SFb.device)
        for i in range(0, B, minibatch):
            mb = perm[i:i + minibatch]
            mu, val = AT.apply_attn(params, SFb[mb], NBb[mb], MKb[mb], mm_dtype)
            ratio = (_logp(Ab[mb], mu, log_std) - LPb[mb]).exp()
            s1 = ratio * ADb[mb]; s2 = torch.clamp(ratio, 1 - clip, 1 + clip) * ADb[mb]
            pl = -torch.min(s1, s2).mean()
            vl = (val - RETb[mb]).pow(2).mean()
            loss = pl + vcoef * vl - ent * _entropy(log_std)
            opt.zero_grad(set_to_none=True); loss.backward(); opt.step()
            pls.append(float(pl.detach())); vls.append(float(vl.detach()))
    return sum(pls) / len(pls), sum(vls) / len(vls), float(REW.sum(0).mean())
