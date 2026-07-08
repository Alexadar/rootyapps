"""PPO for the ENEMY — cooperative multi-agent, one shared per-monster policy (replaces the ES enemy, which
could not scale to the 31-dim obs). Mirrors ppo_torch, but:
  * the action is sampled PER MONSTER  a_e [P,N,M,2]  (the enemy MLP is applied per monster);
  * the reward is a SHARED TEAM scalar r_enemy [P,N] broadcast to every monster (monsters cooperate);
  * GAE is per-monster, and the update trains ONLY on alive monster-samples (dead slots masked out);
  * the PLAYER is FROZEN — its mean action is injected each tick (no grad), enemy action injected via a
    closure so the compiled _core is untouched (mirrors how step_pa injects the player action).
Value head V(monster_obs)->scalar predicts the team return from a single monster's view (per-monster critic).
Deployed model = the mean policy MLP (same {sizes,w,b} JSON as the ES enemy) — parity-safe, value head dropped.

Per-monster blows the sample count up by M, so the enemy runs a SMALLER env-group than the player (per-monster
already yields plenty of samples). The GAE python loop is training-side (not the sim hot path), same as ppo_torch."""
import math
import torch
import policy_torch as P

LOG2PI = math.log(2 * math.pi)


def init_value(device, seed, in_dim, H=64):
    """Per-monster critic V(obs)->scalar. Leaf params (grad); training only, dropped at save."""
    base = P.init_mlp([in_dim, H, H, 1], device=device, seed=seed)
    return [(W.clone().detach().requires_grad_(True), b.clone().detach().requires_grad_(True)) for W, b in base]


def value_params_flat(vparams):
    return [w for wb in vparams for w in wb]


def _logp(a, mu, log_std):
    std = log_std.exp()
    return (-0.5 * ((a - mu) / std) ** 2 - log_std - 0.5 * LOG2PI).sum(-1)


def _entropy(log_std):
    return (log_std + 0.5 * math.log(2 * math.e * math.pi)).sum()


@torch.no_grad()
def rollout(env, ticks, eparams, log_std, vparams, player, AT, P_group, mm_dtype=None):
    """Enemy sampled per monster, player FROZEN (mean action injected). Enemy obs computed on `s` (pre-step,
    mirroring the player). Returns obs,a,logp,team_rew,val,alive stacked over T. Enemy action injected into
    _core via a closure -> the compiled core is unchanged (it just returns the captured tensor)."""
    pf = lambda b: AT.apply_attn(player, b[0], b[1], b[2], mm_dtype)[0]
    s = env.reset(P_group)
    obs_l, a_l, lp_l, r_l, v_l, al_l = [], [], [], [], [], []
    for t in range(1, ticks + 1):
        obs = env.enemy_obs_vec(s)                                  # [P,N,M,eobs]
        mu = P.apply_enemy(eparams, obs, mm_dtype)                  # [P,N,M,2]
        a = mu + log_std.exp() * torch.randn_like(mu)
        alive = ((s["mon_act"] > 0.5) & (s["mon_hp"] > 0)).float()  # [P,N,M]
        obs_l.append(obs); a_l.append(a); lp_l.append(_logp(a, mu, log_std))
        v_l.append(P.apply_enemy(vparams, obs, mm_dtype).squeeze(-1)); al_l.append(alive)
        a_player = pf(env.player_set_obs(s))                        # frozen player, mean action
        s, _r_p, r_e, _ = env.step_pa(s, t, a_player, lambda _o: a)  # inject enemy action a
        r_l.append(r_e)                                             # [P,N] shared team reward
    return (torch.stack(obs_l), torch.stack(a_l), torch.stack(lp_l),
            torch.stack(r_l), torch.stack(v_l), torch.stack(al_l))


def _gae(team_rew, val, gamma, lam):
    """team_rew [T,P,N] (shared) -> broadcast to M; val [T,P,N,M]. Per-monster GAE; V_T=0 (full episodes)."""
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


def ppo_step(env, ticks, eparams, log_std, vparams, opt, player, AT, P_group,
             gamma=0.99, lam=0.95, clip=0.2, epochs=4, minibatch=262144, vcoef=0.5, ent=0.003, mm_dtype=None):
    """One PPO update of the enemy vs the frozen player. Returns (policy_loss, value_loss, mean_team_return)."""
    obs, a, lp_old, team_rew, val, alive = rollout(env, ticks, eparams, log_std, vparams, player, AT, P_group, mm_dtype)
    with torch.no_grad():
        adv, ret = _gae(team_rew, val, gamma, lam)
        m = alive > 0.5
        adv = (adv - adv[m].mean()) / (adv[m].std() + 1e-6)         # normalize over ALIVE samples only
    O = obs.reshape(-1, obs.shape[-1]); A = a.reshape(-1, a.shape[-1])
    LP = lp_old.reshape(-1); AD = adv.reshape(-1); RET = ret.reshape(-1); keep = alive.reshape(-1) > 0.5
    O, A, LP, AD, RET = O[keep], A[keep], LP[keep], AD[keep], RET[keep]   # train only on alive monster-samples
    B = O.shape[0]
    pls, vls = [], []
    for _ in range(epochs):
        perm = torch.randperm(B, device=O.device)
        for i in range(0, B, minibatch):
            mb = perm[i:i + minibatch]
            mu = P.apply_mlp(eparams, O[mb], mm_dtype)
            ratio = (_logp(A[mb], mu, log_std) - LP[mb]).exp()
            s1 = ratio * AD[mb]; s2 = torch.clamp(ratio, 1 - clip, 1 + clip) * AD[mb]
            pl = -torch.min(s1, s2).mean()
            vl = (P.apply_mlp(vparams, O[mb], mm_dtype).squeeze(-1) - RET[mb]).pow(2).mean()
            loss = pl + vcoef * vl - ent * _entropy(log_std)
            opt.zero_grad(set_to_none=True); loss.backward(); opt.step()
            pls.append(float(pl.detach())); vls.append(float(vl.detach()))
    return sum(pls) / len(pls), sum(vls) / len(vls), float(team_rew.sum(0).mean())
