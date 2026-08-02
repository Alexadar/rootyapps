"""Co-evolution: PPO player vs ES world-generator, equilibrium at 62% win.

Monstro's player/enemy recipe with the enemy replaced by a CALIBRATING world
generator (dealer network + 18 theta knobs, one ES genome). Its fitness is
not "beat the player" but "hold EVERY skill group at 62% win" — the groups
span the player league AND noisy (temperature-sampled) variants of the
current player, so the generator must INFER session difficulty from game
state (its dealer already sees fans/money/week/roster) and adapt per session.
That per-group objective is what makes the artifact an adaptive levelgen
model shippable into player sessions, not a fixed difficulty table.

Anti-collapse (monstro lessons): fixed asymmetric cadence (6 PPO iters : 2 ES
gens), FIFO leagues both sides + a permanent bank-world anchor block, fixed
entropy coef (never annealed), low player LR, final-round artifact (never
keep-best / best-of-pop — winner's curse), frozen references (bank world;
round-0 player), first-completed-episode-only win counting (length-bias — a
generator-controllable hacking channel otherwise), 480-week horizons for
fitness after round 20 and for every gate (surviving IS a win at 480).

Usage: python3 coevolve.py [--rounds 30] [--budget-min 100] [--out runs/coevolve]
"""

import argparse
import json
import math
import time
from collections import deque
from pathlib import Path

import torch

import world_config as W
from env_producer import ProducerEnv
import obs_producer as OB
import policy_producer as PP
import dealer as DL
from train_ppo import collect, gae, ppo_update, evaluate
from train_dealer_es import make_text_fit_sampler

TARGET = 0.62
GENOME_D = DL.N_PARAMS + W.N_KNOBS


# ---------- genome: dealer flat params + theta in sigmoid z-space ----------

def sigma_vec(device):
    return torch.cat([torch.full((DL.N_PARAMS,), 0.05),
                      torch.full((W.N_KNOBS,), 0.15)]).to(device)


def theta_from_z(z):
    """z [..., K] -> dict of knob tensors (sigmoid box reparam)."""
    out = {}
    for i, k in enumerate(W.KNOB_NAMES):
        _, lo, hi = W.GEN_KNOBS[k]
        out[k] = lo + torch.sigmoid(z[..., i]) * (hi - lo)
    return out


def z_default(device):
    zs = []
    for k in W.KNOB_NAMES:
        d, lo, hi = W.GEN_KNOBS[k]
        p = min(max((d - lo) / (hi - lo), 1e-4), 1 - 1e-4)
        zs.append(math.log(p / (1 - p)))
    return torch.tensor(zs, device=device)


def warm_start_genome(device):
    g = torch.zeros(1, GENOME_D, device=device)
    ck = Path(__file__).parent / "runs/dealer_v1/dealer_best.pt"
    if ck.exists():
        g[0, :DL.N_PARAMS] = torch.load(ck, map_location=device)["mean"][0].to(device)
        print(f"dealer warm start <- {ck}")
    else:
        g[0, :DL.N_PARAMS] = DL.init_dealer(1, device=device)[0]
        print("dealer cold start (bank-like init)")
    g[0, DL.N_PARAMS:] = z_default(device)
    return g


def decode_theta_per_env(genomes, slots, device):
    """genomes [E, GENOME_D] -> theta dict of [E*slots] tensors."""
    th = theta_from_z(genomes[:, DL.N_PARAMS:])
    return {k: th[k].repeat_interleave(slots).to(device) for k in W.KNOB_NAMES}


# ---------- dealt-content probes (hacking watch, free at the source) ----------

class Probes:
    def __init__(self, pop, device):
        self.pop, self.device = pop, device
        self.reset()

    def reset(self):
        d = self.device
        self.n_deals = torch.zeros(self.pop, device=d)
        self.stat_sum = torch.zeros(self.pop, 9, device=d)
        self.stat_sq = torch.zeros(self.pop, 9, device=d)
        self.genre_hist = torch.zeros(self.pop, W.N_GENRES, device=d)

    def push(self, fields, pop, slots):
        st = fields["stats"].view(pop, slots * 2, 9)
        self.n_deals += slots * 2
        self.stat_sum += st.sum(1)
        self.stat_sq += (st ** 2).sum(1)
        g = torch.nn.functional.one_hot(fields["genre"].view(pop, slots * 2), W.N_GENRES).float()
        self.genre_hist += g.sum(1)

    def summary(self):
        n = self.n_deals.clamp(min=1).unsqueeze(1)
        mu = self.stat_sum / n
        var = (self.stat_sq / n - mu ** 2).clamp(min=0)
        sigma = var.sqrt().mean(1)                                  # [E] mean stat sigma
        p = self.genre_hist / self.genre_hist.sum(1, keepdim=True).clamp(min=1)
        gent = -(p * (p + 1e-9).log()).sum(1)                       # [E] genre entropy (nats)
        return {"stat_mu": mu.mean(1), "stat_sigma": sigma, "genre_ent": gent}


