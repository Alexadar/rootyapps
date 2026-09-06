"""common.controller — the differentiable VELOCITY-TRACKING geometric flight controller.

Turns a desired world-frame velocity reference `v_ref` into a quadrotor collective thrust + body-rate
command (the level the physics `quad_step` integrates). This is the "flight is ALGORITHMIC" half of the
AI-commander design: the nav-field gives a route direction, `v_ref = flow·v_cruise (+ optional residual)`
turns it into a velocity to hold, and this controller makes the drone hold it. Because it guarantees the
drone CAN fly (thrust is gravity-compensated by construction), an RL policy never has to learn low-level
flight — it only issues higher-level commands. Refs: vector-field guidance → velocity control (AIAA 2021,
doi 10.2514/6.2021-0782); residual RL over a base controller (Johannink et al. arXiv:1812.03201; diff-sim
residual Luo et al. arXiv:2410.03076).

SINGLE SOURCE OF TRUTH: arena's env_drone._core calls this for the base, then wraps its AI velocity-override
+ urgency (added into `v_ref` before the call) and battery gate (multiplied into `thrust` after) around it;
the cherrypick demo calls it bare (no AI, no battery). Pure broadcast ops over arbitrary leading dims, no
python branch/loop ([[no-loops-in-engine]]); differentiable in `v_ref`, the state, and every gain.
"""
import torch

from common.oracles import rotation as ROT


def velocity_track(vel, quat, v_ref, d_vref, k_v, k_R, tau, dt, mass, gravity, t_max, omega_max):
    """One control tick. Shapes broadcast over any leading dims [...]; the last dim is 3 (world x,y,z) for
    the vectors, 4 for `quat` (w,x,y,z).

    vel   [...,3]  current world velocity        quat [...,4]  current attitude (body->world)
    v_ref [...,3]  desired world velocity         d_vref [...,3] LOW-PASS reference STATE (carry across ticks)
    k_v,k_R,tau    tracking / attitude / filter gains (scalars or broadcastable tensors; softplus'd upstream)
    dt,mass,gravity,t_max,omega_max  physics constants (floats)

    Returns (thrust [...], omega_cmd [...,3] BODY rates, d_vref [...,3] updated filter state)."""
    d_vref = d_vref + (v_ref - d_vref) * (dt / tau)                    # LOW-PASS the reference (anti-shake guardrail)
    a_des = k_v * (d_vref - vel)                                       # [...,3] commanded acceleration (P on velocity)
    f_des = mass * a_des                                               # desired thrust vector (world), pre-gravity
    f_des = torch.cat([f_des[..., :2], f_des[..., 2:3] + mass * gravity], -1)   # + gravity compensation on z -> can hover
    bodyz = ROT.body_z_axis(quat)                                     # [...,3] current thrust axis (world)
    thrust = (f_des * bodyz).sum(-1).clamp(0.0, t_max)                # collective thrust = f_des projected on body-z
    bodyz_des = f_des / (f_des.norm(dim=-1, keepdim=True) + 1e-6)     # desired thrust direction (unit)
    err_w = ROT.shortest_arc(bodyz, bodyz_des)                       # WORLD-frame attitude-error rotation vector
    err_b = ROT.quat_rotate(ROT.quat_conjugate(quat), err_w)        # -> BODY frame (quad_step integrates BODY rates)
    omega_cmd = (k_R * err_b).clamp(-omega_max, omega_max)          # body-rate command (P on attitude error)
    return thrust, omega_cmd, d_vref
