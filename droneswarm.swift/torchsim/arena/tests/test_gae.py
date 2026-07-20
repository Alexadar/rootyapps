"""Done-masked per-agent GAE — reduces to the plain reference with no deaths, cuts value across a
death, and bootstraps the tail (froggo test_gae idiom, generalized to the [T,P,N,A] agent axis)."""
import os
import sys

import torch

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from ppo_team import _gae


def ref_gae_no_done(rew_team, val, v_last, gamma, lam):
    """Plain GAE (no done masking), team reward broadcast to agents — the reference _gae must equal
    this when done is all-zero."""
    T = rew_team.shape[0]
    rew = rew_team.unsqueeze(-1).expand_as(val)
    adv = torch.zeros_like(val); last = torch.zeros_like(val[0])
    for t in range(T - 1, -1, -1):
        v_next = val[t + 1] if t + 1 < T else v_last
        delta = rew[t] + gamma * v_next - val[t]
        last = delta + gamma * lam * last
        adv[t] = last
    return adv, adv + val


def test_reduces_to_reference_without_dones():
    T, P, N, A = 6, 1, 2, 3
    torch.manual_seed(0)
    rew = torch.randn(T, P, N)
    val = torch.randn(T, P, N, A)
    v_last = torch.randn(P, N, A)
    done = torch.zeros(T, P, N, A)
    adv, ret = _gae(rew, val, done, v_last, 0.98, 0.95)
    radv, rret = ref_gae_no_done(rew, val, v_last, 0.98, 0.95)
    assert torch.allclose(adv, radv, atol=1e-6) and torch.allclose(ret, rret, atol=1e-6)


def test_value_does_not_flow_across_death():
    """An agent that dies at t=1 must have no value flowing from t=2 into t<=1."""
    T, gamma, lam = 4, 0.9, 1.0
    rew = torch.zeros(T, 1, 1)
    rew[:, 0, 0] = torch.tensor([1.0, 1.0, 5.0, 5.0])           # big reward AFTER the death at t=1
    val = torch.zeros(T, 1, 1, 1)
    v_last = torch.zeros(1, 1, 1)
    done = torch.zeros(T, 1, 1, 1); done[1, 0, 0, 0] = 1.0       # agent dies at t=1
    adv, ret = _gae(rew, val, done, v_last, gamma, lam)
    # at t=1 nonterm=0 -> last resets; adv[1] = rew[1] = 1.0 (no post-death reward leaks in)
    assert abs(float(adv[1, 0, 0, 0]) - 1.0) < 1e-6
    # at t=0: delta = rew[0] + gamma*v(t1)*nonterm - v0 = 1.0; last = delta + gamma*lam*nonterm(t0)*last(t1)
    # nonterm at t=0 is 1, last(t1)=adv[1]=1.0 -> adv[0] = 1.0 + 0.9*1.0 = 1.9
    assert abs(float(adv[0, 0, 0, 0]) - 1.9) < 1e-6


def test_tail_bootstrap():
    """A truncated-but-alive agent bootstraps v_last into the final delta."""
    T, gamma, lam = 2, 0.9, 0.95
    rew = torch.zeros(T, 1, 1)
    val = torch.zeros(T, 1, 1, 1)
    v_last = torch.ones(1, 1, 1) * 10.0
    done = torch.zeros(T, 1, 1, 1)
    adv, ret = _gae(rew, val, done, v_last, gamma, lam)
    # last step delta = 0 + gamma*v_last - 0 = 9.0
    assert abs(float(adv[1, 0, 0, 0]) - 9.0) < 1e-6