def probed_source(base_src, probes, pop, slots):
    def src(env_mask):
        out = base_src(env_mask)
        probes.push(out, pop, slots)
        return out
    return src


# ---------- generator fitness: per-skill-group calibration ----------

@torch.no_grad()
def eval_gen_pop(genomes, groups_def, slots, weeks, seed, device,
                 sampler, max_steps=None):
    """genomes [E,GENOME_D]; groups_def = list of (player_params, temperature|None)
    — slots are partitioned equally across groups; None temp = argmax.
    Returns fitness [E], per-group win [E,G], med first-episode weeks [E], probes."""
    E = genomes.shape[0]
    G = len(groups_def)
    per = slots // G
    n = E * slots
    if max_steps is None:
        max_steps = weeks * 9 + 400

    env = ProducerEnv(n, device=device, seed=seed, max_weeks=weeks + 8,
                      obs_theta=True, bank_size=4096, victory_weeks=weeks)
    env.theta = decode_theta_per_env(genomes, slots, device)
    env.refresh_pay_mult()
    state = DL.DealerState(n, device)
    probes = Probes(E, device)
    base = DL.make_candidate_source(genomes[:, :DL.N_PARAMS].contiguous(), E, slots,
                                    env, state, torch.full((n,), TARGET, device=device), sampler)
    env.candidate_source = probed_source(base, probes, E, slots)
    raw_reset = env.reset
    env.reset = lambda mask=None: (state.reset(mask if mask is not None else
                                               torch.ones(n, dtype=torch.bool, device=device)),
                                   raw_reset(mask))[-1]
    env.reset()

    rng = torch.Generator(device=device).manual_seed(seed + 5)
    rows_per_group = [torch.arange(n, device=device).view(E, G, per)[:, g].reshape(-1)
                      for g in range(G)]
    act = torch.zeros(n, dtype=torch.long, device=device)
    wins = torch.zeros(n, device=device)
    eps = torch.zeros(n, device=device)
    ep_wk = torch.zeros(n, device=device)

    for _ in range(max_steps):
        sf, tk, pr = OB.build_obs(env)
        mask = env.legal_mask()
        for g, (pparams, temp) in enumerate(groups_def):
            rows = rows_per_group[g]
            logits, _ = PP.apply_policy(pparams, sf[rows], tk[rows], pr[rows], mask[rows])
            if temp is None:
                act[rows] = logits.argmax(-1)
            else:
                probs = torch.softmax(logits / temp, -1)
                act[rows] = torch.multinomial(probs, 1, generator=rng).squeeze(1)
        wk_before = env.s["week"].clone()
        env.step(act)
        done, out = env.s["done"], env.s["outcome"]
        first = done & (eps < 1)                        # first-episode-only (C2)
        wins += (first & ((out == 1) | (out == 2))).float()
        ep_wk += first.float() * wk_before
        eps += first.float()
        env.reset(done)
        if bool((eps.view(E, slots).min(1).values >= 1).all()):
            break

    wr_group = wins.view(E, G, per).mean(-1)                        # [E,G]
    med_wk = ep_wk.view(E, slots).median(1).values
    ps = probes.summary()
    fitness = (wr_group - TARGET).abs().mean(1) \
        + 0.02 * torch.relu(24.0 - med_wk) \
        + 0.02 * torch.relu(6.0 - ps["stat_sigma"]) \
        + 0.05 * torch.relu(1.0 - ps["genre_ent"]) \
        + 0.01 * genomes[:, DL.N_PARAMS:].pow(2).mean(1)
    terms = {"win": float((wr_group - TARGET).abs().mean(1).mean()),
             "med_wk": float(med_wk.float().mean()),
             "stat_sigma": float(ps["stat_sigma"].mean()),
             "genre_ent": float(ps["genre_ent"].mean()),
             "z_l2": float(genomes[:, DL.N_PARAMS:].pow(2).mean())}
    return fitness, wr_group, med_wk, terms


# ---------- player-phase league env (anchor + FIFO-7 generator blocks) ----------

