"""ppo_team — multi-agent PPO for the RECURRENT drone (policy_recur) vs the feedforward enemy
(policy_attn). Per-agent shared-team-reward (monstro ppo_enemy_attn) + done-masked GAE + tail bootstrap
(froggo, for mid-episode agent death). Only the drone is recurrent: game_loop threads its GRU latent h
across decisions; the rollout STORES the per-decision h_in and the update re-forwards with it DETACHED
(truncation-1 recurrent PPO — the GRU learns a good one-step latent update without full BPTT).

The drone acts recurrently EVERYWHERE (training side, frozen opponent, eval), so both sides' rollouts
thread h. Only the training side's transitions are recorded. Pre-allocated buffers (no torch.stack
transient — the VRAM win).
"""
import math

import torch

import policy_attn as AT
import policy_recur as RE
from env_drone import game_loop

LOG2PI = math.log(2 * math.pi)


def _logp(a, mu, log_std):
    std = log_std.exp()
    return (-0.5 * ((a - mu) / std) ** 2 - log_std - 0.5 * LOG2PI).sum(-1)


def _entropy(log_std):
    return (log_std + 0.5 * math.log(2 * math.e * math.pi)).sum()


def _gae(rew_team, val, done, v_last, gamma, lam):
    """Done-masked per-agent GAE. rew_team [T,P,N] (broadcast to every agent), val/done [T,P,N,A],
    v_last [P,N,A]. done[t]=1 => that agent's episode ended at t (no value flows across its death)."""
    T = rew_team.shape[0]
    rew = rew_team.unsqueeze(-1).expand_as(val)
    adv = torch.zeros_like(val)
    last = torch.zeros_like(val[0])
    for t in range(T - 1, -1, -1):                               # GAE-LOOP-OK (reverse recursion, offline)
        nonterm = 1.0 - done[t]
        v_next = val[t + 1] if t + 1 < T else v_last
        delta = rew[t] + gamma * v_next * nonterm - val[t]
        last = delta + gamma * lam * nonterm * last
        adv[t] = last
    return adv, adv + val


@torch.no_grad()
def rollout(env, train_side, dparams, dls, eparams, els, P, K_dec, mm_dtype=None):
    """Roll out K_dec decisions; the TRAINING side samples (records logp/val), the opponent plays its
    frozen mean. The drone is recurrent (game_loop threads h; h_in recorded when the drone trains).
    Returns per-decision buffers + v_last."""
    dstd, estd = dls.exp(), els.exp()
    H = dparams["We"].shape[1]
    store_dt = mm_dtype if mm_dtype is not None else torch.float32
    buf, step = {}, [0]

    def slot(name, sample, dt):
        if name not in buf:
            buf[name] = torch.zeros((K_dec, *sample.shape), dtype=dt, device=sample.device)
        return buf[name]

    def drone_fn(sf, tok, mk, h_in):
        mu, val, h_new = RE.apply_recur(dparams, sf, tok, mk, h_in, mm_dtype)
        if train_side == "drone":
            a = mu + dstd * torch.randn_like(mu)
            k = step[0]
            slot("sf", sf, store_dt)[k] = sf.to(store_dt)
            slot("tok", tok, store_dt)[k] = tok.to(store_dt)
            slot("mk", mk, store_dt)[k] = mk.to(store_dt)
            slot("h", h_in, store_dt)[k] = h_in.to(store_dt)
            slot("a", a, torch.float32)[k] = a
            slot("lp", val, torch.float32)  # ensure lp buffer allocated with right batch shape below
            buf["lp"][k] = _logp(a, mu, dls)
            slot("val", val, torch.float32)[k] = val
            return a, h_new
        return mu, h_new                                          # opponent: drone plays its mean

    def enemy_fn(sf, tok, mk):
        mu, val = AT.apply_attn(eparams, sf, tok, mk, mm_dtype)
        if train_side == "enemy":
            a = mu + estd * torch.randn_like(mu)
            k = step[0]
            slot("sf", sf, store_dt)[k] = sf.to(store_dt)
            slot("tok", tok, store_dt)[k] = tok.to(store_dt)
            slot("mk", mk, store_dt)[k] = mk.to(store_dt)
            slot("a", a, torch.float32)[k] = a
            slot("lp", val, torch.float32)
            buf["lp"][k] = _logp(a, mu, els)
            slot("val", val, torch.float32)[k] = val
            return a
        return mu

    def on_step(k, s, d_obs, e_obs, a_d, a_e, ns, r_d, r_e, done_d, done_e, h_in):
        kk = step[0]
        if train_side == "drone":
            r, done, valid = r_d, done_d, ((s["d_act"] > 0.5) & (s["d_alive"] > 0.5)).float()
        else:
            r, done, valid = r_e, done_e, (s["e_alive"] > 0.5).float()
        slot("rew", r, torch.float32)[kk] = r
        slot("done", done, torch.float32)[kk] = done
        slot("valid", valid, torch.float32)[kk] = valid
        step[0] = kk + 1

    s = game_loop(env, drone_fn, enemy_fn, P, K_dec, on_step=on_step, drone_recur=True, latent_h=H)
    T = step[0]
    # tail bootstrap value from the post-rollout obs of the TRAINING side
    if train_side == "drone":
        post = env.drone_obs(s)
        active = ((s["d_act"] > 0.5) & (s["d_alive"] > 0.5)).float()[..., None]
        _, v_last, _ = RE.apply_recur(dparams, *post, env._last_h * active, mm_dtype)
        alive_last = s["d_alive"]
    else:
        _, v_last = AT.apply_attn(eparams, *env.enemy_obs(s), mm_dtype)
        alive_last = s["e_alive"]
    sl = lambda k: buf[k][:T]
    out = {k: sl(k) for k in buf}
    out["v_last"] = v_last * alive_last
    return out


