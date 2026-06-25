"""Torch co-evolution trainer. Two models trained adversarially by alternating ES:
  player_net (survive + kill)   vs   shared enemy_net (damage + approach, one net for all monster types).

Map source: --dataset <dir> (train/ + eval/ folds), else --map, else the 10 swiper maps. Batched
N = maps × --perm. Device auto-detected (cuda -> mps -> cpu). --budget caps wall-time (stops + saves).

  python train_torch.py --dataset datasets/surround --perm 8 --pop 12 --ticks 200 --cap 16 --eval
  python train_torch.py --dataset datasets/surround --pop 64 --ticks 400 --budget 3600   # 3090
"""
import argparse, glob, json, os, random, time
import torch
from tqdm import tqdm
import data, schedule
import policy_torch as P
import es_torch as ES
from env_torch import EnvTorch

H = 32                                   # hidden width (tiny for POC)
PLAYER_SIZES = [EnvTorch.player_obs, H, H, EnvTorch.player_act]
ENEMY_SIZES = [EnvTorch.enemy_obs, H, H, EnvTorch.enemy_act]
# Held-out map the models never train on (training uses the 10 swiper maps from prod.json).
EVAL_MAP_DEFAULT = os.path.join(os.path.dirname(__file__), "eval_maps", "eval_unseen.json")


def pick_device(pref="auto"):
    """auto: cuda (3090) -> mps (Apple GPU) -> cpu. Explicit value passes through."""
    if pref and pref != "auto":
        return pref
    if torch.cuda.is_available():
        return "cuda"
    mps = getattr(torch.backends, "mps", None)
    if mps is not None and mps.is_available():
        return "mps"
    return "cpu"


def _perf_setup(dev):
    """Standard torch perf flags. On cuda: TF32 fast-path for the (tiny) MLP matmuls — only affects the
    net, parity-safe. cudnn.benchmark is a no-op for us (no convs). The sim stays fp32; bf16/fp16 are NOT
    used (d² overflows fp16 at world scale, bf16 mantissa too coarse for collision thresholds)."""
    torch.backends.cudnn.benchmark = True
    if dev == "cuda":
        torch.backends.cuda.matmul.allow_tf32 = True
        torch.backends.cudnn.allow_tf32 = True
        torch.set_float32_matmul_precision("high")


def tick_at(it, args):
    """Tick curriculum: ramp rollout length from --tick-start to --ticks over --tick-warmup iters. Short
    early episodes cost ~ticks and are enough to learn basic survive/aim; lengthen as policies mature.
    Off when --tick-start<=0. Eval always uses full ticks. (ticks is the loop count, not a tensor shape,
    so varying it does NOT trigger torch.compile recompiles.)"""
    s = args.tick_start
    if s <= 0 or it >= args.tick_warmup:
        return args.ticks
    return int(s + (args.ticks - s) * (it / max(args.tick_warmup, 1)))


def swiper_maps(client):
    prod = json.load(open(os.path.join(client, "Resources", "prod.json")))
    names = prod["mapFilenames"]
    return [os.path.join(client, "Resources", "MapConfigs", n + ".json") for n in names]


def train_paths(args):
    """--dataset <dir> -> <dir>/train/*.json ; else --map ; else the 10 swiper maps."""
    if args.dataset:
        return sorted(glob.glob(os.path.join(args.dataset, "train", "*.json")))
    return [args.map] if args.map else swiper_maps(args.client)


def eval_paths(args):
    """--eval-map override ; else --dataset/eval/*.json ; else the single held-out unseen map."""
    if args.eval_map:
        return [args.eval_map]
    if args.dataset:
        return sorted(glob.glob(os.path.join(args.dataset, "eval", "*.json")))
    return [EVAL_MAP_DEFAULT]


def build_env(args):
    gd = data.GameData(args.client)
    paths = train_paths(args)
    levels = [data.sim_level(data.load_map(p)) for p in paths]
    n_envs = len(levels) * args.perm
    sched = schedule.build_multi(levels, gd.monsters, base_seed=1, n_envs=n_envs, cap=args.cap)
    weapon = gd.weapons.get(1) or next(iter(gd.weapons.values()))
    exo = gd.exoskeletons.get(1) or next(iter(gd.exoskeletons.values()))
    env = EnvTorch(sched, weapon, exo, device=args.device, bullets=args.bullets)
    return env, len(levels), n_envs


def _play_batch(env, ticks_max, real_tot, env_ticks, pf, ef):
    """Play ALL eval games at once, vectorized over the N-env batch (exactly like training rolls N
    envs) — NO per-game loop. Each env runs to its own timeout / cleared / death; metrics are frozen
    per-env at the first crossing via masks, so this is byte-identical to playing each game alone and
    breaking. The only loop is the unavoidable per-tick time loop. Returns (survived[N], kills[N], dmg[N])."""
    s = env.reset(1)
    N = s["player_hp"].shape[1]
    dev = s["player_hp"].device
    hp_max = float(env.cfg.player_max_hp)
    done = torch.zeros(N, device=dev)
    fk = torch.zeros(N, device=dev)
    fhp = torch.full((N,), hp_max, device=dev)
    with torch.no_grad():
        for tk in range(1, ticks_max + 1):
            s, _, _, panel = env.step(s, tk, pf, ef)
            if panel is not None and env._panel is not None:               # accumulate eval reward-term sums here (out of core)
                for _k, _v in panel.items():
                    env._panel[_k] += _v
            hp = s["player_hp"][0]; k = s["kills"][0]                       # [N]
            cross = ((hp <= 0) | (k >= real_tot) | (tk >= env_ticks)).float()
            newly = (1.0 - done) * cross
            fk = torch.where(newly > 0.5, k, fk)
            fhp = torch.where(newly > 0.5, hp.clamp(min=0.0), fhp)
            done = torch.maximum(done, cross)
            if float(done.min()) > 0.5:
                break
    return fhp > 0, fk, hp_max - fhp