class LeagueEnv:
    BLOCKS = 8

    def __init__(self, n, device, seed, sampler, train_weeks, victory_weeks=None):
        assert n % self.BLOCKS == 0
        self.n, self.device = n, device
        self.per = n // self.BLOCKS
        self.env = ProducerEnv(n, device=device, seed=seed, max_weeks=train_weeks,
                               obs_theta=True, victory_weeks=victory_weeks)
        self.state = DL.DealerState(n, device)
        self.flat = torch.zeros(self.BLOCKS, DL.N_PARAMS, device=device)
        diff = torch.full((n,), TARGET, device=device)
        base = DL.make_candidate_source(self.flat, self.BLOCKS, self.per,
                                        self.env, self.state, diff, sampler)

        def source(env_mask):
            out = base(env_mask)
            bank = self.env._draw_artists((n, 2))
            for k in out:                                # block 0 = bank anchor
                out[k][:self.per] = bank[k][:self.per]
            return out
        self.env.candidate_source = source

        raw_reset = self.env.reset
        st = self.state

        def reset_hook(mask=None):
            st.reset(mask if mask is not None
                     else torch.ones(n, dtype=torch.bool, device=device))
            return raw_reset(mask)
        self.env.reset = reset_hook

    def install(self, slot, genome):
        """slot in 1..7; block 0 (anchor: bank + default theta) is permanent."""
        assert 1 <= slot < self.BLOCKS
        self.flat[slot] = genome[:DL.N_PARAMS]
        th = theta_from_z(genome[DL.N_PARAMS:])
        rows = slice(slot * self.per, (slot + 1) * self.per)
        for k in W.KNOB_NAMES:
            self.env.theta[k][rows] = th[k]
        self.env.refresh_pay_mult()
        m = torch.zeros(self.n, dtype=torch.bool, device=self.device)
        m[rows] = True
        self.env.reset(m)                                # kill in-flight episodes


# ---------- round-gate: fresh seeds, per-skill-group, full length ----------

@torch.no_grad()
def gate_eval(gen_mean, player, old_player, seed, device, sampler,
              per_group=1536, weeks=480):
    groups = [(player, None), (player, 1.0), (old_player, None)]
    fitness, wr_group, med_wk, terms = eval_gen_pop(
        gen_mean, groups, per_group * len(groups), weeks, seed, device, sampler)
    return {"wr_argmax": float(wr_group[0, 0]), "wr_sampled": float(wr_group[0, 1]),
            "wr_old": float(wr_group[0, 2]), "med_weeks": float(med_wk[0]),
            "skill_gap": float(wr_group[0, 0] - wr_group[0, 1]), "terms": terms}


