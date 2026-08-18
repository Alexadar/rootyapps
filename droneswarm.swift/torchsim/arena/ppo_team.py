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
    """Log-probability of action `a` under a DIAGONAL Gaussian policy N(mu, std), std=exp(log_std).
    log N(a;mu,std) = -0.5*((a-mu)/std)^2 - log_std - 0.5*log(2pi), summed over the action dims (-1)."""
    std = log_std.exp()                                          # per-dim standard deviation
    return (-0.5 * ((a - mu) / std) ** 2 - log_std - 0.5 * LOG2PI).sum(-1)   # [..] joint log-prob over action dims


def _entropy(log_std):
    """Differential entropy of a diagonal Gaussian: 0.5*log(2*pi*e*std^2) = log_std + 0.5*log(2*pi*e), summed
    over action dims. Depends ONLY on log_std (state-independent here) -> acts as an exploration floor."""
    return (log_std + 0.5 * math.log(2 * math.e * math.pi)).sum()


def _gae(rew_team, val, done, v_last, gamma, lam):
    """Done-masked per-agent Generalized Advantage Estimation (Schulman 2016). rew_team [T,P,N] (the shared
    TEAM reward, broadcast to every agent), val/done [T,P,N,A], v_last [P,N,A] (post-rollout bootstrap value).
    done[t]=1 => that agent's episode ended at t, so no value/advantage flows ACROSS its death. Returns
    (advantages, value-targets = advantages + values)."""
    T = rew_team.shape[0]                                        # rollout length (decisions)
    rew = rew_team.unsqueeze(-1).expand_as(val)                 # [T,P,N,A] broadcast the team reward to each agent
    adv = torch.zeros_like(val)                                 # [T,P,N,A] advantage accumulator
    last = torch.zeros_like(val[0])                            # [P,N,A] running GAE term (carried backward in time)
    for t in range(T - 1, -1, -1):                              # GAE-LOOP-OK: reverse-time recursion (offline, no grad)
        nonterm = 1.0 - done[t]                                # 0 where the agent died this step -> cuts the bootstrap
        v_next = val[t + 1] if t + 1 < T else v_last           # next-step value (or the tail bootstrap at the horizon)
        delta = rew[t] + gamma * v_next * nonterm - val[t]     # TD residual: r + gamma*V(s') - V(s)
        last = delta + gamma * lam * nonterm * last            # GAE(lambda): delta + discounted decayed future advantage
        adv[t] = last                                          # store this step's advantage
    return adv, adv + val                                       # value target = advantage + baseline value


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

    def drone_fn(sf, tok, mk, ef, em, dm, dpxy, h_in):
        mu, val, h_new, a_hard = RE.apply_recur(dparams, sf, tok, mk, ef, em, dm, dpxy, h_in, mm_dtype)
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
            return a, h_new, a_hard
        return mu, h_new, a_hard                                  # opponent: drone plays its mean + its assignment

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

    s = game_loop(env, drone_fn, enemy_fn, P, K_dec, on_step=on_step, drone_recur=True, latent_h=H,
                  early_break=False)                            # training: no per-decision GPU->CPU sync (A1)
    T = step[0]
    # tail bootstrap value from the post-rollout obs of the TRAINING side
    if train_side == "drone":
        post = env.drone_obs(s)
        active = ((s["d_act"] > 0.5) & (s["d_alive"] > 0.5)).float()[..., None]
        _, v_last, _, _ = RE.apply_recur(dparams, *post, env._last_h * active, mm_dtype)
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
            if train_side == "drone":                            # (dead path: the drone trains via SAPO, not ppo_step)
                mu, val, _, _ = RE.apply_recur(dparams, SFb[mb], TOKb[mb], MKb[mb], Hb[mb].float(), mm_dtype)
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