def _print_panel(args, pan):
    """Print the reward-decomposition panel: per-tick RAW behavioral value, the weight & sign it enters the
    reward with, and the resulting weighted contribution. Shows which terms are dead/dominant and what the
    policy is actually DOING (raw value is meaningful even for weight-0 terms). Weights come from args (the
    actual training weights), not the fresh eval env which carries only defaults."""
    if not pan:
        return
    tk = max(pan.get("ticks", 1.0), 1.0)
    print("  reward panel (per tick — raw behavioral value, weight, sign, weighted contribution):")
    for lab, key, sgn, w in _reward_terms(args):
        raw = pan.get(key, 0.0) / tk
        print(f"    {lab:11s} raw={raw:11.3f}  w={w:8.4f}  {'+' if sgn > 0 else '-'}  contrib={sgn * w * raw:+11.4f}")


def _reward_terms(args):
    """(label, panel-key, sign-in-reward, weight) for every reward term — single source for panel + tb.
    The hardcoded enemy weights (0.1/0.0008/0.02) mirror env_torch._core."""
    return [("kill", "p_kill", +1, args.rw_kill), ("aim", "p_aim", +1, args.rw_aim),
            ("damage", "p_damage", +1, args.rw_damage), ("hit", "p_hit", -1, args.rw_hit),
            ("space", "p_space", +1, args.rw_space), ("ring", "p_ring", -1, args.rw_ring),
            ("effort", "p_effort", -1, args.rw_effort), ("shot", "p_shot", -1, args.rw_shot),
            ("e_dmg", "e_dmg", +1, args.rw_e_dmg), ("e_approach", "e_approach", +1, args.rw_e_approach),
            ("e_deaths", "e_deaths", -1, args.rw_e_deaths), ("e_align", "e_align", +1, args.rw_align),
            ("e_separate", "e_separate", -1, args.rw_separate)]


def _tb_eval(writer, args, it, rows, panel):
    """Log eval metrics + per-tick reward RAW values AND weighted CONTRIBUTIONS. The contrib curves directly
    expose OVER-powered terms (dominant |contrib|) and UNDER-powered ones (~0) from a single run."""
    if writer is None:
        return
    def agg(rs, tag):
        n = max(len(rs), 1)
        writer.add_scalar(f"eval{tag}/survival_pct", 100.0 * sum(r[1] for r in rs) / n, it)
        writer.add_scalar(f"eval{tag}/kills", sum(r[2] for r in rs) / n, it)
        writer.add_scalar(f"eval{tag}/clear_pct", 100.0 * sum(r[2] / max(r[3], 1) for r in rs) / n, it)
        writer.add_scalar(f"eval{tag}/dmg", sum(r[4] for r in rs) / n, it)
    agg(rows, "")                                         # overall
    for w in sorted(set(r[0].split(":")[0] for r in rows if ":" in r[0])):   # per-weapon curves
        agg([r for r in rows if r[0].split(":")[0] == w], "_" + w)
    if panel:
        tk = max(panel.get("ticks", 1.0), 1.0)
        for lab, key, sgn, w in _reward_terms(args):
            raw = panel.get(key, 0.0) / tk
            writer.add_scalar(f"reward_raw/{lab}", raw, it)
            writer.add_scalar(f"reward_contrib/{lab}", sgn * w * raw, it)