def snap_player(params):
    return [(Wm.detach().clone(), b.detach().clone()) for Wm, b in params]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--rounds", type=int, default=30)
    ap.add_argument("--budget-min", type=float, default=100)
    ap.add_argument("--ppo-iters", type=int, default=6)
    ap.add_argument("--es-gens", type=int, default=2)
    ap.add_argument("--es-pop", type=int, default=48)      # antithetic pairs = pop/2
    ap.add_argument("--es-slots", type=int, default=384)   # episodes per genome
    ap.add_argument("--es-lr", type=float, default=0.03)
    ap.add_argument("--sigma-scale", type=float, default=1.0,
                    help="shrink ES sigma when the win-rate cliff is narrower than "
                         "the noise (smoothed-vs-deployed objective divergence)")
    ap.add_argument("--envs", type=int, default=16384)
    ap.add_argument("--rollout", type=int, default=64)
    ap.add_argument("--lr", type=float, default=1.5e-4)
    ap.add_argument("--ent", type=float, default=0.005)    # FIXED, never annealed
    ap.add_argument("--gamma", type=float, default=0.997)
    ap.add_argument("--train-weeks", type=int, default=208)
    ap.add_argument("--full-after", type=int, default=20)  # gen fitness 480wk after this round
    ap.add_argument("--victory-weeks", type=int, default=None,
                    help="compressed survive-N-weeks-wins horizon for CALIBRATION "
                         "(fitness+gate+player env); validation must use true 480")
    ap.add_argument("--player", default="runs/v2_ladder/best.json")
    ap.add_argument("--device", default="cuda")
    ap.add_argument("--seed", type=int, default=0)
    ap.add_argument("--out", default="runs/coevolve")
    ap.add_argument("--resume", default=None, help="ckpt_rNN.pt to resume both sides from")
    args = ap.parse_args()

    dev = args.device
    here = Path(__file__).parent
    outdir = here / args.out
    outdir.mkdir(parents=True, exist_ok=True)
    sampler = make_text_fit_sampler(dev)

    # player (warm start, one Adam forever)
    if args.resume:
        ck = torch.load(here / args.resume, map_location=dev)
        player = [(Wm.to(dev).requires_grad_(True), b.to(dev).requires_grad_(True))
                  for Wm, b in ck["player"]]
        meta = ck["meta"]
        gen_mean = ck["gen_mean"].to(dev)
        if gen_mean.shape[1] != GENOME_D:
            # dealer architecture changed (e.g. qkv memory upgrade): keep the
            # theta z-tail, fresh-init the dealer half (bank-like output biases)
            old_theta = gen_mean[0, -W.N_KNOBS:].clone()
            gen_mean = torch.zeros(1, GENOME_D, device=dev)
            gen_mean[0, :DL.N_PARAMS] = DL.init_dealer(1, device=dev)[0]
            gen_mean[0, DL.N_PARAMS:] = old_theta
            print(f"genome dim changed ({ck['gen_mean'].shape[1]} -> {GENOME_D}): "
                  f"theta carried over, dealer fresh-initialized")
        print(f"resumed both sides from {args.resume} (round {ck['round']})")
    else:
        player, meta = PP.load(here / args.player, device=dev)
        player = [(Wm.requires_grad_(True), b.requires_grad_(True)) for Wm, b in player]
        gen_mean = warm_start_genome(dev)
    assert meta.get("obs_theta"), "co-evolution expects the theta-aware player"
    opt = torch.optim.Adam(PP.opt_params(player), lr=args.lr)
    player_ref = snap_player(player)                       # frozen round-0 reference
    sig = sigma_vec(dev) * args.sigma_scale
    g_cpu = torch.Generator().manual_seed(args.seed + 3)

    # leagues
    gen_league = deque(maxlen=7)
    player_league = deque(maxlen=6)
    gen_league.append(gen_mean[0].clone())
    player_league.append(snap_player(player))

    lenv = LeagueEnv(args.envs, dev, args.seed, sampler, args.train_weeks,
                     victory_weeks=args.victory_weeks)
    for slot in range(1, LeagueEnv.BLOCKS):
        lenv.install(slot, gen_league[-1])

    rng = torch.Generator(device=dev).manual_seed(args.seed + 9)
    log_path = outdir / "coevolve_log.jsonl"
    band_hits = 0
    ref_wins = deque(maxlen=5)
    gate_err = None    # proportional ES damping: full step far from target,
    t0 = time.time()   # quarter step near the band (anti-ping-pong)

    for rnd in range(1, args.rounds + 1):
        t_rnd = time.time()
        # ---------------- player phase ----------------
        pstats = []
        for _ in range(args.ppo_iters):
            panel = {k: 0.0 for k in ("terminal", "shaping", "step")}
            for k in ("win-fans", "win-years", "bankrupt", "rep", "rejects", "timeout"):
                panel[k] = 0
            batch = collect(lenv.env, player, args.rollout, args.gamma, rng, panel)
            with torch.no_grad():
                ADV, RET = gae(batch[7], batch[6], batch[8], args.gamma, 0.95)
                ADV = (ADV - ADV.mean()) / (ADV.std() + 1e-6)
            pl, vl, ent = ppo_update(player, opt, tuple(batch) + (ADV, RET),
                                     0.2, 4, 16384, 0.5, args.ent)
            eps_n = sum(panel[k] for k in ("win-fans", "win-years", "bankrupt",
                                           "rep", "rejects", "timeout"))
            pstats.append({"pl": round(pl, 4), "vl": round(vl, 3), "ent": round(ent, 3),
                           "eps": eps_n,
                           "win": round((panel["win-fans"] + panel["win-years"]) / max(eps_n, 1), 3)})
        player_league.append(snap_player(player))

        # ---------------- generator phase ----------------
        weeks = args.victory_weeks if args.victory_weeks \
            else (480 if rnd > args.full_after else 208)
        # skill groups: CURRENT player weighted 3x (aligns ES fitness with the
        # gate metric — the current-argmax rate is what must sit at 62%), two
        # older league members, + noisy current (tau 1.0, 1.5) for adaptivity
        lg = list(player_league)
        older = [lg[max(0, len(lg) - 3)], lg[0]]
        members = [lg[-1], lg[-1], lg[-1], lg[-1]] + older
        groups = [(m, None) for m in members] + [(lg[-1], 1.0), (lg[-1], 1.5)]
        gstats = []
        for gi in range(args.es_gens):
            half = args.es_pop // 2
            noise = torch.randn(half, GENOME_D, generator=g_cpu).to(dev) * sig
            noise = torch.cat([noise, -noise])
            fitness, wr_group, med_wk, terms = eval_gen_pop(
                gen_mean + noise, groups, args.es_slots, weeks,
                seed=100_000 * rnd + gi, device=dev, sampler=sampler)
            shaped = (fitness.argsort().argsort().float() / (args.es_pop - 1)) - 0.5
            grad = (shaped.unsqueeze(1) * noise / sig ** 2).mean(0)
            lr_eff = args.es_lr * (min(1.0, max(0.25, abs(gate_err) / 0.15))
                                   if gate_err is not None else 1.0)
            gen_mean = gen_mean - lr_eff * grad.unsqueeze(0)
            gstats.append({"fit_best": round(float(fitness.min()), 4),
                           "fit_mean": round(float(fitness.mean()), 4),
                           "wr_groups": [round(float(x), 3) for x in wr_group.mean(0)],
                           "terms": {k: round(v, 3) for k, v in terms.items()}})
        gen_league.append(gen_mean[0].clone())
        lenv.install(1 + (rnd - 1) % 7, gen_league[-1])

        # ---------------- gate ----------------
        gate = gate_eval(gen_mean, snap_player(player), player_league[0],
                         seed=777_000 + rnd, device=dev, sampler=sampler,
                         weeks=weeks)
        ref = evaluate(player, n=1024, device=dev, seed=555_000 + rnd, obs_theta=True)
        ref_wins.append(ref["win"])
        th_dec = {k: round(float(v), 4) for k, v in
                  theta_from_z(gen_mean[0, DL.N_PARAMS:]).items()}
        n_sat = int((gen_mean[0, DL.N_PARAMS:].abs() > 2.5).sum())

        gate_err = gate["wr_argmax"] - TARGET
        in_band = abs(gate_err) <= 0.03
        band_hits = band_hits + 1 if in_band else 0
        ref_plateau = (len(ref_wins) >= 5 and
                       ref_wins[-1] - ref_wins[0] < 0.02)   # <2% gain over last 4 rounds

        rec = {"round": rnd, "sec": round(time.time() - t_rnd, 1), "weeks_gen": weeks,
               "player": pstats, "gen": gstats, "gate": gate,
               "ref_win": round(ref["win"], 4), "theta": th_dec, "z_saturated": n_sat,
               "band_hits": band_hits}
        with log_path.open("a") as f:
            f.write(json.dumps(rec) + "\n")
        print(f"[r{rnd:2}] gate {gate['wr_argmax']:.3f} (samp {gate['wr_sampled']:.3f} "
              f"old {gate['wr_old']:.3f} gap {gate['skill_gap']:+.2f}) | "
              f"fit {gstats[-1]['fit_mean']:.3f} | ent {pstats[-1]['ent']:.2f} "
              f"vl {pstats[-1]['vl']:.2f} | ref {ref['win']:.3f} | θsat {n_sat} | "
              f"{rec['sec']}s")

        torch.save({"round": rnd, "player": snap_player(player),
                    "gen_mean": gen_mean.cpu(), "meta": meta},
                   outdir / f"ckpt_r{rnd:02}.pt")

        if band_hits >= 4 and ref_plateau:
            print(f">>> converged at round {rnd}")
            break
        if (time.time() - t0) > args.budget_min * 60:
            print(">>> wall-time budget reached")
            break

    # final artifact: LAST-round mean (never best-of-pop / keep-best — winner's curse)
    torch.save({"gen_mean": gen_mean.cpu(), "targets": TARGET, "rounds": rnd},
               outdir / "generator_final.pt")
    dealer_w = gen_mean[0, :DL.N_PARAMS].cpu().tolist()
    json.dump({"target_win": TARGET, "rounds": rnd,
               "theta": {k: float(v) for k, v in
                         theta_from_z(gen_mean[0, DL.N_PARAMS:]).items()},
               "dealer": {"params": dealer_w, "n_params": DL.N_PARAMS,
                          "arch": {"ctx": DL.CTX_DIM, "mem_k": DL.MEM_K,
                                   "mem_dim": DL.MEM_DIM, "d_emb": DL.D_EMB,
                                   "out_per_cand": DL.OUT_PER_CAND}}},
              (here / "data/world_coevolved.json").open("w"))
    print(f"artifacts: {outdir/'generator_final.pt'} + data/world_coevolved.json")


if __name__ == "__main__":
    main()