def sapo_step(env, dparams, dls, eparams, els, dopt, log_alpha, aopt, P, H_dec, K_dec=80, dtarget=None,
              gamma=0.99, lam=0.95, tau=0.005, target_entropy=-2.0, grad_clip=0.5, vcoef=0.5, mm_dtype=None):
    """SAPO for the DRONE (Xing & Bhardwaj, "Stabilizing RL in Differentiable Multiphysics Simulation",
    ICLR'25, arXiv:2412.12089) — the 2026-SOTA successor to SHAC that trains FROM SCRATCH in one phase (no
    PPO bootstrap). It is a windowed analytic-gradient BPTT (SHAC-style) made MAXIMUM-ENTROPY:
      (1) the entropy bonus is folded INTO the discounted H-step return (paper Eq.18), not tacked on as a
          separate flat term -> exploration is discounted consistently with reward, which is what stabilises
          a random init through the early flat-reward regime;
      (2) the critic regresses the SOFT TD(lambda) value (Eq.20): each step's reward carries +alpha*H so the
          value head learns the entropy-augmented return the actor is actually maximising;
      (3) alpha is AUTO-TUNED SAC-style (Eq.21) toward a target entropy -> no hand-set exploration schedule;
          alpha rises when the policy is too deterministic (H < target) and decays as it sharpens.
    The rest is standard analytic-gradient BPTT: reparameterised action, EMA target net for the value bootstrap,
    truncated BPTT at window seams, frozen mean-playing enemy. Returns (actor_loss, value_loss, ret, valid)."""
    Hh = dparams["We"].shape[1]                              # GRU latent width (drone recurrent hidden size)
    dev = dls.device                                         # everything lives on the policy's device (cuda/cpu)
    if dtarget is None:                                      # standalone fallback (smoke/tests): a local EMA target.
        dtarget = {kk: v.detach().clone() for kk, v in dparams.items()}   # slow-tracking copy for the value bootstrap
    s = env.reset(P)                                         # fresh episode: state dict of [P,N,...] tensors
    h = torch.zeros(P, env.N, env.D, Hh, device=dev)         # per-drone GRU latent, zero at episode start
    a_sum = c_sum = r_sum = v_sum = 0.0; nw = 0              # running means over windows (for logging)
    k = 0                                                    # global decision index (0..K_dec-1), threads the schedule
    while k < K_dec:                                         # SAPO-EPISODE-LOOP-OK: walk the episode window-by-window
        w = min(H_dec, K_dec - k)                            # this window's length (last window may be short)
        dstd = dls.exp()                                     # action std = exp(log_std); RECOMPUTE per window so its
        #                                                      graph is freed by this window's backward (else 2nd-backward)
        H_ent = _entropy(dls)                                # per-step differential entropy (grad ON wrt log_std -> the
        #                                                      max-ent objective drives std; state-independent -> one scalar)
        alpha = log_alpha.exp()                              # current entropy temperature (auto-tuned below); >0 by exp
        disc = 1.0                                           # running discount gamma^t within the window
        ret = torch.zeros(P, env.N, device=dev)             # [P,N] differentiable ENTROPY-AUGMENTED window return (grad ON)
        vals, rews, alives = [], [], []                     # per-step value preds / rewards / alive-masks (for the critic)
        # ---- roll the window forward WITH gradient (the differentiable-sim BPTT) ----
        for _ in range(w):                                  # SAPO-WINDOW-LOOP-OK: the short BPTT chain (grad flows)
            do = env.drone_obs(s)                            # perceive (self-feat + tokens + mask), pure fn of state
            act = ((s["d_act"] > 0.5) & (s["d_alive"] > 0.5)).float()   # [P,N,D] 1 = drone launched AND alive
            mu, val, h, assign = RE.apply_recur(dparams, *do, h * act[..., None], mm_dtype)   # policy: action, value, latent, target assignment
            a_d = mu + dstd * torch.randn_like(mu)           # REPARAMETERIZED (pathwise) action: grad flows through mu AND dstd
            with torch.no_grad():                            # the enemy is the FROZEN opponent -> no grad, plays its mean
                e_mu, _ = AT.apply_attn(eparams, *env.enemy_obs(s), mm_dtype)
            vals.append(val); alives.append(act)             # stash value pred + alive mask for the critic target below
            s, r_d, _, _, _ = env.step_dec(s, k, a_d, e_mu, assign); k += 1   # advance the DIFFERENTIABLE sim one decision (5 ticks)
            rews.append(r_d)                                 # [P,N] team reward this decision (grad flows via smooth terms)
            ret = ret + disc * (r_d + alpha.detach() * H_ent)   # Eq.18: accumulate gamma^t*(r_t + alpha*H_t); alpha frozen
            #                                                      here (trained by alpha_loss), H_ent carries the std grad
            disc = disc * gamma                              # bump the discount for the next step
        # ---- terminal SOFT value bootstrap V(s_w) from the EMA TARGET net ----
        # Grad flows through the INPUT state s_w (shaped by the window's actions), NOT the target's frozen params ->
        # SHAC's long-horizon gradient. V is the SOFT value (the critic below is trained on entropy-augmented returns).
        do = env.drone_obs(s)                                # obs at the window-END state
        actf = ((s["d_act"] > 0.5) & (s["d_alive"] > 0.5)).float()          # alive mask at window end
        _, v_last, _, _ = RE.apply_recur(dtarget, *do, (h * actf[..., None]).detach(), mm_dtype)   # target-net value [P,N,D]
        v_term = (v_last * actf).sum(-1) / (actf.sum(-1) + 1e-6)            # [P,N] alive-mean terminal value (safe denom)
        # ---- ACTOR loss: MAXIMISE (entropy-augmented window return + discounted terminal value) -> minimise negative ----
        actor_loss = -((ret + disc * v_term).mean())        # entropy already folded into `ret` (Eq.17 max-ent objective)
        # ---- CRITIC target: SOFT TD(lambda) return-to-go (Eq.20), computed offline (no grad), regressed vs the LIVE V ----
        V = torch.stack(vals)                                # [w,P,N,D] live value preds (grad ON -> critic learns)
        A = torch.stack(alives)                              # [w,P,N,D] alive masks
        R = torch.stack(rews)                                # [w,P,N] per-step team rewards
        with torch.no_grad():                                # targets are constants for the regression -> detach everything
            vt = v_term.detach()                             # [P,N] target-net terminal value (bootstraps past window end)
            Vm = (V * A).sum(-1) / (A.sum(-1) + 1e-6)        # [w,P,N] per-step alive-mean value (intermediate bootstraps)
            Rs = R + alpha.detach() * H_ent.detach()         # [w,P,N] SOFT reward r_t + alpha*H_t -> critic learns soft value
            # SOFT TD(lambda) return-to-go, VECTORIZED (no scan). Triangular-matrix unroll, but the
            # per-step adjusted reward a_t uses the entropy-augmented reward Rs (this is the ONLY change from SHAC's critic).
            vnext = torch.cat([Vm[1:], vt[None]], 0)         # [w,P,N] bootstrap value at t+1 (last step uses terminal vt)
            a = Rs + gamma * (1.0 - lam) * vnext             # [w,P,N] per-step adjusted soft reward a_t
            gl = gamma * lam                                 # geometric ratio of the lambda-return recursion
            idx = torch.arange(w, device=dev); dk = idx[None, :] - idx[:, None]      # [w,w] j - t
            M = (dk >= 0).float() * (gl ** dk.clamp(min=0).float())                 # [w,w] triangular (gl)^{j-t}, j>=t
            tail = (gl ** (w - idx).float())[:, None, None] * vt[None]              # [w,P,N] (gl)^{w-t} * terminal value
            targets = torch.einsum("tj,jpn->tpn", M, a) + tail                     # [w,P,N] soft lambda-return (detached)
        crit = (((V - targets[..., None]) ** 2) * A).sum() / (A.sum() + 1e-6)   # masked MSE(V, soft lambda-return), alive only
        # ---- one combined gradient step (actor via the diff sim, critic via regression on the shared trunk) ----
        loss = actor_loss + vcoef * crit                     # vcoef balances the value-regression against the actor
        dopt.zero_grad(set_to_none=True); loss.backward()    # backprop: actor through the sim, critic to the value head
        torch.nn.utils.clip_grad_norm_(RE.opt_params(dparams, dls), grad_clip)   # clip: tame exploding contact gradients
        dopt.step()                                          # apply the update to the LIVE drone params
        # ---- AUTO-ALPHA (Eq.21): drag the entropy toward target_entropy. When H < target the policy is too
        # deterministic -> (H-target)<0 -> minimising log_alpha*(H-target) pushes log_alpha (hence alpha) UP, and
        # vice-versa. No outer minus: this is the SAC dual objective rewritten for entropy H (= -log_pi). ----
        alpha_loss = log_alpha * (H_ent.detach() - target_entropy)
        aopt.zero_grad(set_to_none=True); alpha_loss.backward(); aopt.step()   # one-parameter dual ascent on the temperature
        with torch.no_grad():                                # EMA target-net update: dtarget <- (1-tau)*dtarget + tau*dparams
            tp = list(dtarget.values())                      # target param TensorList (a slow-moving copy of the drone params)
            sp = [dparams[kk].detach() for kk in dtarget]    # matching live params (same dict key order)
            torch._foreach_mul_(tp, 1.0 - tau)               # fused over all params: tp *= (1-tau)
            torch._foreach_add_(tp, sp, alpha=tau)           # fused: tp += tau*dparams  (stabilises the value bootstrap)
        s = {kk: v.detach() for kk, v in s.items()}          # TRUNCATED BPTT: cut the graph at the window seam (bound memory)
        h = h.detach()                                       # ...also detach the recurrent latent carried to the next window
        # accumulate logging stats ON-GPU (tensor adds, NO per-window .item()) -> the GPU never stalls between windows.
        a_sum = a_sum + actor_loss.detach(); c_sum = c_sum + crit.detach()
        r_sum = r_sum + ret.mean().detach(); v_sum = v_sum + A.mean().detach(); nw += 1
    inv = 1.0 / max(nw, 1)                                    # window count -> mean
    return float(a_sum * inv), float(c_sum * inv), float(r_sum * inv), float(v_sum * inv)   # single host sync here
