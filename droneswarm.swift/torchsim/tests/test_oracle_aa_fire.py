"""aa_fire oracle tests — SOURCES aa-fire T2-T5 hand vectors: Rayleigh/CEP p_hit table, lead-intercept
quadratic, flat-fire closed forms (+ Euler dt-convergence against them), deterministic resolve_fire."""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import torch
import numpy as np

from oracles import aa_fire
from world_config_drone import WorldConfig


def test_p_hit_rayleigh_table():
    # SOURCES T4: P = 1 - exp(-(r/sigma)^2/2) at r/sigma = 0.5,1,2,3. dist*sigma_ang = 1.0 -> sigma=1.
    r = torch.tensor([0.5, 1.0, 2.0, 3.0], dtype=torch.float64)
    p = aa_fire.p_hit(torch.tensor(100.0, dtype=torch.float64), r, 0.01)
    exp = torch.tensor([0.11750, 0.39347, 0.86466, 0.98889], dtype=torch.float64)  # T4 table
    assert torch.allclose(p, exp, atol=5e-5, rtol=0.0)
    # T4 named: rifleman 100 m, 3 mrad, r=0.15 -> 0.1175; 30mm 800 m, 0.5 mrad, r=0.25 -> 0.1774
    assert abs(float(aa_fire.p_hit(torch.tensor(100.0), torch.tensor(0.15), 0.003)) - 0.1175) < 1e-4
    assert abs(float(aa_fire.p_hit(torch.tensor(800.0), torch.tensor(0.25), 5e-4)) - 0.1774) < 1e-4


def test_p_hit_cep_and_r95():
    # SOURCES T3: CEP = sqrt(2 ln 2)*sigma = 1.17741*sigma -> P=0.5; R95 = 2.4477*sigma -> P=0.95.
    sig = 200.0 * 0.005  # dist*sigma_ang = 1.0
    assert abs(float(aa_fire.p_hit(torch.tensor(200.0), torch.tensor(1.17741 * sig), 0.005)) - 0.5) < 1e-4
    assert abs(float(aa_fire.p_hit(torch.tensor(200.0), torch.tensor(2.4477 * sig), 0.005)) - 0.95) < 1e-4


def test_lead_solution_hand_case():
    # SOURCES T5: p=(100,0,0), v=(0,20,0), s=300 -> t=0.334077 s, aim=(100,6.68155,0), |aim|=100.2230.
    t, aim, feas = aa_fire.lead_solution(torch.tensor([100.0, 0.0, 0.0]),
                                         torch.tensor([0.0, 20.0, 0.0]), 300.0)
    assert bool(feas)
    assert abs(float(t) - 0.334077) < 1e-4
    assert torch.allclose(aim, torch.tensor([100.0, 6.68155, 0.0]), atol=1e-3, rtol=0.0)
    assert abs(float(aim.norm()) - 100.2230) < 1e-3
    assert abs(float(aim.norm()) - 300.0 * float(t)) < 1e-3  # intercept identity |aim| = s*t


def test_lead_stationary_and_infeasible():
    # v=0 -> t = |p|/s exactly; aim = p. |p|=50 (3-4-5 scaled), s=200 -> t=0.25.
    p = torch.tensor([30.0, 40.0, 0.0])
    t, aim, feas = aa_fire.lead_solution(p, torch.zeros(3), 200.0)
    assert bool(feas) and abs(float(t) - 0.25) < 1e-6
    assert torch.allclose(aim, p, atol=1e-5, rtol=0.0)
    # target receding at 50 m/s, muzzle 30 m/s: both quadratic roots negative -> infeasible.
    _, _, feas2 = aa_fire.lead_solution(torch.tensor([100.0, 0.0, 0.0]),
                                        torch.tensor([50.0, 0.0, 0.0]), 30.0)
    assert not bool(feas2)


def test_flat_fire_closed_forms():
    # SOURCES T2 (McCoy flat fire): u0=948, k=1.17e-3, x=100 -> u = 948*exp(-0.117) = 843.3 m/s,
    # t = (exp(0.117)-1)/(k*u0) = 0.11190 s, drop = 0.5*g*t^2 = 6.14 cm.
    u0, k, x = torch.tensor(948.0, dtype=torch.float64), 1.17e-3, torch.tensor(100.0, dtype=torch.float64)
    u = aa_fire.flat_fire_speed(u0, k, x)
    t = aa_fire.flat_fire_time(u0, k, x)
    assert abs(float(u) - 843.3) < 0.1
    assert abs(float(t) - 0.11190) < 1e-4
    assert abs(0.5 * 9.80665 * float(t) ** 2 - 0.0614) < 1e-4  # T2 drop 6.14 cm
    # k -> 0 limits: u -> u0, t -> x/u0 (vacuum flat fire).
    assert abs(float(aa_fire.flat_fire_time(u0, 1e-9, x)) - 100.0 / 948.0) < 1e-6
    assert abs(float(aa_fire.flat_fire_speed(u0, k, torch.zeros((), dtype=torch.float64))) - 948.0) < 1e-9


