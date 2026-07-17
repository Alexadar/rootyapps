"""Quadrotor dynamics oracle — CTBR "Level-A" response model (SOURCES quadrotor-ctbr §1.4).

The drone brain outputs Collective-Thrust + Body-Rates (the sim-to-real-preferred action space,
Kaufmann et al. Nature 2023). Level A models the low-level Betaflight rate controller as first-order
tracking (the structure of Molchanov/SimpleFlight's motor model), so we integrate the honest rigid
body without needing per-motor PID gains we don't have:

    omega <- omega_cmd + (omega - omega_cmd) exp(-dt/tau_omega)     # body-rate first-order lag (EXACT ZOH)
    quat  <- quat (x) Exp(omega dt)                                  # attitude kinematics (rotation oracle)
    a     <- ge*thrust/m * bodyZ(quat) + [0,0,-g] + drag(v - wind)   # Newton translational
    v <- v + a dt ;  p <- p + v dt                                   # symplectic (semi-implicit) Euler

The rate-lag update is the exact zero-order-hold solution of omega_dot=(omega_cmd-omega)/tau, so it
is unconditionally stable at the 50 Hz game tick (SOURCES timestep note). Collective thrust is applied
directly (its ~30 ms lag ~ 1.5 ticks is a documented v1 simplification; the attitude channel, which
governs wind response and feel, is the one that carries lag). Ground effect enters as a thrust
MULTIPLIER (aero oracle). Pure broadcast tensor ops, NO loops. Everything batches over [P,N,D].
"""
import torch

from . import rotation as R
from . import aero as A


def rate_track(omega, omega_cmd, tau_omega, dt):
    """First-order body-rate tracking (exact ZOH). omega,omega_cmd [...,3] -> [...,3]."""
    alpha = torch.exp(torch.as_tensor(-dt / tau_omega, dtype=omega.dtype, device=omega.device))
    return omega_cmd + (omega - omega_cmd) * alpha


def quad_step(pos, vel, quat, omega, thrust, omega_cmd, wind_vel, ge_factor,
              mass, tau_omega, drag_quad, drag_lin, g, dt):
    """One physics tick of the CTBR Level-A quadrotor. All entity tensors [...,3] / quat [...,4],
    scalars are python floats or 0-d tensors. `thrust` [...] = collective thrust FORCE [N] (env maps
    the action to it), `ge_factor` [...] = ground-effect thrust multiplier (aero oracle). Returns
    (pos, vel, quat, omega). Semi-implicit Euler (velocity before position). Loop-free."""
    omega = rate_track(omega, omega_cmd, tau_omega, dt)
    quat = R.quat_integrate(quat, omega, dt)
    bodyz = R.body_z_axis(quat)                                    # world thrust direction [...,3]
    thrust_accel = (ge_factor * thrust / mass)[..., None] * bodyz  # [...,3]
    grav = torch.zeros_like(thrust_accel)
    grav[..., 2] = -g
    v_air = vel - wind_vel
    a = thrust_accel + grav + A.drag_accel(v_air, drag_quad, drag_lin)
    vel = vel + a * dt
    pos = pos + vel * dt
    return pos, vel, quat, omega
