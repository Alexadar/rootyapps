"""STEP-0 gate acceptance — the droneswarm control problem is playable AND non-degenerate at the
tuned WorldConfig, and the gate metrics move the right way with difficulty (froggo test_gate idiom).

Pure numpy, fast (a few thousand pursuit samples). Run with `pytest tests/test_gate.py -q`.
"""
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import gate_intercept as G
from world_config_drone import WorldConfig


def test_gate_default_config_playable_and_nondegenerate():
    cfg = WorldConfig()
    rep = G.run_gate(cfg, M=4096, seed=0)
    checks, ok = G.verdict(rep)
    assert ok, f"gate FAILED at default config: {checks} :: {rep}"
    # spell the four out so a regression names the offender
    assert rep["hover_margin_worst_wind"] >= 1.5
    assert rep["intercept_rate_maneuver"] > 0.95
    assert 0.05 * rep["episode_horizon_s"] < rep["intercept_time_p50"] < 0.85 * rep["episode_horizon_s"]
    assert rep["intercept_advantage"] > 0.5
    assert 0.3 < rep["aa_loss_nominal"] < 0.9


def test_hover_margin_monotone_decreasing_in_wind():
    cfg = WorldConfig()
    W = np.array([0.0, 4.0, 8.0, 12.0, 16.0])
    m = G.hover_margin(cfg, W)
    assert np.all(np.diff(m) < 0.0), f"hover margin should fall with wind: {m}"
    assert m[0] == cfg.drone_t2w                      # zero wind -> margin is exactly T2W


def test_jinking_reduces_aa_loss():
    """The sourced sigma_maneuver term must make a jinking approach strictly safer than a straight one
    (this is the physical reason the policy will learn to evade — see SOURCES aa-fire error budget)."""
    cfg = WorldConfig()
    a_lat = cfg.gravity * np.sqrt(cfg.drone_t2w ** 2 - 1.0)
    v = 0.8 * cfg.drone_speed_max
    straight = G.aa_loss_fraction(cfg, v, jink_accel=0.0)
    jink = G.aa_loss_fraction(cfg, v, jink_accel=a_lat)
    assert jink < straight, f"jinking must lower AA loss: straight={straight} jink={jink}"


def test_aa_loss_monotone_in_approach_speed():
    """Faster approach = less dwell in the ring = fewer shots = lower loss (a real, exploitable gradient)."""
    cfg = WorldConfig()
    losses = [G.aa_loss_fraction(cfg, v, jink_accel=0.0) for v in (8.0, 14.0, 20.0)]
    assert losses[0] >= losses[1] >= losses[2], f"loss should fall as approach speed rises: {losses}"


def test_constant_action_cannot_hunt():
    """The degeneracy guard: no fixed thrust vector systematically intercepts an evading target,
    while a maneuvering pursuer does (else the env is degenerate and RL is pointless)."""
    cfg = WorldConfig()
    p0, v0, q0, ud = G.sample_geometry(cfg, 2048, seed=1)
    hit_con, _, _ = G._run_pursuit(cfg, p0, v0, q0, ud, maneuver=False)
    hit_man, _, _ = G._run_pursuit(cfg, p0, v0, q0, ud, maneuver=True)
    assert hit_con.mean() < 0.25, f"constant action clears too much ({hit_con.mean():.2f}) -> degenerate"
    assert hit_man.mean() - hit_con.mean() > 0.5