def test_flat_fire_euler_dt_convergence():
    # Flat fire is the ODE du/dt = -k u^2 (=> u(x)=u0 e^{-kx}, t(x)=(e^{kx}-1)/(k u0)). Explicit-Euler
    # integrate to T = flat_fire_time(x=100); error vs flat_fire_speed(x=100) must halve with dt (slope~1).
    u0, k, x = 948.0, 1.17e-3, 100.0
    T = float(aa_fire.flat_fire_time(torch.tensor(u0, dtype=torch.float64), k, torch.tensor(x, dtype=torch.float64)))
    u_exact = float(aa_fire.flat_fire_speed(torch.tensor(u0, dtype=torch.float64), k, torch.tensor(x, dtype=torch.float64)))
    errs = []
    for n in (64, 128):  # Richardson: dt and dt/2
        dt, u = T / n, u0
        for _ in range(n):
            u = u - dt * k * u * u
        errs.append(abs(u - u_exact))
    ratio = errs[0] / errs[1]
    assert 1.7 < ratio < 2.3  # first-order convergence


def test_resolve_fire_deterministic():
    # hit = fire_gate * (roll < prob): strict <, gate masks, roll==prob is a miss.
    gate = torch.tensor([1.0, 1.0, 0.0, 1.0])
    prob = torch.tensor([0.5, 0.5, 0.9, 0.3])
    roll = torch.tensor([0.4, 0.6, 0.1, 0.3])
    hit = aa_fire.resolve_fire(gate, prob, roll)
    assert torch.equal(hit, torch.tensor([1.0, 0.0, 0.0, 0.0]))


def test_maneuver_extra_var_jinking():
    # SOURCES error budget: sigma_m^2 = (0.5 a_perp t_f)^2 * penalty. a_perp=30, t_f=0.334077 (T5 TOF),
    # penalty=0.5 -> (5.011155)^2 * 0.5 = 12.5559. Jinking must lower P(hit) with WorldConfig params.
    ev = aa_fire.maneuver_extra_var(torch.tensor(30.0), torch.tensor(0.334077), 0.5)
    assert abs(float(ev) - 12.5559) < 1e-3
    cfg = WorldConfig()
    d = torch.tensor(10.0)
    tf = d / cfg.aa_muzzle_soldier
    p0 = aa_fire.p_hit(d, cfg.aa_target_radius, cfg.aa_sigma_ang)
    p1 = aa_fire.p_hit(d, cfg.aa_target_radius, cfg.aa_sigma_ang,
                       aa_fire.maneuver_extra_var(torch.tensor(20.0), tf, cfg.aa_maneuver_penalty))
    p2 = aa_fire.p_hit(d, cfg.aa_target_radius, cfg.aa_sigma_ang,
                       aa_fire.maneuver_extra_var(torch.tensor(40.0), tf, cfg.aa_maneuver_penalty))
    assert float(p1) < float(p0) and float(p2) < float(p1)  # monotone: harder jink -> lower P


def test_batched_vectorization():
    # [P=2, N=3, K=4] batch equals the per-element call at index [1,2,3] (family [P,N,K,...] convention).
    torch.manual_seed(0)
    rel = torch.randn(2, 3, 4, 3) * 50.0 + torch.tensor([80.0, 0.0, 20.0])
    vel = torch.randn(2, 3, 4, 3) * 10.0
    t, aim, feas = aa_fire.lead_solution(rel, vel, 300.0)
    assert t.shape == (2, 3, 4) and aim.shape == (2, 3, 4, 3) and feas.shape == (2, 3, 4)
    t1, aim1, feas1 = aa_fire.lead_solution(rel[1, 2, 3], vel[1, 2, 3], 300.0)
    assert torch.allclose(t[1, 2, 3], t1, atol=1e-6, rtol=0.0)
    assert torch.allclose(aim[1, 2, 3], aim1, atol=1e-6, rtol=0.0)
    assert bool(feas[1, 2, 3]) == bool(feas1)
    dist = rel.norm(dim=-1)
    p = aa_fire.p_hit(dist, 0.2, 0.024)
    assert p.shape == (2, 3, 4)
    assert torch.allclose(p[1, 2, 3], aa_fire.p_hit(dist[1, 2, 3], 0.2, 0.024), atol=1e-7, rtol=0.0)