def run_eval(gd, weapons, exo, args, player, enemy, dev, seeds, arch="mlp"):
    """Play every held-out (map x seed) game in ONE batched rollout (no map/seed loop).
    Returns (rows, maps); row = (name, survived, kills, M, dmg). enemy=None -> scripted monster steering
    (the fixed, game-realistic reference opponent), so eval measures absolute player skill, not the
    co-evolving arms race (which makes clear% bounce as the enemy strengthens).
    arch='attn' -> player is an attention bundle: feed env.player_set_obs and apply_attn (mu only)."""
    if arch == "attn":
        import policy_attn as AT
        pf = lambda bundle: AT.apply_attn(player, bundle[0], bundle[1], bundle[2])[0]
    else:
        pf = lambda obs: P.apply_mlp(player, obs)
    ef = (lambda obs: P.apply_enemy(enemy, obs)) if enemy is not None else None
    maps = eval_paths(args)
    levels = [data.sim_level(data.load_map(m)) for m in maps]
    names = [os.path.basename(m) for m in maps]
    sched, real_tot, assign = schedule.build_eval(levels, gd.monsters, seeds, cap=1024)
    env = EnvTorch(sched, weapons[0], exo, device=dev, bullets=args.bullets)
    if arch == "attn":
        env.player_obs_fn = env.player_set_obs
    per_ticks = [args.eval_ticks or int(lv["duration"] * 30) for lv in levels]
    env_ticks = torch.tensor([per_ticks[assign[e]] for e in range(len(assign))], device=dev, dtype=torch.float32)
    rt = torch.tensor(real_tot, device=dev)
    rows, panel = [], {}
    for w in weapons:                                    # one weapon-conditioned policy, evaluated per weapon
        wname = str(w.get("name", w.get("id", "?")))
        env.set_weapon(w)
        env.decompose = True; env.reset_panel()          # cheap at eval scale; powers --eval-panel + tensorboard
        surv, fk, dmg = _play_batch(env, int(env_ticks.max()), rt, env_ticks, pf, ef)
        panel = env.read_panel()                         # representative (last weapon)
        rows += [(f"{wname}:{names[assign[e]]}", bool(surv[e]), int(fk[e]), int(real_tot[e]), float(dmg[e]))
                 for e in range(len(assign))]
    if getattr(args, "eval_panel", False):
        _print_panel(args, panel)
    return rows, maps, panel


def eval_line(rows):
    n = len(rows)
    surv = sum(r[1] for r in rows)
    mk = sum(r[2] for r in rows) / n
    mclear = sum(r[2] / max(r[3], 1) for r in rows) / n
    mdmg = sum(r[4] for r in rows) / n
    return f"survival {surv}/{n} ({100*surv/n:.0f}%)  kills {mk:.1f}  clear {100*mclear:.0f}%  dmg {mdmg:.0f}"


