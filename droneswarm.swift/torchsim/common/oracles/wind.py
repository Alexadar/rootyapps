"""Wind oracle — Dryden turbulence (offline series generator) + logarithmic mean-wind shear + the
hot-path sampler. SOURCES wind (MIL-F-8785C / MIL-HDBK-1797).

Split by where it runs:
  * dryden_series_np  — OFFLINE (schedule pregen only, numpy). Generates a per-env gust time series
    [T,3]. Implemented as a first-order Gauss-Markov / Ornstein-Uhlenbeck process per axis — the
    1st-order Dryden realization (SOURCES: acceptable low-order form). Exact stationary variance
    sigma^2 and autocorrelation rho(tau)=exp(-tau*V/L); by Taylor frozen-turbulence the SPATIAL
    correlation is rho(r)=exp(-r/L) (the audit's oracle: rho(20 m, L=94.73 m)=0.8097). Uses
    scipy.signal.lfilter over the time axis (vectorized C IIR) — NO python loop even offline.
  * shear_factor, wind_at — HOT PATH (torch, called inside _core). Pure broadcast, NO loops.

The pregenerated [N,T,3] gust table + [N,3] mean wind make the sim's wind fully deterministic
(zero runtime RNG -> batch==singles bit-identity). The net gets NO true-wind obs (it infers wind
from its own dynamics — prefer-learnable-features); wind enters only through the drone's air-relative
velocity in the drag term.

Dryden V semantics note (SOURCES conflict #7): MIL defines V as vehicle AIRSPEED; the pregenerated
per-env table uses the mean WIND speed as the advection rate (frozen turbulence past a station).
This under-samples encounter frequency for a fast drone — an accepted approximation of the offline
pregen format, documented here.
"""
import numpy as np
import torch


def dryden_series_np(rng, T, dt, V_mean, sigma3, L3, v_floor=2.0):
    """Generate one env's gust series [T,3] (numpy, OFFLINE). First-order OU per axis with exact
    stationary variance sigma^2 and per-step AR coefficient phi=exp(-dt*V/L). rng = np.random.Generator,
    sigma3/L3 = per-axis [3]. V_mean floored at v_floor so a near-calm env still has a finite
    correlation time. Uses lfilter (no python loop)."""
    from scipy.signal import lfilter
    V = max(float(V_mean), v_floor)
    sigma3 = np.asarray(sigma3, np.float64)
    L3 = np.asarray(L3, np.float64)
    phi = np.exp(-dt * V / L3)                                     # [3] AR(1) coefficient per axis
    sig_step = sigma3 * np.sqrt(np.clip(1.0 - phi * phi, 1e-12, None))   # innovation std for stationary var
    white = rng.standard_normal((T, 3))
    out = np.empty((T, 3), np.float64)
    for j in range(3):                                            # OFFLINE-LOOP-OK: 3 axes, vectorized IIR inside
        # x[k] = phi*x[k-1] + sig_step*white[k]  <=>  lfilter(b=[sig_step], a=[1,-phi])
        out[:, j] = lfilter([sig_step[j]], [1.0, -phi[j]], white[:, j])
    return out.astype(np.float32)


def dryden_length_scales(altitude_m, L_w, L_uv):
    """Per-axis Dryden length scales [3] = (L_u, L_v, L_w). Low-altitude band uses the horizontal
    scales for u,v and the vertical scale for w (SOURCES wind). Returned as a numpy [3] for the
    schedule. (Altitude-dependent MIL forms exist; v1 uses the fixed low-alt band.)"""
    return np.array([L_uv, L_uv, L_w], np.float64)


def shear_factor(z_agl, z0, z_ref, eps=1e-6):
    """Logarithmic mean-wind shear multiplier u(z)/u(z_ref) = ln(z/z0)/ln(z_ref/z0) (SOURCES wind).
    z_agl [...] height above ground [m] -> [...]. Clamped so z > z0 (log positive) and factor >= 0.
    Torch, loop-free."""
    z = torch.clamp(z_agl, min=z0 * 1.001)
    num = torch.log(z / z0)
    den = float(np.log(z_ref / z0))
    return torch.clamp(num / den, min=0.0)


def wind_at(gust_t, mean_wind, z_agl, z0, z_ref):
    """Total wind velocity at drone altitude. gust_t [N,3] this-tick gust (sliced from the pregen
    table), mean_wind [N,3], z_agl [P,N,D] -> [P,N,D,3]. total = (mean + gust) * shear(z). The mean
    and gust are horizontal-ish world vectors; shear scales the whole vector by the height profile.
    Broadcast, loop-free."""
    base = (mean_wind + gust_t)[None, :, None, :]                 # [1,N,1,3] -> broadcast over P,D
    sf = shear_factor(z_agl, z0, z_ref)[..., None]                # [P,N,D,1]
    return base * sf
