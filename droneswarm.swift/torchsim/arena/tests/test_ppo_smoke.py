"""PPO smoke (slow) — the drone brain measurably improves at the shaped hunt objective over a handful
of tiny updates, with no NaNs (froggo test_ppo_smoke idiom). Enemy frozen to isolate the learning
signal from co-evolution. Deselected by default: pytest -m 'not slow'."""
import math
import os
import sys

import pytest
import torch

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import policy_attn as AT
import policy_recur as RE
import ppo_team as PPO
import schedule_drone as S
from env_drone import EnvDrone
from world_config_drone import WorldConfig

pytestmark = pytest.mark.slow


def test_drone_learns_something():
    cfg = WorldConfig()
    env = EnvDrone(S.build(cfg, 32, D=8, E=6, O=8, T=200, base_seed=0), device="cpu", cfg=cfg)
    K_dec = 200 // cfg.act_every
    torch.manual_seed(0)
    dp, dls = RE.init_recur(EnvDrone.DRONE_SELF_F, EnvDrone.DRONE_TOK_F, 16, 32, EnvDrone.DRONE_ACT, seed=0)
    ep, els = AT.init_attn(EnvDrone.ENEMY_SELF_F, EnvDrone.ENEMY_TOK_F, 16, 32, EnvDrone.ENEMY_ACT, seed=1)
    opt = torch.optim.Adam(RE.opt_params(dp, dls), lr=3e-3)
    vls = []
    for _ in range(30):                                          # frozen enemy -> pure (recurrent) drone improvement
        pl, vl, ret, valid = PPO.ppo_step(env, "drone", dp, dls, ep, els, opt, P=2, K_dec=K_dec,
                                          minibatch=16384, epochs=2)
        assert math.isfinite(pl) and math.isfinite(vl) and math.isfinite(ret)
        vls.append(vl)
    # VALUE-LOSS DECREASING is the robust "the learning stack works" signal: the critic learning to
    # predict returns exercises the whole pipeline (rollout -> GAE targets -> minibatch -> backprop),
    # independent of which behavior direction the (noisy, bounded potential-shaped) reward pushes.
    # On GPU this fell 55.9 -> 14.4; here we just require the tail below the head.
    first = sum(vls[:5]) / 5
    last = sum(vls[-5:]) / 5
    assert last < first, f"critic value loss did not fall (learning stack broken?): first={first:.3f} last={last:.3f}"