def eval_report(rows, maps, seeds, dev):
    print(f"\nEval ({len(maps)} maps x {seeds} seeds = {len(rows)} games, dev={dev}):")
    print(f"  overall  {eval_line(rows)}")
    # rows are tagged "weapon:mapname" -> break down per weapon (the generalization readout)
    weapons = sorted(set(r[0].split(":")[0] for r in rows if ":" in r[0]))
    for w in (weapons or [None]):
        wr = [r for r in rows if w is None or r[0].split(":")[0] == w] if w else rows
        print(f"    {(w or 'all'):10s} {eval_line(wr)}")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--client", default=data.DEFAULT_CLIENT)
    ap.add_argument("--dataset", default="")             # <dir> with train/ + eval/ folds (overrides --map)
    ap.add_argument("--map", default="")                 # single map override (else 10 swiper maps)
    ap.add_argument("--perm", type=int, default=4)       # envs per map  -> N = maps * perm
    ap.add_argument("--pop", type=int, default=8)        # ES population (rollout uses 2*pop)
    ap.add_argument("--ticks", type=int, default=150)
    ap.add_argument("--iters", type=int, default=8)      # alternating player/enemy
    ap.add_argument("--tick-start", type=int, default=0)   # tick curriculum start len (0=off -> full ticks)
    ap.add_argument("--tick-warmup", type=int, default=40) # iters to ramp tick-start -> ticks
    ap.add_argument("--cap", type=int, default=64)       # monster slots
    ap.add_argument("--bullets", type=int, default=8)    # bullet ring-buffer slots; must be >= max simultaneous
    #   alive bullets for the weapon (else live bullets get overwritten -> sim changes). Pistol peaks at 2;
    #   8 = margin (parity-exact vs 32). Size up for fast guns. Collision+dodge are all-pairs over B, so B = cost.
    ap.add_argument("--sigma", type=float, default=0.1)
    ap.add_argument("--lr", type=float, default=0.05)
    # co-evolution stabilization (Red-Queen / runaway-enemy fixes). Defaults reproduce the old 50/50 loop.
    ap.add_argument("--enemy-every", type=int, default=2)   # train enemy 1-in-K iters (K=2: old 50/50; K>2:
    #   asymmetric cadence — slow the enemy so the player can converge instead of chasing a moving target).
    ap.add_argument("--enemy-pool", type=int, default=1)    # league size: player trains vs a random snapshot
    #   from the last N enemies (1 = latest only = old behavior; N>1 = PSRO-lite, damps oscillation).
    ap.add_argument("--freeze-enemy", action="store_true")  # freeze the enemy net: never ES-update it; the player
    #   trains vs a STATIC neural opponent (load a trained enemy via --resume). Stops the arms-race runaway.
    ap.add_argument("--algo", default="es", choices=["es", "grpo", "ppo"])  # policy-gradient player (+ ES enemy)
    ap.add_argument("--player-arch", default="mlp", choices=["mlp", "attn"])  # attn = single-query cross-attention
    #   over the per-monster SET obs (surroundings-aware); requires --algo ppo, not --engine jax.
    ap.add_argument("--attn-dim", type=int, default=32)       # attention key/value/query width
    ap.add_argument("--attn-hidden", type=int, default=64)    # encoder head hidden width
    ap.add_argument("--grpo-lr", type=float, default=3e-3)
    ap.add_argument("--grpo-group", type=int, default=64)  # P = group size (action samples per env)
    ap.add_argument("--grpo-gamma", type=float, default=0.99)
    ap.add_argument("--grpo-std", type=float, default=0.6)  # initial action std
    ap.add_argument("--grpo-ent", type=float, default=0.0)  # entropy bonus coef
    ap.add_argument("--ppo-lr", type=float, default=1e-4)    # T3: 3e-4 was unstable (policy collapse); 1e-4 stable
    ap.add_argument("--ppo-epochs", type=int, default=4)
    ap.add_argument("--ppo-clip", type=float, default=0.2)
    ap.add_argument("--ppo-gae", type=float, default=0.95)
    ap.add_argument("--ppo-gamma", type=float, default=0.99)
    ap.add_argument("--ppo-minibatch", type=int, default=16384)
    ap.add_argument("--ppo-vcoef", type=float, default=0.5)
    ap.add_argument("--ppo-ent", type=float, default=0.003)  # T3: light entropy bonus aids stability
    ap.add_argument("--ppo-group", type=int, default=64)
    ap.add_argument("--ppo-std", type=float, default=0.5)    # T3: 0.5 > 0.6 (less collapse from over-exploration)
    ap.add_argument("--rw-kill", type=float, default=1.0)     # reward shaping (training-only, parity-safe)
    ap.add_argument("--rw-survive", type=float, default=0.01)
    ap.add_argument("--rw-damage", type=float, default=0.0)   # dense damage-dealt shaping (0=off, parity-safe)
    ap.add_argument("--rw-hit", type=float, default=0.05)     # penalty per HP TAKEN; raise to force dodging/moving
    ap.add_argument("--rw-aim", type=float, default=0.005)    # reward for aiming at the threat centroid (raise -> aim tracks)
    ap.add_argument("--rw-space", type=float, default=0.0)    # reward for keeping the (space-keep+1)-th monster away
    ap.add_argument("--space-keep", type=int, default=2)      # how many monsters you may have close (default 2)
    ap.add_argument("--space-target", type=float, default=200.0)  # distance where the spacing reward saturates
    ap.add_argument("--rw-ring", type=float, default=0.0)     # keep-out circle: penalty per tick per monster inside
    ap.add_argument("--ring-radius", type=float, default=90.0)  # personal-space radius (~2 monster bodies, >damage line)
    ap.add_argument("--rw-effort", type=float, default=0.0)   # economical move cost (∝|move|) -> still when safe
    ap.add_argument("--rw-shot", type=float, default=0.0)     # economical fire cost -> trigger discipline (pair w/ rw-damage)
    ap.add_argument("--rw-e-dmg", type=float, default=0.1)       # enemy: reward per HP dealt to player (was hardcoded)
    ap.add_argument("--rw-e-approach", type=float, default=0.0008)  # enemy: DENSE closing reward — lower to slow the enemy
    ap.add_argument("--rw-e-deaths", type=float, default=0.02)   # enemy: penalty per monster killed (was hardcoded)
    ap.add_argument("--rw-align", type=float, default=0.0)    # enemy: reward coherent swarm heading (flocking alignment)
    ap.add_argument("--rw-separate", type=float, default=0.0)  # enemy: penalty for monsters stacking (anti-overlap)
    ap.add_argument("--sep-radius", type=float, default=50.0)  # monster separation circle (~1 body)
    ap.add_argument("--seed", type=int, default=0)       # training-only RNG offset (multi-seed validation;
    #   parity-safe — sim uses det_rand, NOT global RNG. seed=0 reproduces the original fixed-seed run).
    ap.add_argument("--device", default="auto")          # auto: cuda -> mps -> cpu (explicit value respected)
    ap.add_argument("--engine", default="torch", choices=["torch", "jax"])  # jax: lax.scan rollout (~1.23x, T3)
    ap.add_argument("--policy-bf16", action="store_true")  # bf16 policy MLP forward (~1.3x; sim stays fp32,
    #   game logic unaffected — only the learned policy trajectory + parity checksum change, so opt-in).
    ap.add_argument("--compile", action="store_true")    # torch.compile the env step (CUDA-graphs on cuda)
    ap.add_argument("--compile-mode", default="default")  # "default"=Inductor fusion (robust). "reduce-overhead"
    #                                                       adds CUDA-graphs but breaks on our recurrent rollout.
    ap.add_argument("--budget", type=float, default=0.0)   # wall-time cap in seconds (0=off); stops + saves
    ap.add_argument("--eval", action="store_true")       # after training, play one UNSEEN map headless
    ap.add_argument("--eval-map", default="")            # default: dataset/eval/*.json or eval_unseen.json
    ap.add_argument("--eval-ticks", type=int, default=0)  # 0 -> landingDuration*30 (full map)
    ap.add_argument("--eval-seeds", type=int, default=3)  # seeds per eval map (held-out distribution)
    ap.add_argument("--eval-vs", default="live", choices=["fixed", "live"])  # eval opponent (always neural):
    #   fixed = frozen enemy snapshot (held constant -> clean absolute player-progress metric);
    #   live = the current enemy (co-evolving, or static if --freeze-enemy). Comparable across iters when frozen.
    ap.add_argument("--eval-every", type=int, default=0)  # run a quick 1-seed eval every K iters (0=off)
    ap.add_argument("--keep-best", action="store_true")   # save the PEAK fixed-eval checkpoint, not the final
    #   weights. Diagnosis: co-evo collapse is LATE — bad seeds peak mid-run (77-85%) then degrade to 23-53%
    #   by the end. Keeping the best-along-trajectory checkpoint dodges the tail collapse (needs --eval-every).
    ap.add_argument("--render", default="")              # render a 3x3 eval grid video to this path at end
    ap.add_argument("--player-out", default="../MonstroSim/models/player.json")
    ap.add_argument("--enemy-out", default="../MonstroSim/models/monster.json")
    ap.add_argument("--resume", default="")              # load full training state (attn weights+Adam+glog+enemy+it) if file exists
    ap.add_argument("--ckpt-out", default="")            # save full training state here at the end (for --resume)
    ap.add_argument("--eval-panel", action="store_true") # decompose eval: print every reward-term RAW sum + sign + weight
    ap.add_argument("--logdir", default="")              # tensorboard dir: per-iter fitness/PPO-loss + per-eval metrics + reward panel
    ap.add_argument("--weapons", default="")             # comma-sep weapon ids to cycle, e.g. 1,5,4 (pistol,shotgun,minigun); "" = id 1
    ap.add_argument("--range-rand", default="")          # "lo,hi" -> per-iter random bullet_range scale (e.g. 0.3,1.0); forces out-of-range -> range discipline
    args = ap.parse_args()
    if args.player_arch == "attn":
        assert args.algo == "ppo", "--player-arch attn requires --algo ppo (gradients; ES can't scale to it)"
        assert args.engine != "jax", "--player-arch attn is torch-only (no JAX engine)"

    dev = pick_device(args.device)
    args.device = dev
    _perf_setup(dev)
    torch.manual_seed(args.seed)                          # training RNG (PPO/GRPO action sampling); parity-safe
    env, n_maps, n_envs = build_env(args)
    env.rw_kill, env.rw_survive = args.rw_kill, args.rw_survive   # reward shaping (set BEFORE compile bakes it)
    env.rw_damage = args.rw_damage
    env.rw_hit = args.rw_hit
    env.rw_space, env.space_keep, env.space_target = args.rw_space, args.space_keep, args.space_target
    env.rw_aim = args.rw_aim
    env.rw_ring, env.ring_radius = args.rw_ring, args.ring_radius   # keep-out circle (pure-neural predictor)
    env.rw_effort, env.rw_shot = args.rw_effort, args.rw_shot        # economical actions (move/fire cost)
    env.rw_align, env.rw_separate, env.sep_radius = args.rw_align, args.rw_separate, args.sep_radius   # swarm
    env.rw_e_dmg, env.rw_e_approach, env.rw_e_deaths = args.rw_e_dmg, args.rw_e_approach, args.rw_e_deaths  # enemy core
    Ppop = 2 * args.pop
    jr = None
    if args.engine == "jax":
        # Hybrid: torch ES/eval/save, JAX lax.scan rollout for fitness (the only hot path). ~1.23x over
        # torch-fusion on cuda (T3); env_jax is parity-proven so trained models still run in the Swift game.
        assert args.tick_start <= 0, "--engine jax bakes a fixed tick count; tick curriculum is unsupported"
        import jax_engine
        jr = jax_engine.JaxRollout(env, args.ticks, Ppop, dev)
        print(f"  engine: JAX (lax.scan rollout, P={Ppop})")
    elif args.compile:
        # Inductor FUSION is the win (compile-clean _core traces once; the 5.3x on mps was fusion alone,
        # no CUDA-graphs). 'default' is robust everywhere. 'reduce-overhead' adds CUDA-graphs but its
        # static-buffer reuse clobbers our carried rollout state -> off by default. First iter = warmup.
        mode = None if (args.compile_mode == "default" or dev != "cuda") else args.compile_mode
        env._core = torch.compile(env._core, mode=mode)
        print(f"  torch.compile: ON (mode={mode or 'default'})")
    gd_eval = data.GameData(args.client)                  # loaded once; reused by periodic + final eval
    if args.weapons:                                      # weapon-conditioned policy: cycle these each iter
        weapon_cyc = [gd_eval.weapons[int(i)] for i in args.weapons.split(",")]
    else:
        weapon_cyc = [gd_eval.weapons.get(1) or next(iter(gd_eval.weapons.values()))]
    exo_eval = gd_eval.exoskeletons.get(1) or next(iter(gd_eval.exoskeletons.values()))
    print(f"  weapons: {[w.get('name', w.get('id')) for w in weapon_cyc]} (cycled per iter)")
    src = os.path.basename(args.dataset.rstrip("/")) if args.dataset else ("map" if args.map else "swiper")
    print(f"Torch co-evolution [{src}]: {n_maps} maps x {args.perm} = N={n_envs} envs, M={env.M}, "
          f"B={env.B}, ticks={args.ticks}, pop={args.pop}, iters={args.iters}, dev={dev}")

    sd = args.seed                                        # net-init offset (multi-seed validation; sd=0 = original)
    player = P.init_mlp(PLAYER_SIZES, device=dev, seed=7 + sd)
    enemy = P.init_mlp(ENEMY_SIZES, device=dev, seed=11 + sd)
    _ckpt = torch.load(args.resume, map_location=dev) if (args.resume and os.path.exists(args.resume)) else None
    if _ckpt is not None:                                  # resume: enemy first (closures below capture it)
        enemy = [(W.to(dev), b.to(dev)) for W, b in _ckpt["enemy"]]
        print(f"  resume: loaded {args.resume} (it={_ckpt.get('it', 0)})")
    enemy_ref = [(W.clone(), b.clone()) for W, b in enemy]   # frozen iter-0 snapshot = the fixed eval opponent
    gen = torch.Generator().manual_seed(42 + sd)         # CPU generator (noise moved to device in es)
    rrng = random.Random(123 + sd)                        # range-randomization RNG (separate, doesn't perturb ES stream)
    rr = [float(x) for x in args.range_rand.split(",")] if args.range_rand else None
    # enemy league (PSRO-lite): pool of past enemy snapshots the player trains against (see --enemy-pool).
    import random as _random
    pool_rng = _random.Random(1234 + sd)
    snap = lambda net: [(W.detach().clone(), b.detach().clone()) for W, b in net]
    enemy_pool = [snap(enemy)]
    def opponent():                                      # the enemy the player trains against this iter
        if args.enemy_pool <= 1:
            return enemy                                 # latest only (old behavior, exact)
        return enemy_pool[pool_rng.randrange(len(enemy_pool))]
    # which opponent eval/render run against (see --eval-vs): fixed snapshot or live co-evolving enemy.
    eval_enemy = lambda: (enemy_ref if args.eval_vs == "fixed" else enemy)
    if args.keep_best and args.eval_every <= 0:           # keep-best needs periodic fixed-eval to score on
        args.eval_every = 20
    best_keep = (_ckpt["best_keep"] if (_ckpt is not None and _ckpt.get("best_keep")) else
                 {"score": -1.0, "player": None, "enemy": None, "it": -1, "log_std": None})
    def keep_score(rows):                                 # clear-dominant, small survival bonus (both 0..1)
        n = len(rows)
        return sum(r[2] / max(r[3], 1) for r in rows) / n + 0.25 * (sum(r[1] for r in rows) / n)

    pdt = torch.bfloat16 if args.policy_bf16 else None   # bf16 policy forward (sim stays fp32); ~1.3x rollout
    if args.player_arch == "attn":                       # attn player consumes the SET-obs bundle, not a flat vec
        import policy_attn as _AT                         #   (used as the FROZEN opponent in the enemy-ES step)
        pf = lambda params: (lambda b: _AT.apply_attn(params, b[0], b[1], b[2], pdt)[0])
    else:
        pf = lambda params: (lambda obs: P.apply_mlp(params, obs, mm_dtype=pdt))
    ef = lambda params: (lambda obs: P.apply_enemy(params, obs, mm_dtype=pdt))

    grpo = ppo = None
    if args.algo == "grpo":
        import grpo_torch as G                            # policy-gradient player (the deployed agent)
        gparams, glog = G.init_player(PLAYER_SIZES, dev, seed=7 + sd, std0=args.grpo_std)
        gopt = torch.optim.Adam(G.opt_params(gparams, glog), lr=args.grpo_lr)
        player = G.mean_params(gparams)                   # eval/save/opponent use the deterministic mean
        grpo = (G, gparams, glog, gopt)
        print(f"  algo: GRPO player (group={args.grpo_group} lr={args.grpo_lr} std={args.grpo_std}) + ES enemy")
    elif args.algo == "ppo" and args.player_arch == "attn":
        import ppo_attn as PPOA, policy_attn as AT          # single-query cross-attention over the SET obs
        env.player_obs_fn = env.player_set_obs              # feed the per-monster set obs through env.step (eval)
        attn_meta = {"Fs": EnvTorch.player_set_fs, "Fm": EnvTorch.player_set_fm,
                     "d": args.attn_dim, "H": args.attn_hidden, "act": EnvTorch.player_act}
        aparams, glog = AT.init_attn(attn_meta["Fs"], attn_meta["Fm"], attn_meta["d"], attn_meta["H"],
                                     attn_meta["act"], dev, seed=7 + sd, std0=args.ppo_std)
        popt = torch.optim.Adam(AT.opt_params(aparams, glog), lr=args.ppo_lr)
        if _ckpt is not None:                              # restore attn weights + glog + Adam moments IN PLACE
            for (W, b), (cW, cb) in zip(aparams, _ckpt["aparams"]):
                W.data.copy_(cW.to(dev)); b.data.copy_(cb.to(dev))
            glog.data.copy_(_ckpt["glog"].to(dev)); popt.load_state_dict(_ckpt["popt"])
        player = AT.mean_params(aparams)
        ppo = ("attn", PPOA, AT, aparams, glog, popt)
        print(f"  algo: PPO ATTENTION player (d={args.attn_dim} H={args.attn_hidden} group={args.ppo_group} "
              f"lr={args.ppo_lr}) + ES enemy   rw_hit={args.rw_hit} rw_space={args.rw_space} rw_aim={args.rw_aim}")
    elif args.algo == "ppo":
        import grpo_torch as G, ppo_torch as PPO          # PPO: clipped surrogate + critic + GAE
        gparams, glog = G.init_player(PLAYER_SIZES, dev, seed=7 + sd, std0=args.ppo_std)
        vparams = PPO.init_value(dev, seed=23 + sd, in_dim=EnvTorch.player_obs)   # critic sees the full obs
        popt = torch.optim.Adam(G.opt_params(gparams, glog) + PPO.value_params_flat(vparams), lr=args.ppo_lr)
        player = G.mean_params(gparams)
        ppo = ("mlp", PPO, G, gparams, glog, vparams, popt)
        print(f"  algo: PPO player (group={args.ppo_group} lr={args.ppo_lr} epochs={args.ppo_epochs} "
              f"clip={args.ppo_clip}) + ES enemy   rw_kill={args.rw_kill} rw_survive={args.rw_survive}")

    best = 0.0
    hist = {"player": [], "enemy": []}
    last = {"player": float("nan"), "enemy": float("nan")}
    writer = None
    if args.logdir:
        from torch.utils.tensorboard import SummaryWriter
        writer = SummaryWriter(args.logdir)
        print(f"  tensorboard -> {args.logdir}   (view: tensorboard --logdir {os.path.dirname(args.logdir) or args.logdir})")
    t0 = time.time()
    use_budget = args.budget > 0
    # When budgeted, the bar tracks WALL-TIME (fills to --budget seconds) so the ETA is the real
    # stop time — not tqdm projecting all --iters (which the budget halts long before).
    pbar = tqdm(total=(round(args.budget) if use_budget else args.iters), desc="co-evo",
                unit=("s" if use_budget else "it"), dynamic_ncols=True)
    it = _ckpt["it"] if _ckpt is not None else 0
    while it < args.iters:
        rscale = rrng.uniform(rr[0], rr[1]) if rr else 1.0    # per-iter range scale -> forces out-of-range regime
        env.set_weapon(weapon_cyc[it % len(weapon_cyc)], rscale)   # per-iter weapon + range randomization
        train_player = args.freeze_enemy or (it % args.enemy_every != args.enemy_every - 1)   # enemy 1-in-K (frozen -> never)
        cur_ticks = tick_at(it, args)                          # curriculum: short rollouts early -> full
        if train_player:
            opp = opponent()                                    # league opponent (latest, or sampled snapshot)
            if ppo is not None and ppo[0] == "attn":            # attention PPO (shared-encoder critic) vs ES enemy
                _, PPOA, AT, aparams, glog, popt = ppo
                _pl, _vl, ret = PPOA.ppo_step(env, cur_ticks, aparams, glog, popt, opp, args.ppo_group,
                                              gamma=args.ppo_gamma, lam=args.ppo_gae, clip=args.ppo_clip,
                                              epochs=args.ppo_epochs, minibatch=args.ppo_minibatch,
                                              vcoef=args.ppo_vcoef, ent=args.ppo_ent, mm_dtype=pdt)
                player = AT.mean_params(aparams)
                best = ret; hist["player"].append(ret); last["player"] = ret
                if writer is not None:
                    writer.add_scalar("ppo/policy_loss", float(_pl), it); writer.add_scalar("ppo/value_loss", float(_vl), it)
            elif ppo is not None:                               # MLP PPO player step vs the frozen ES enemy
                _, PPO, G, gparams, glog, vparams, popt = ppo
                _pl, _vl, ret = PPO.ppo_step(env, cur_ticks, gparams, glog, vparams, popt, opp, args.ppo_group,
                                             gamma=args.ppo_gamma, lam=args.ppo_gae, clip=args.ppo_clip,
                                             epochs=args.ppo_epochs, minibatch=args.ppo_minibatch,
                                             vcoef=args.ppo_vcoef, ent=args.ppo_ent)
                player = G.mean_params(gparams)
                best = ret; hist["player"].append(ret); last["player"] = ret
                if writer is not None:
                    writer.add_scalar("ppo/policy_loss", float(_pl), it); writer.add_scalar("ppo/value_loss", float(_vl), it)
            elif grpo is not None:                              # GRPO player step vs the frozen ES enemy
                G, gparams, glog, gopt = grpo
                _loss, ret = G.grpo_player_step(env, cur_ticks, gparams, glog, gopt, opp,
                                                args.grpo_group, gamma=args.grpo_gamma, ent_coef=args.grpo_ent)
                player = G.mean_params(gparams)                 # refresh the deterministic mean for eval/opponent
                best = ret; hist["player"].append(ret); last["player"] = ret
                if writer is not None:
                    writer.add_scalar("ppo/policy_loss", float(_pl), it); writer.add_scalar("ppo/value_loss", float(_vl), it)
            else:
                def fitness(stacked):
                    if jr is not None:
                        return jr.reward_player(stacked, opp)
                    out = env.rollout(Ppop, cur_ticks, pf(stacked), ef(opp))
                    return out["reward_player"].mean(1)
                player, best, mean = ES.es_step(player, fitness, args.pop, gen, dev, args.sigma, args.lr)
                hist["player"].append(mean); last["player"] = mean
        else:
            def fitness(stacked):
                if jr is not None:
                    return jr.reward_enemy(player, stacked)
                out = env.rollout(Ppop, cur_ticks, pf(player), ef(stacked))
                return out["reward_enemy"].mean(1)
            enemy, best, mean = ES.es_step(enemy, fitness, args.pop, gen, dev, args.sigma, args.lr)
            hist["enemy"].append(mean); last["enemy"] = mean
            if args.enemy_pool > 1:                             # add the freshly-trained enemy to the league
                enemy_pool.append(snap(enemy)); enemy_pool[:] = enemy_pool[-args.enemy_pool:]

        elapsed = time.time() - t0
        if use_budget:
            pbar.n = min(round(elapsed), round(args.budget)); pbar.refresh()
        else:
            pbar.update(1)
        pbar.set_postfix(it=it, phase="player" if train_player else "enemy",
                         player=f"{last['player']:.2f}", enemy=f"{last['enemy']:.3f}", best=f"{best:.2f}")
        if writer is not None:
            writer.add_scalar("fitness/player", last["player"], it)
            writer.add_scalar("fitness/enemy", last["enemy"], it)
        if args.eval_every and it > 0 and it % args.eval_every == 0:
            ev_seeds = 2 if args.keep_best else 1         # keep-best: 2 seeds for a less noisy checkpoint score
            rows, _, panel = run_eval(gd_eval, weapon_cyc, exo_eval, args, player, eval_enemy(), dev, seeds=ev_seeds,
                                      arch=args.player_arch)
            _tb_eval(writer, args, it, rows, panel)
            tqdm.write(f"  [eval @ it{it:4d} vs {args.eval_vs}]  {eval_line(rows)}")
            if args.keep_best:
                sc = keep_score(rows)
                if sc > best_keep["score"]:
                    ls = glog.detach().clone() if args.player_arch == "attn" else None
                    best_keep.update(score=sc, player=snap(player), enemy=snap(enemy), it=it, log_std=ls)
        it += 1
        if use_budget and elapsed > args.budget:
            print(f"\n>>> reached {args.budget:.0f}s budget at iter {it} — stopping (models saved below).", flush=True)
            break
    pbar.close()

    def trend(xs):
        return f"{xs[0]:.3f} -> {xs[-1]:.3f}  (+{xs[-1]-xs[0]:.3f})" if len(xs) >= 2 else (f"{xs[0]:.3f}" if xs else "n/a")
    print(f"Player fitness: {trend(hist['player'])}")
    print(f"Enemy  fitness: {trend(hist['enemy'])}")

    save_player, save_enemy = player, enemy
    if args.keep_best and best_keep["player"] is not None:   # save the PEAK checkpoint, not the collapsed final
        save_player, save_enemy = best_keep["player"], best_keep["enemy"]
        print(f"keep-best: saving the it{best_keep['it']} checkpoint (peak fixed-eval score "
              f"{best_keep['score']:.3f}) instead of the final weights.")
    os.makedirs(os.path.dirname(os.path.abspath(args.player_out)), exist_ok=True)
    if args.player_arch == "attn":                            # discriminated kind=attention JSON (not MLP sizes/w/b)
        import policy_attn as AT
        save_log_std = best_keep["log_std"] if (args.keep_best and best_keep.get("log_std") is not None) else glog
        attn_meta = {"Fs": EnvTorch.player_set_fs, "Fm": EnvTorch.player_set_fm,
                     "d": args.attn_dim, "H": args.attn_hidden, "act": EnvTorch.player_act}
        AT.to_json(save_player, save_log_std, attn_meta, args.player_out)
    else:
        P.to_json(save_player, PLAYER_SIZES, args.player_out)
    P.to_json(save_enemy, ENEMY_SIZES, args.enemy_out)
    print(f"saved -> {args.player_out}  +  {args.enemy_out}")
    if args.ckpt_out and args.player_arch == "attn":         # full-state checkpoint for --resume (current working state)
        torch.save({"aparams": aparams, "glog": glog, "popt": popt.state_dict(),
                    "enemy": enemy, "it": it, "best_keep": best_keep}, args.ckpt_out)
        print(f"  ckpt -> {args.ckpt_out} (it={it})")
    player, enemy = save_player, save_enemy               # final --eval / --render reflect the deployed model

    if args.eval:
        print(f"  (eval opponent: --eval-vs {args.eval_vs})")
        rows, maps, panel = run_eval(gd_eval, weapon_cyc, exo_eval, args, player, eval_enemy(), dev, max(1, args.eval_seeds),
                                     arch=args.player_arch)
        _tb_eval(writer, args, it, rows, panel)
        eval_report(rows, maps, args.eval_seeds, dev)

    if args.render:
        try:                                                  # non-fatal: models are already saved above
            import render_eval
            render_eval.render_grid(gd_eval, weapon_cyc, exo_eval, args, player, eval_enemy(), dev, args.render,
                                    arch=args.player_arch)
        except Exception as e:
            print(f"  [render skipped] {type(e).__name__}: {e}\n  (models saved OK; video needs imageio-ffmpeg "
                  f"— `pip install imageio-ffmpeg`, or run in the conda env that has it.)")

    if writer is not None:
        writer.close()


if __name__ == "__main__":
    main()