def ppo_step(env, train_side, dparams, dls, eparams, els, opt, P, K_dec,
             gamma=0.98, lam=0.95, clip=0.2, epochs=2, minibatch=262144, vcoef=0.5, ent=0.0,
             mm_dtype=None):
    """One PPO update for the training side. Returns (policy_loss, value_loss, mean_return, valid_frac)."""
    b = rollout(env, train_side, dparams, dls, eparams, els, P, K_dec, mm_dtype)
    log_std = dls if train_side == "drone" else els
    with torch.no_grad():
        adv, ret = _gae(b["rew"], b["val"], b["done"], b["v_last"], gamma, lam)
        keep = b["valid"].reshape(-1) > 0.5
        kept = adv.reshape(-1)[keep]
        adv = (adv - kept.mean()) / (kept.std() + 1e-6)
    Fs, Ft, K = b["sf"].shape[-1], b["tok"].shape[-1], b["tok"].shape[-2]
    SFb = b["sf"].reshape(-1, Fs)[keep]; TOKb = b["tok"].reshape(-1, K, Ft)[keep]; MKb = b["mk"].reshape(-1, K)[keep]
    Ab = b["a"].reshape(-1, b["a"].shape[-1])[keep]; LPb = b["lp"].reshape(-1)[keep]
    ADb = adv.reshape(-1)[keep]; RETb = ret.reshape(-1)[keep]
    Hb = b["h"].reshape(-1, b["h"].shape[-1])[keep] if train_side == "drone" else None
    B = SFb.shape[0]
    mean_ret = float(b["rew"].sum(0).mean())
    if B == 0:
        return 0.0, 0.0, mean_ret, 0.0
    pls, vls = [], []
    for _ in range(epochs):                                     # PPO-EPOCH-LOOP-OK (optimization, offline)
        perm = torch.randperm(B, device=SFb.device)
        for i in range(0, B, minibatch):                        # PPO-MB-LOOP-OK
            mb = perm[i:i + minibatch]
            if train_side == "drone":
                mu, val, _ = RE.apply_recur(dparams, SFb[mb], TOKb[mb], MKb[mb], Hb[mb].float(), mm_dtype)
            else:
                mu, val = AT.apply_attn(eparams, SFb[mb][:, None], TOKb[mb][:, None], MKb[mb][:, None], mm_dtype)
                mu, val = mu[:, 0], val[:, 0]
            ratio = (_logp(Ab[mb], mu, log_std) - LPb[mb]).exp()
            s1 = ratio * ADb[mb]
            s2 = torch.clamp(ratio, 1 - clip, 1 + clip) * ADb[mb]
            pl = -torch.min(s1, s2).mean()
            vl = (val - RETb[mb]).pow(2).mean()
            loss = pl + vcoef * vl - ent * _entropy(log_std)
            opt.zero_grad(set_to_none=True); loss.backward(); opt.step()
            pls.append(float(pl.detach())); vls.append(float(vl.detach()))
    return (sum(pls) / len(pls), sum(vls) / len(vls), mean_ret, float(b["valid"].mean()))
