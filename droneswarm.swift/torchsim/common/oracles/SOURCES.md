# SOURCES.md — the physics research behind every oracle (DO NOT MAKE PHYSICS UP)

Six web-research reports (verified citations, formulas, parameters, numeric unit-test packages)
plus a completeness audit. Every formula implemented in oracles/*.py MUST trace to a section here;
every parameter to a table row. Generated 2026-07-16 by the droneswarm-physics-research workflow.
Audit resolutions (conflicts, gaps G1-G8) are binding — see the '## AUDIT' section.



====================================================================================================
# REPORT: reference-sims-parity
====================================================================================================

# Parity Oracles & Parameter Sources for a Vectorized Drone-Swarm Sim

## 1) Recommended model: gym-pybullet-drones `Physics.DYN` as THE parity oracle

**Why this one:** it is the only widely-used reference whose explicit-dynamics path is ~20 lines of plain NumPy (`BaseAviary._dynamics`), fully deterministic, contact-free, and uses a fixed-step integrator — so a PyTorch broadcast reimplementation can match it to float64 round-off. MIT-licensed. Paper: Panerati et al., *"Learning to Fly — a Gym Environment with PyBullet Physics for Reinforcement Learning of Multi-agent Quadcopter Control"*, IROS 2021, pp. 7512–7519.

**Source of equations (verified):** `gym_pybullet_drones/envs/BaseAviary.py` at https://raw.githubusercontent.com/utiasDSL/gym-pybullet-drones/main/gym_pybullet_drones/envs/BaseAviary.py — methods `_dynamics` and `_integrateQ`.

### Discrete update (verbatim semantics, dt = 1/240 s default; per drone, all trivially batchable)

Inputs: motor speeds `rpm ∈ R^4` (GPD's "RPM" units — see caveat below), state `(p, q, v, ω)` with quaternion in **[x,y,z,w]** (PyBullet convention) and `ω` = body rates (stored under the misleading name `rpy_rates`).

```
F_j      = KF * rpm_j^2                                   j = 0..3          [N]
T_world  = R(q) @ [0, 0, ΣF_j]                                              [N]
τ_x      = (L/√2) * (−F_0 − F_1 + F_2 + F_3)              # code: x_torque = -(f0+f1-f2-f3)*(L/√2)
τ_y      = (L/√2) * (−F_0 + F_1 + F_2 − F_3)
τ_z      = KM * (−rpm_0² + rpm_1² − rpm_2² + rpm_3²)      # sign flipped if DRONE_MODEL == RACE
τ        = τ − ω × (J ω)                                   # gyroscopic term
a        = (T_world − [0,0,G·M]) / M                       # G = 9.8 exactly (not 9.81!)
ω̇        = J⁻¹ τ
# --- integration, EXACT statement order (matters for bit-parity): ---
v  ← v + dt·a                                              # (3)
ω  ← ω + dt·ω̇                                             # (4)
p  ← p + dt·v                                              # (5) uses NEW v  → semi-implicit Euler
q  ← [cos(θ)·I₄ + (2/‖ω‖)·sin(θ)·Λ(ω)] q,  θ = ‖ω‖·dt/2   # (6) uses NEW ω; exact exp-map, ‖q‖ preserved
```

with `Λ(ω) = 0.5·[[0,r,−q,p],[−r,0,p,q],[q,−p,0,r],[−p,−q,−r,0]]` (from `_integrateQ`; skip update if `‖ω‖≈0`). This is symplectic (semi-implicit) Euler on translation and rotation, with an exact quaternion exponential for constant ω over the step — replicate exactly, including the statement order confirmed above (quat uses the *incremented* ω, pos the *incremented* v).

**No motor lag, no drag in DYN mode.** `Physics.DYN` is the bare model above; ground effect / drag / downwash exist only as PyBullet external-force add-ons (`PYB_GND`, `PYB_DRAG`, `PYB_DW`, `PYB_GND_DRAG_DW`), with these formulas (same file, useful as secondary oracles):

```
ground effect (per rotor):  ΔF_z = rpm_j²·KF·GND_EFF_COEFF·(PROP_RADIUS/(4·h_j))²      # h_j = prop height; newer commits clip h_j from below — check your pinned commit
drag:   f_drag = R(q)ᵀ · [ −DRAG_COEFF ⊙ Σ_j(2π·rpm_j/60) ] ⊙ v                        # linear in v, ∝ Σ rotor speeds
downwash (drone below another): ΔF_z = −α·exp(−½(δ_xy/β)²),  α = DW_COEFF_1·(PROP_RADIUS/(4δ_z))²,  β = DW_COEFF_2·δ_z + DW_COEFF_3
```

**Vectorization:** every line is elementwise/matmul over a batch; the only scalar branch is the `‖ω‖≈0` guard in `_integrateQ` → replace with `torch.where` on a safe-normalized axis. Nothing resists vectorization.

**Units caveat (do not mix parameter sets):** GPD's `KF=3.16e-10` is calibrated against its "RPM"-scaled command (hover ≈ 14468.4); RotorPy's `k_eta=2.3e-8` is per (rad/s)² (hover ≈ 1788 rad/s ≈ 17 077 true RPM). Both are internally consistent Crazyflie fits; pick one system and its units wholesale.

## 2) Parameters table — cf2x (hardcode these in tests)

From `gym_pybullet_drones/assets/cf2x.urdf` (verified: https://raw.githubusercontent.com/utiasDSL/gym-pybullet-drones/main/gym_pybullet_drones/assets/cf2x.urdf):

| Symbol | Meaning | Units | Value | Source |
|---|---|---|---|---|
| M | mass | kg | 0.027 | cf2x.urdf |
| J | inertia diag (Ixx,Iyy,Izz) | kg·m² | (1.4e-5, 1.4e-5, 2.17e-5) | cf2x.urdf |
| L | arm length (center→motor) | m | 0.0397 | cf2x.urdf `arm` |
| KF | thrust coeff | N/RPM² (GPD units) | 3.16e-10 | cf2x.urdf `kf` |
| KM | yaw-torque coeff | N·m/RPM² | 7.94e-12 | cf2x.urdf `km` |
| T2W | thrust-to-weight | – | 2.25 | cf2x.urdf |
| G | gravity used by GPD | m/s² | **9.8** | BaseAviary (`self.G`) |
| dt | physics step | s | 1/240 | BaseAviary (`pyb_freq=240`) |
| GND_EFF_COEFF | ground-effect gain | – | 11.36859 | cf2x.urdf |
| PROP_RADIUS | prop radius | m | 2.31348e-2 | cf2x.urdf |
| DRAG_COEFF_xy / _z | linear drag coeffs | N·s/m per (rad/s) summed | 9.1785e-7 / 10.311e-7 | cf2x.urdf |
| DW_COEFF_1/2/3 | downwash fit | mixed | 2267.18 / 0.16 / −0.11 | cf2x.urdf |
| prop positions | motor xyz (x-config) | m | (±0.028, ±0.028, 0): m0(+,−) m1(−,−) m2(−,+) m3(+,+) | cf2x.urdf |
| HOVER_RPM | √(G·M/(4KF)) | RPM (GPD) | 14468.429 | derived |
| MAX_RPM | √(T2W·G·M/(4KF)) = 1.5·HOVER | RPM (GPD) | 21702.64 | derived |

RotorPy Crazyflie set (independent cross-check; verified: https://raw.githubusercontent.com/spencerfolk/rotorpy/main/rotorpy/vehicles/crazyflie_params.py, coefficients credited to Förster 2015, *System Identification of the Crazyflie 2.0 Nano Quadrocopter*, ETH Zürich BSc thesis):

| Symbol | Value | Units | Notes |
|---|---|---|---|
| m | 0.03 | kg | includes markers |
| Ixx=Iyy / Izz | 1.43e-5 / 2.89e-5 | kg·m² | |
| rotor pos | (±0.0304, ±0.0304, 0) | m | d = 0.043 m |
| k_eta / k_m | 2.3e-8 / 7.8e-10 | N/(rad/s)², N·m/(rad/s)² | thrust / yaw moment |
| τ_m | 0.072 | s | first-order motor lag |
| ω_rotor range | 0–2500 | rad/s | |
| k_d / k_z | 1.02506e-6 / 7.553e-7 | kg·rad⁻¹ | rotor drag / induced inflow |
| c_Dx,c_Dy,c_Dz | 0 | N/(m/s)² | parasitic drag off by default |

## 3) Alternatives considered (and roles)

- **RotorPy** (Folk, Paulos, Kumar, arXiv:2306.04485, RS4UAVs Workshop @ ICRA 2023; MIT): richest aero (parasitic quadratic drag `D=−‖v_b‖·diag(c_D)·v_b`, rotor drag linear in local airspeed, blade flapping, translational lift, first-order motor lag `ω̇_r=(ω_cmd−ω_r)/τ_m`), and v2.0 has `BatchedMultirotor` (PyTorch, `torchdiffeq` rk4/dopri5). **Not the primary oracle** because default integration is adaptive (RK45/dopri5) — not step-matchable bit-for-bit — but ideal as (a) the motor-lag and drag-term oracle with `rk4` fixed-step, (b) an independent parameter set. Verified: https://raw.githubusercontent.com/spencerfolk/rotorpy/main/rotorpy/vehicles/multirotor.py
- **crazyflow** (utiasDSL; MIT; JAX jit/vmap, `n_worlds × n_drones`, claims up to 914 M steps/s on an RTX 4090, MuJoCo/MJX contacts): first-principles model with per-rotor polynomial thrust/torque `F = c0+c1·ω+c2·ω²`, mixing matrix, piecewise-linear motor accel/decel lag, body-frame linear drag; plus system-identified reduced models (`so_rpy*`: second-order fitted attitude response `ṙpy_rates = A·rpy + B·rpy_rates + C·cmd`, first-order thrust lag, linear drag). **Not the oracle** (coefficients loaded from fitted data files, moving target), but the best architectural template for a JAX/torch-style batched sim and a good "does our CTBR-level abstraction behave like a fitted Crazyflie" sanity check. Verified: https://github.com/utiasDSL/crazyflow, `crazyflow/dynamics/first_principles/dynamics.py`, `crazyflow/dynamics/so_rpy_rotor_drag/dynamics.py`
- **NVIDIA/NTNU Aerial Gym** (BSD-3-Clause): Isaac Gym rigid-body PhysX + GPU-parallel geometric controllers; dynamics fidelity buried in PhysX — not replicable analytically. Use only for RL-throughput ideas. Verified: https://github.com/ntnu-arl/aerial_gym_simulator
- **Isaac Lab direct quadcopter example**: action = `[collective, m_x, m_y, m_z]`; `thrust_z = thrust_to_weight(=1.9) · weight · (a₀+1)/2`, `moment = moment_scale(=0.01) · a₁:₄`, applied as external wrench on the Crazyflie body. This is a *wrench-level* abstraction (no rotor model at all) — useful as the minimal action-space design precedent, useless as a physics oracle. Verified: https://raw.githubusercontent.com/isaac-sim/IsaacLab/main/source/isaaclab_tasks/isaaclab_tasks/direct/quadcopter/quadcopter_env.py
- **Betaflight** (GPL-3.0 firmware) — not a sim, but the authority on CTBR semantics. From `src/main/fc/rc.c` (verified: https://raw.githubusercontent.com/betaflight/betaflight/master/src/main/fc/rc.c), **Actual Rates** (default model since 4.3, PR #9495/#10724):

```
x   = rcCommand ∈ [−1,1];  e = rcExpo/100
shaped    = |x| · (x⁵·e + x·(1−e))
angleRate = x·(rcRates·10) + max(0, rates·10 − rcRates·10) · shaped     [deg/s]
```
  then clamped to `±rate_limit[axis]` (firmware cap 1998 deg/s). Defaults (verified in `src/main/fc/controlrate_profile.c`): `rates_type=ACTUAL`, `rcRates=7` → 70 deg/s center sensitivity, `rates=67` → **670 deg/s max rate**, `rcExpo=0`, all three axes. The output *is* the body-frame angular-velocity setpoint fed to the rate PID loop (P+I on gyro error, D on gyro derivative, feedforward on setpoint derivative; runs at gyro rate up to 8 kHz; output → mixer → motors) — per the Betaflight PID Tuning Guide and `pid.c`. So a real-semantics CTBR interface = `(body-rate setpoint deg/s via Actual-rates curve, normalized collective throttle)`.

**License position:** gym-pybullet-drones MIT, RotorPy MIT, crazyflow MIT, Aerial Gym BSD-3-Clause, Isaac Lab BSD-3-Clause (per repo; not independently re-fetched), Betaflight **GPL-3.0**. We reimplement *equations and constants* (not copyrightable facts), we do not copy code; for Betaflight specifically, keep the reimplementation clean-room-ish (formula above, own code) and never vendor GPL source into the MIT/BSD-style sim.

## 4) Unit-test package

All values below use the cf2x table (Sec. 2), G = 9.8, dt = 1/240, float64 unless stated.

**T1 — hover fixed point (invariant).** `rpm = [14468.429]*4`, level, at rest → per-rotor F = 0.066150 N, ΣF = M·G = 0.264600 N, all torques 0. Assert state unchanged after 480 steps to ≤1e-9 (f64) / ≤1e-5 (f32).

**T2 — vertical step (closed form).** `rpm = [15000]*4` from rest, level: per-rotor F = 3.16e-10·2.25e8 = **0.071100 N**; a_z = 0.2844/0.027 − 9.8 = **0.7333333 m/s²**. After 1 step: v_z = **3.0555556e-3 m/s**, p_z = **1.2731481e-5 m** (pos uses NEW vel — this discriminates semi-implicit from explicit Euler, where p_z would be 0). After 2 steps: v_z = 6.1111111e-3, p_z = 3.8194444e-5 m. After n steps: v_z = n·a_z·dt, p_z = n(n+1)/2·a_z·dt².

**T3 — roll mixer (closed form).** `rpm = [15000,15000,14000,14000]`: F = [0.0711, 0.0711, 0.0619360, 0.0619360] N; τ_x = −(0.018328)·(0.0397/√2) = **−5.14506e-4 N·m**; τ_y = 0; ω̇_x = τ_x/1.4e-5 = **−36.7504 rad/s²**; after 1 step ω_x = **−0.1531268 rad/s**.

**T4 — yaw mixer (closed form).** `rpm = [15000,14000,15000,14000]`: z_torques = [1.78650e-3, 1.55624e-3, 1.78650e-3, 1.55624e-3]; τ_z = −z₀+z₁−z₂+z₃ = **−4.6052e-4 N·m**; ω̇_z = **−21.2221 rad/s²**; after 1 step ω_z = **−8.842546e-2 rad/s**.

**T5 — quaternion exp-map (closed form + invariant).** q₀=(0,0,0,1) [xyzw], ω=(0,0,1) rad/s, one call with dt=0.1 → q = (0, 0, sin 0.05, cos 0.05) = **(0, 0, 0.04997917, 0.99875026)**. Invariants: ‖q‖=1 after every step (exact rotation, assert ≤1e-7 f32); constant-ω integration over N small steps equals one big step (exp-map exactness).

**T6 — motor lag (RotorPy oracle, closed form).** `ω̇_r=(ω_cmd−ω_r)/τ_m`, τ_m = 0.072 s, ω₀=0, ω_cmd=2000 rad/s → exact ω(t)=2000(1−e^(−t/0.072)); at t=0.072 s: **1264.2411 rad/s**. If discretized with exact ZOH `ω⁺ = ω_cmd + (ω−ω_cmd)e^(−dt/τ)` this holds to round-off; explicit Euler at dt=1/240 lands within 0.15 % — pick and pin one.

**T7 — GPD drag formula.** hover rpm (T1), v=(1,0,0), level: Σ 2π·rpm/60 = 4·1515.130 = 6060.52 rad/s; F_drag,x = −9.1785e-7·6060.52 = **−5.5627e-3 N** (z coeff: −10.311e-7·6060.52 = −6.2490e-3 N per unit v_z). Invariant: drag ⊥-free, always opposes body-frame velocity.

**T8 — GPD ground effect.** hover rpm, prop height h=0.05 m: ΔF per rotor = 0.066150·11.36859·(0.0231348/0.2)² = **1.006261e-2 N**. (Pin the commit — newer versions clip small h.)

**T9 — Betaflight Actual rates (closed form).** Defaults (rcRates=7, rates=67): x=1 → **670 deg/s**; x=0.5, expo=0 → 35 + 600·0.25 = **185 deg/s**; x=0.5, rcExpo=54 → 35 + 600·0.5·(0.03125·0.54 + 0.5·0.46) = **109.0625 deg/s**. Invariants: odd symmetry f(−x)=−f(x); f(1)=rates·10 regardless of expo; |f| ≤ 1998 deg/s after clamp.

**T10 — THE parity trajectory (integration test).** Pin gym-pybullet-drones to a tag (e.g. current main / v2.x commit hash), `CtrlAviary(drone_model=DroneModel.CF2X, physics=Physics.DYN, pyb_freq=240, ctrl_freq=240)`, start at p=(0,0,1), q=identity, rest. Command schedule (open-loop RPMs, no controller, no wind): steps 0–239 `HOVER_RPM·[1,1,1,1]`; steps 240–263 `[14700,14700,14200,14200]` (small roll kick); steps 264–479 back to HOVER_RPM (coasting rotation + lateral drift). Record (p,q,v,ω) all 480 steps from `env.pos/quat/vel/rpy_rates`; compare our torch sim elementwise. Tolerances: **f64 vs f64: atol 1e-9 (pos, m), 1e-10 (quat)** — any miss is a model/order bug, not precision; **f32: atol 1e-4 m (pos), 1e-5 (quat), 1e-3 rad/s (ω)** over the full 2 s (float32 eps ≈1.2e-7 × ~500 steps of accumulation; achievable because the scenario avoids sustained tumbling). Parameters that MUST match exactly: M, J, KF, KM, L, G=9.8, dt=1/240, mixer signs (T3/T4), statement order v→ω→p→q with p,q using updated v,ω, quat convention [x,y,z,w], exp-map quat update. Batch check: run 1024 identical drones in one tensor — all rows must equal the single-drone trajectory bitwise.

**T11 — secondary parity (RotorPy).** `BatchedMultirotor`, crazyflie_params, `rk4` fixed step dt=1/240, zero wind, `c_D*=0` (default), set k_d=k_z=k_flap=0 and bypass motor lag (or model it) → same hover/step checks as T1/T2 under RotorPy's units (hover ω_r = √(0.03·9.81/(4·2.3e-8)) = **1788.32 rad/s**); tolerance 1e-6 relative (rk4 vs our Euler differs at O(dt²) — compare accelerations, not long trajectories, or run both with matched integrators).

## 5) Sources

- gym-pybullet-drones `BaseAviary.py` (dynamics, `_integrateQ`, drag/gnd/downwash, G=9.8, dt): https://raw.githubusercontent.com/utiasDSL/gym-pybullet-drones/main/gym_pybullet_drones/envs/BaseAviary.py (fetched)
- cf2x.urdf parameters: https://raw.githubusercontent.com/utiasDSL/gym-pybullet-drones/main/gym_pybullet_drones/assets/cf2x.urdf (fetched); repo/license/paper: https://github.com/utiasDSL/gym-pybullet-drones (MIT; Panerati et al., IROS 2021)
- RotorPy: repo https://github.com/spencerfolk/rotorpy (MIT); dynamics https://raw.githubusercontent.com/spencerfolk/rotorpy/main/rotorpy/vehicles/multirotor.py; params https://raw.githubusercontent.com/spencerfolk/rotorpy/main/rotorpy/vehicles/crazyflie_params.py (all fetched); paper: Folk, Paulos, Kumar, *RotorPy: A Python-based Multirotor Simulator with Aerodynamics for Education and Research*, RS4UAVs Workshop @ ICRA 2023, arXiv:2306.04485; parameter provenance: J. Förster, *System Identification of the Crazyflie 2.0 Nano Quadrocopter*, ETH Zürich, 2015
- crazyflow: https://github.com/utiasDSL/crazyflow (MIT, JAX-batched; fetched) + `crazyflow/dynamics/first_principles/dynamics.py`, `crazyflow/dynamics/so_rpy_rotor_drag/dynamics.py` (fetched)
- Aerial Gym Simulator: https://github.com/ntnu-arl/aerial_gym_simulator (BSD-3-Clause; fetched)
- Isaac Lab quadcopter env: https://github.com/isaac-sim/IsaacLab/blob/main/source/isaaclab_tasks/isaaclab_tasks/direct/quadcopter/quadcopter_env.py (fetched raw)
- Betaflight Actual rates source: https://github.com/betaflight/betaflight/blob/master/src/main/fc/rc.c and defaults https://github.com/betaflight/betaflight/blob/master/src/main/fc/controlrate_profile.c (both fetched raw; GPL-3.0); rate-model background: PR [#9495](https://github.com/betaflight/betaflight/pull/9495), [#10724](https://github.com/betaflight/betaflight/pull/10724); rate calculator https://betaflight.com/docs/wiki/guides/current/Rate-Calculator; PID loop overview: [Betaflight PID Tuning Guide](https://betaflight.com/docs/wiki/guides/current/PID-Tuning-Guide), [pid.c](https://github.com/betaflight/betaflight/blob/master/src/main/flight/pid.c); rates semantics explainer: [Oscar Liang — Rates and Expo](https://oscarliang.com/rates/)


====================================================================================================
# REPORT: wind-dryden
====================================================================================================

# Wind Field & Atmospheric Turbulence for Batched Drone-Swarm Sim — Sourced Models, Discrete Updates, Test Oracles

**Scope**: offline pregeneration of a `[N_envs, T_ticks, 3]` wind array (u = along mean wind, v = lateral, w = vertical), consumed deterministically at runtime. All recursions below are elementwise over the env batch; the only sequential dimension is time, which lives in the offline generator (an `lfilter`/scan over T is allowed there; the runtime hot path is a pure gather + broadcast, satisfying the no-loops rule).

---

## 1) Recommended model

**Total wind at agent i, tick t** (superposition, standard practice per MATLAB Aerospace Blockset which sums mean wind + Dryden turbulence + discrete gust [S3][S4]):

```
W_i(t) = s(z_i) * U_mean_env * x̂_wind        (log-shear mean wind, horizontal)
       + [u_g, v_g, w_g](env, t')             (Dryden turbulence, pregenerated)
       + g(x_adv)                              (optional 1-cosine gust, deterministic)
```

MIL-F-8785C requires the low-altitude turbulence longitudinal axis to be aligned with the prevailing wind direction (quoted in Cole & Wickenheiser §5.1 [S9]) — so generate in wind axes and rotate by the env's fixed wind heading (one 2×2 rotation, broadcast).

### 1a. Mean wind: logarithmic shear profile (neutral surface layer)

Canonical log law (Stull, boundary-layer meteorology texts [S6]):

```
u(z) = (u*/κ) · ln(z/z0)          κ = 0.40
```

Implementation-ready ratio form (u* cancels; this is the form to code):

```
u(z) = u_ref · ln(z/z0) / ln(z_ref/z0),   valid z > z0, neutral stability
s(z) = ln(z/z0) / ln(z_ref/z0)            (elementwise over agent z tensor)
```

Power-law alternative (Wikipedia + Hsu et al. 1994 [S7]; IEC 61400-1 NWP [S8]):

```
u(z) = u_ref · (z/z_ref)^α        α = 0.143 open land (neutral), 0.11 open water, 0.20 IEC 61400-1 design profile
```

Recommend the log law (physically grounded in similarity theory, gives you terrain via z0); apply `s(z_i)` at runtime to the horizontal mean-wind components only (elementwise). Do **not** shear-scale the turbulence — its height dependence is already in σ(h), L(h) below; evaluate those at a fixed nominal swarm altitude h₀ per env.

### 1b. Turbulence: Dryden model, MIL-F-8785C low-altitude form

**Intensities and length scales for h < 1000 ft** (h in **feet**, W20 = mean wind speed at 20 ft; verified against MATLAB Aerospace Blockset docs which quote MIL-F-8785C / MIL-HDBK-1797 [S3][S4]):

```
σ_w = 0.1 · W20
σ_u = σ_v = σ_w / (0.177 + 0.000823·h)^0.4

L_w = h                                          (MIL-F-8785C convention)
L_u = L_v = h / (0.177 + 0.000823·h)^1.2
```

(MIL-HDBK-1797 uses the halved convention `2L_w = h`, `L_u = 2L_v = h/(0.177+0.000823h)^1.2` with compensating factors of 2 in its PSDs [S3]. Pick **one** convention; the 8785C one above is what the equations below assume.) Sanity anchor built into the formula: at h = 1000 ft the parenthetical is exactly 1.0, so L_u = L_v = L_w = 1000 ft and σ_u = σ_v = σ_w. Units: evaluate the parenthetical with h in ft; L inherits ft (convert ×0.3048 m/ft); σ inherits W20's units.

**Spectra / shaping filters (MIL-F-8785C via [S4])**, ω in rad/s, V = speed of the vehicle relative to the air mass:

```
Φ_u(ω) = σ_u²·(2L_u/πV) · 1/(1+(L_u ω/V)²)
Φ_v(ω) = σ_v²·(L_v/πV) · (1+3(L_v ω/V)²)/(1+(L_v ω/V)²)²      (same form for w with L_w, σ_w)

H_u(s) = σ_u·√(2L_u/(πV)) · 1/(1 + (L_u/V)s)
H_v(s) = σ_v·√(L_v/(πV)) · (1 + √3(L_v/V)s)/(1 + (L_v/V)s)²   (same for w)
```

(Check: ∫₀^∞ Φ dω = σ² for both forms — closed-form integrals π/2 and π; this is invariant (b) in §4.) For hovering/slow drones, V is the speed at which frozen turbulence is swept past the vehicle, i.e. take `V = max(Ū_env, V_min)` with the mean wind — this is Taylor's frozen-turbulence interpretation ([S10], and TurbSim/QBlade practice [S11]); flag: the V_min floor is an engineering guard, not from the spec.

**Discrete-time realization (the documented one — MATLAB "Dryden Wind Turbulence Model (Discrete)" [S3])**, sample time T, η ~ N(0,1) i.i.d. unit-variance noise per channel:

```
u_g[k+1] = (1 − (V·T/L_u))·u_g[k] + √(2·V·T/L_u)·σ_u·η₁[k]
v_g[k+1] = (1 − (V·T/L_v))·v_g[k] + √(2·V·T/L_v)·σ_v·η₂[k]
w_g[k+1] = (1 − (V·T/L_w))·w_g[k] + √(2·V·T/L_w)·σ_w·η₃[k]
```

This is a first-order Gauss–Markov (AR(1)) filter per channel; note MATLAB's discrete block uses first-order forms for v, w too (drops the √3 zero — spectrum is then Lambert/Markov shaped, variance still ≈ σ²). Two refinements, both sourced:

- **Exact variance-preserving update** (recommended; the AR(1) above inflates variance by 1/(1−λT/2), λ = V/L): use the exact Ornstein–Uhlenbeck discretization, exact for any T (Gillespie 1996, Phys. Rev. E 54:2084 [S12]):

```
a = exp(−V·T/L),   u_g[k+1] = a·u_g[k] + σ·√(1−a²)·η[k]     → stationary Var = σ² exactly
```

- **Exact Dryden spectrum for v, w** (if you want the √3 zero): discretize H_v(s) (2nd order, coefficients above) with the bilinear/Tustin transform via `scipy.signal.cont2discrete(..., method='bilinear')` [S13], yielding a Direct-Form-II biquad `y[k] = b0·x[k]+b1·x[k−1]+b2·x[k−2] − a1·y[k−1] − a2·y[k−2]` — still elementwise over the batch, two carried states per env.

**Recommendation**: exact-OU AR(1) for u; biquad (bilinear) for v, w. Generate offline with float64, discard a burn-in of ≥ 5·L_max/V seconds, store as `[N_envs, T, 3]`.

### 1c. Discrete gusts: "1-cosine", MIL-F-8785C

Ramp-and-hold form (MIL-F-8785C, as documented by MATLAB Discrete Wind Gust block [S5]):

```
V_wind(x) = 0                          x < 0
          = (Vm/2)·(1 − cos(πx/dm))    0 ≤ x ≤ dm
          = Vm                         x > dm
```

x = distance penetrated into the gust (= V_rel·(t−t₀) for the frozen field), dm = gust length, Vm = gust amplitude, independently parameterizable per axis. MATLAB defaults: dm = [120 120 80] m, Vm = [3.5 3.5 3.0] m/s, start 5 s [S5].

Return-to-zero full gust (certification form, 14 CFR / CS 25.341 [S14]):

```
U(s) = (Uds/2)·(1 − cos(πs/H)),  0 ≤ s ≤ 2H     (peak Uds at s=H, back to 0 at 2H; H ∈ 30–350 ft investigated)
```

Both are deterministic closed forms — evaluate directly into the precomputed array (pure broadcast over t).

### 1d. Spatial variation at swarm scale — honest, sourced treatment

What real models say:

- Engineering wind fields (TurbSim, QBlade, Mann/Veers) generate a frozen turbulence box "translated through the field of interest at the average velocity … consistent with Taylor's hypothesis" [S11]; the hypothesis itself is Taylor (1938) [S10]: `u'(x, t) = u'(x − Ū·t, 0)`.
- Point-to-point coherence, IEC 61400-1 exponential model (quoted verbatim in [S15]; parameters a = 12, b = 0.12): 

```
γ²(f, r) = exp[−12·√((f·r/Ū_hub)² + (0.12·r/L_c)²)],   L_c = 8.1·Λ₁,  Λ₁ = 42 m for z ≥ 60 m (0.7·z below, 0.7·60 = 42)
```

  and its ancestor Davenport (1961): `γ = exp(−C·δ·f/Ū)` [S15].
- Numbers at drone height z = 10 m (Λ₁ = 7 m, L_c = 56.7 m, Ū = 8 m/s): at r = 5 m separation, DC-limit coherence = exp(−12·0.12·5/56.7) = **0.881**; at r = 20 m it is **0.602**; at r = 20 m and f = 0.5 Hz, γ² ≈ exp(−15.0) ≈ **3·10⁻⁷** — i.e. high-frequency turbulence is fully decorrelated across a 20 m swarm, while the energy-containing low-frequency eddies (scales L_u ≈ 95 m at h = 50 ft) remain mostly common-mode.

**Recommended simplification (defensible, cheap):** one Dryden realization per env applied uniformly to all agents, plus per-agent log-shear s(z_i). This is exact in the DC limit and captures the dominant common-mode gust energy, but overstates coherence at high f / large r — say so in the docstring with the numbers above. **Sourced upgrade at zero runtime randomness:** frozen-field advection (Taylor [S10][S11]) — treat the pregenerated series as a 1-D frozen line sampled at Δξ = Ū·T and let each agent read `series[t − x_i/(Ū·T)]` (per-agent integer index shift = batched gather; fully vectorizable; store T + span/(Ū·T) extra samples). This gives correct streamwise decorrelation; lateral coherence stays 1 (exactly the approximation a frozen 1-D line implies — same one Cole & Wickenheiser relax only by adding a cos²ˢ directional spreading sum [S9]). Full IEC coherence would require a correlated multi-point Cholesky/Veers synthesis per frequency — resists the "one series per env" format; not recommended.

---

## 2) Parameters table

| Symbol | Meaning | Units | Real values | Source |
|---|---|---|---|---|
| W20 | mean wind at 20 ft (6 m) | kt (ft/s) | light 15 kt, moderate 30 kt, severe 45 kt | MIL-F-8785C via [S3][S4] |
| σ_w | vertical turb. intensity | = W20 units | 0.1·W20 (h<1000 ft) | MIL-F-8785C [S3][S4] |
| σ_u, σ_v | horiz. turb. intensity | = W20 units | σ_w/(0.177+0.000823h)^0.4, h in ft | MIL-F-8785C [S3][S4] |
| L_w | vertical length scale | ft | h (8785C) / h/2 (1797) | [S3] |
| L_u, L_v | horiz. length scales | ft | h/(0.177+0.000823h)^1.2 | [S3][S4] |
| T | filter sample time | s | 0.1 s (MATLAB block default noise sample time) | [S3] |
| κ | von Kármán constant | – | 0.40 | Stull [S6] |
| z0 | roughness length | m | sea 0.0002 · smooth snow/mud 0.005 · **open grass field 0.03** · low crops 0.10 · high crops 0.25 · parkland 0.5 · **forest/suburb 1.0** · city ≥2 | Davenport–Wieringa classification (Wieringa 1992; table in Stull) [S6] |
| α | power-law exponent | – | 0.143 open land · 0.11 open sea (Hsu 1994) · 0.20 IEC design | [S7][S8] |
| Vm | gust amplitude | m/s | [3.5, 3.5, 3.0] (defaults) | [S5] |
| dm | gust length | m | [120, 120, 80] (defaults) | [S5] |
| H | cert. gust gradient | ft | 30–350 | 14 CFR 25.341 [S14] |
| a, b, L_c | IEC coherence decrement, offset, scale | –, –, m | 12, 0.12, 8.1·Λ₁ (Λ₁ = 0.7z, z<60 m) | IEC 61400-1 via [S15] |

---

## 3) Alternatives considered

- **Von Kármán model (MIL-F-8785C's preferred form)**: PSD ∝ (1+(1.339Lω/V)²)^(−5/6) — irrational exponent, no exact finite-order shaping filter; requires rational approximation. Dryden exists precisely as the filter-realizable surrogate; both are in the same spec [S4]. Rejected: extra complexity, no gameplay-visible benefit.
- **Kaimal spectra + Veers/Sandia coherent-field synthesis (TurbSim / IEC 61400-1)**: correct multi-point coherence, but needs per-frequency Cholesky over an agent grid → O(P²·F) pregeneration and a spatial interpolation lattice at runtime; wind-turbine tooling, overkill at swarm scale [S15][S11].
- **Sum-of-sinusoids spatio-temporal field** (Cole & Wickenheiser: `y(t)=Σᵢ√(S(ωᵢ)δω)cos(ωᵢt+ψᵢ)`, spatial via k = ω/u₁₀ and cos²ˢ spreading) [S9]: genuinely 2-D spatial, but finite-sum PSD approximation, O(N_freq·N_dir) per sample, and periodic artifacts. Keep as future upgrade path if lateral decorrelation ever matters.
- **Euler AR(1) as-is (MATLAB discrete block)**: fine, documented [S3]; rejected in favor of exact-OU only because Gillespie's form makes the variance test exact instead of tolerance-fudged [S12].
- **CFD/LES fields**: no.

---

## 4) Unit-test package (pytest oracles)

**T1 — MIL low-altitude σ/L closed values** (h in ft):
- h = 1000, W20 = 20 ft/s → parenthetical = 0.177+0.823 = **1.0 exactly** → σ_u = σ_v = σ_w = 2.0 ft/s; L_u = L_v = L_w = 1000 ft. (Exact.)
- h = 50, W20 = 20 ft/s → 0.177+0.04115 = 0.21815; 0.21815^0.4 = 0.54387; 0.21815^1.2 = 0.160882 → σ_w = 2.0, σ_u = σ_v = 2.0/0.54387 = **3.67734 ft/s**; L_w = 50 ft, L_u = L_v = 50/0.160882 = **310.79 ft** (= 94.73 m). rtol 1e-5.

**T2 — AR(1) recursion vs independent reference**: build `dlti([b],[1,−a])` with a = 1−VT/L, b = σ√(2VT/L); feed an identical fixed η sequence to the tensor recursion and `scipy.signal.dlsim`; assert allclose atol 1e-12. Same for the v/w biquad from `cont2discrete(H_v, T, method='bilinear')` [S13]. (Pure implementation identity — no statistics.)

**T3 — stationary variance invariant**: (i) Euler form: closed-form Var∞ = b²/(1−a²) = σ²/(1−λT/2), λ = V/L. Numbers: V=10 m/s, L=100 m, T=0.02 s, σ=1 → a = 0.998, b = 0.0632456, Var∞ = **1.0010010**. (ii) Exact-OU form [S12]: a = e^(−0.002) = 0.9980020, b = √(1−e^(−0.004)) = 0.0631823, Var∞ = **1.0 exactly**. Empirical check: 8192 envs × 2×10⁵ steps after burn-in 5L/V; pooled sample variance within ±1% (AR(1) has few effective samples per series — pool across the batch, that's what it's for).

**T4 — autocorrelation invariant (u-channel is exactly OU)**: R(kT)/R(0) = a^k; with exact-OU a = e^(−λT): ρ(lag 50) = e^(−0.1) = **0.904837**, tolerance ±0.01 pooled over batch.

**T5 — PSD/variance consistency of the continuous forms** (analytic, no sim): ∫₀^∞Φ_u dω = σ_u² and ∫₀^∞Φ_v dω = σ_v² (integrals π/2, π shown in §1b) — assert via `scipy.integrate.quad` < 1e-6 relative.

**T6 — log profile hand values** (z0 = 0.03 m, z_ref = 10 m, u_ref = 5 m/s): u(2 m) = 5·4.199705/5.809143 = **3.61474 m/s**; u(50 m) = 5·7.418581/5.809143 = **6.38526 m/s**. Forest z0 = 1.0: u(2 m) = 5·ln2/ln10 = **1.50515 m/s**. Invariants: u(z_ref) ≡ u_ref; monotone in z; u→0 as z→z0.

**T7 — power law**: u_ref = 5 m/s at 10 m: α = 0.143 → u(50) = 5·5^0.143 = **6.29400 m/s**; α = 0.2 (IEC) → **6.89865 m/s**.

**T8 — 1-cosine gust**: Vm = 3.5 m/s, dm = 120 m: V(30) = 1.75(1−cos π/4) = **0.512563**; V(60) = **1.75** (half amplitude at mid-length, exact); V(90) = **2.987437**; V(≥120) = **3.5**; V(<0) = 0; monotone on [0, dm]. CS-25 form, Uds = 10, H = 100: U(50) = **5**, U(100) = **10** (peak), U(150) = **5**, U(200) = **0**, symmetric about s = H.

**T9 — coherence-based spatial sanity (documentation-level assert)**: IEC γ²(f→0, r) = exp(−1.44·r/L_c): z = 10 m → L_c = 56.7 m → γ²(r=5) = **0.88075**, γ²(r=20) = **0.60172** — used to assert the frozen-line advection path (T10) and to bound the stated error of the uniform-field mode.

**T10 — Taylor advection identity**: with frozen-line indexing, agent at x = m·Ū·T must read exactly the value the x=0 agent read m ticks earlier: `field(x_i, t) == series[t − x_i/(Ū·T)]` (exact integer-shift equality); two agents at equal x get identical wind (lateral coherence 1 by construction).

**T11 — determinism/batch invariants**: same seed → bitwise-equal `[N_envs,T,3]`; envs use independent noise (cross-env correlation of η → |ρ| < 4/√T); no NaN; runtime consumption performs zero RNG calls.

---

## 5) Sources

- [S1] MIL-F-8785C, *Flying Qualities of Piloted Airplanes*, U.S. Military Specification, Nov 5 1980 (turbulence §3.7; formulas verified via [S3][S4][S5] which reproduce it).
- [S2] MIL-HDBK-1797, *Flying Qualities of Piloted Aircraft*, DoD Handbook, 1997 (length-scale convention 2L_w = h; via [S3]).
- [S3] MathWorks Aerospace Blockset, "Dryden Wind Turbulence Model (Discrete)" — discrete difference equations, unit-variance noise, defaults. https://www.mathworks.com/help/aeroblks/drydenwindturbulencemodeldiscrete.html (verified 2026-07).
- [S4] MathWorks, "Dryden Wind Turbulence Model (Continuous)" — Φ_u, Φ_v, Φ_w, H(s), low-altitude σ/L, MIL refs list. https://www.mathworks.com/help/aeroblks/drydenwindturbulencemodelcontinuous.html (verified).
- [S5] MathWorks, "Discrete Wind Gust Model" — 1-cosine formula + defaults, cites MIL-F-8785C. https://www.mathworks.com/help/aeroblks/discretewindgustmodel.html (verified).
- [S6] Davenport–Wieringa roughness classification: Wieringa, J. (1992), "Updating the Davenport roughness classification," *J. Wind Eng. Ind. Aerodyn.* 41; table as presented in Stull, *Practical Meteorology* (log law, κ = 0.4). Table values verified via https://www.researchgate.net/figure/1-The-Davenport-Wieringa-roughness-length-z-0-classification-Table-presented-in-Stull_tbl1_341709759
- [S7] Wikipedia, "Wind profile power law" (α = 0.143 open land; α = 0.11 offshore citing Hsu, Meindl & Gilhousen 1994, *J. Appl. Meteorol.* 33:757–765). https://en.wikipedia.org/wiki/Wind_profile_power_law (verified).
- [S8] IEC 61400-1 (ed. 3/4), Normal Wind Profile model V(z) = V_hub(z/z_hub)^0.2 (design standard; exponent also reproduced in NREL TurbSim User's Guide, NREL/TP-500-39797).
- [S9] Cole, K. & Wickenheiser, A. (2019), "Spatio-Temporal Wind Modeling for UAV Simulations," arXiv:1905.09954 — sum-of-sinusoids field, k = ω/u₁₀, cos²ˢ spreading, MIL-F-8785C wind-alignment requirement. https://arxiv.org/pdf/1905.09954 (verified, §4.14, §5.1–5.6).
- [S10] Taylor, G.I. (1938), "The Spectrum of Turbulence," *Proc. R. Soc. Lond. A* 164:476–490 (frozen-turbulence hypothesis).
- [S11] QBlade documentation, "Wind Field Generator Overview" — turbulence box "translated through the field … consistent with Taylor's hypothesis" (same mechanism as NREL TurbSim). https://docs.qblade.org/src/user/windfield/windfield.html (verified).
- [S12] Gillespie, D.T. (1996), "Exact numerical simulation of the Ornstein-Uhlenbeck process and its integral," *Phys. Rev. E* 54(2):2084–2091 — exact update x⁺ = x·e^(−λT) + σ√(1−e^(−2λT))·n. https://link.aps.org/doi/10.1103/PhysRevE.54.2084 (verified).
- [S13] SciPy documentation, `scipy.signal.cont2discrete` (Tustin/bilinear discretization), `scipy.signal.dlsim` — reference implementations for T2. https://docs.scipy.org/doc/scipy/reference/generated/scipy.signal.cont2discrete.html
- [S14] 14 CFR § 25.341 "Gust and turbulence loads" — U = (Uds/2)(1−cos(πs/H)), 0 ≤ s ≤ 2H, H ∈ 30–350 ft. https://www.law.cornell.edu/cfr/text/14/25.341 (verified via govinfo).
- [S15] Nybø, Nielsen & Godvik (2023), "Investigations of correlation and coherence in turbulence from a large-eddy simulation," *Wind Energy Science* 8:487 — quotes IEC 61400-1(2019) exponential coherence (a=12, b=0.12, L_c=8.1Λ₁, Λ₁=42 m above 60 m) and Davenport (1961) γ = exp(−C·δ·f/Ū). https://wes.copernicus.org/articles/8/487/2023/ (verified). Davenport, A.G. (1961), *Q. J. R. Meteorol. Soc.* 87:194–211.

**Caveats / non-sourced choices flagged**: (a) V_min floor for hovering vehicles in the Dryden λ = V/L (engineering guard on Taylor's hypothesis, not in any spec); (b) evaluating σ(h), L(h) at one nominal altitude per env instead of per-agent (the spec's model is per-point in h; per-agent evaluation is also pure elementwise math if you prefer it, but then each agent needs its own filter state — incompatible with one shared series per env); (c) uniform-field mode's coherence overstatement quantified in T9 rather than corrected.


====================================================================================================
# REPORT: quadrotor-ctbr
====================================================================================================

All sources verified. Compiling the report.

---

# Quadrotor 6-DOF + Rotor/Motor + CTBR Model for a Vectorized Drone-Swarm Sim

**Scope**: kamikaze FPV-style quads, CTBR (collective thrust + body rates) action interface, PyTorch batched tensors, no per-agent loops. Every equation below is quoted from a verified source (see §5); nothing is invented. Verified = I fetched the PDF/source file and read the equation/number.

---

## 1) Recommended model

### 1.1 State (per agent; batch dim B implicit everywhere)

`p ∈ R^{B×3}` world position, `v ∈ R^{B×3}` world velocity, `q ∈ R^{B×4}` unit quaternion body→world (Hamilton, w-first), `ω ∈ R^{B×3}` body rates, `Ω ∈ R^{B×4}` rotor speeds.

### 1.2 Continuous dynamics — Kaufmann/Bauersfeld/Scaramuzza ICRA 2022, Eq. (1); identical structure in Kaufmann et al., Nature 2023, Methods Eq. (1)

```
ṗ = v
q̇ = ½ q ⊗ [0, ω]                                   (quaternion kinematics; also Solà Eq. (200))
v̇ = (1/m) R(q)·(f_prop + f_drag) + g_W ,   g_W = [0,0,−9.81] m/s²
ω̇ = J⁻¹ (τ_prop − ω × Jω) ,               J = diag(Jx,Jy,Jz)
Ω̇ = (1/k_mot)(Ω_cmd − Ω)                            (motor first-order lag)
```

Rotor forces/torques (ICRA22 Eq. (2)–(4); Nature Eq. (2)–(4)):

```
f_i(Ω_i) = [0, 0, c_l·Ω_i²]ᵀ        τ_i(Ω_i) = [0, 0, ±c_d·Ω_i²]ᵀ   (sign = spin direction)
f_prop = Σ_i f_i                     τ_prop = Σ_i τ_i + r_{P,i} × f_i
f_drag = −[k_vx·v_{B,x}, k_vy·v_{B,y}, k_vz·v_{B,z}]ᵀ   (linear body-frame drag, ICRA22 Eq. (3))
```

with `v_B = R(q)ᵀ v` and `r_{P,i}` the propeller position in body frame. For an X-configuration with arm `L` and rotors at `(±L/√2, ±L/√2)` this collapses to the mixing used verbatim in gym-pybullet-drones `BaseAviary._dynamics` (rotor order 0:(+x,+y), 1:(−x,+y), 2:(−x,−y), 3:(+x,−y); `F_i = k_f Ω_i²`):

```
T  =  F0 + F1 + F2 + F3
τx = ( F0 + F1 − F2 − F3)·L/√2
τy = (−F0 + F1 + F2 − F3)·L/√2
τz = (−F0 + F1 − F2 + F3)·k_m/k_f · … i.e. τz = −kmΩ0² + kmΩ1² − kmΩ2² + kmΩ3²
```

i.e. `[T,τx,τy,τz]ᵀ = M·[F0..F3]ᵀ`, `M = [[1,1,1,1],[l,l,−l,−l],[−l,l,l,−l],[−κ,κ,−κ,κ]]`, `l = L/√2`, `κ = k_m/k_f`. `M` and `M⁻¹` (control allocation) are constant 4×4 → one batched matmul.

### 1.3 Discrete update at fixed Δt (implementation-ready)

Integrator choice is itself sourced: ICRA22: *"The dynamics are integrated using a symplectic Euler scheme with step size 1 ms"*; gym-pybullet-drones `_dynamics` uses exactly the symplectic order (velocity before position); Agilicious uses RK4 at 1 ms with explicit/symplectic Euler options. Recommended: **symplectic Euler, Δt = 1 ms** (single force evaluation; RK4 is 4× cost for little gain at 1 kHz).

```
# 1. motor lag (exact ZOH solution of Ω̇=(Ω_cmd−Ω)/τ_m; textbook 1st-order step response, Ogata;
#    Euler-form equivalent is Molchanov et al. 2019: u'_t = u'_{t−1} + (4Δt/T)(u_t − u'_{t−1}), T = 2% settling = 4τ_m)
Ω ← Ω_cmd + (Ω − Ω_cmd)·exp(−Δt/τ_m)

# 2. forces/torques (Eq. 2–4 above)
F = c_l·Ω²                       # B×4
T, τ = (M @ F)                   # B×4 → split; add f_drag = −K_v · (R(q)ᵀ v)

# 3. accelerations
a  = g_W + R(q)·([0,0,T] + f_drag)/m
ω̇ = J⁻¹·(τ_xyz − ω × (J·ω))     # gyroscopic term verbatim in BaseAviary:
                                  # torques = torques − cross(rpy_rates, J·rpy_rates); deriv = J_INV·torques

# 4. symplectic Euler (order quoted from BaseAviary / ICRA22)
v ← v + Δt·a
p ← p + Δt·v          # NEW velocity — semi-implicit
ω ← ω + Δt·ω̇

# 5. quaternion: zeroth-order forward integrator, Solà Eq. (214)–(215)
q ← q ⊗ q{ω·Δt},   q{θ} = exp(θ/2) = [cos(‖θ‖/2), (θ/‖θ‖)·sin(‖θ‖/2)]   (Solà Eq. (101)/(215))
```

Solà §4.6: zeroth-order integrators *"result in unit quaternions by construction (product of two unit quaternions)"* — only float rounding drifts the norm; renormalize `q ← q/‖q‖` periodically. Midward variant `q{ω̄Δt}`, `ω̄ = (ω_n+ω_{n+1})/2` is Solà Eq. (218)–(219); first-order correction `+ Δt²/24·[0, ω_n×ω_{n+1}]` is Eq. (227). For fixed rotation axis the zeroth-order product is **exact** for any Δt (Solà Eq. (228)–(229)) — exploited in tests below.

Vectorization: quaternion product = fixed bilinear map (batched 4-vector ops), `R(q)` = closed-form 3×3 from q, mixing = constant matmul, `exp` map needs a `sinc`-style guard at ‖θ‖→0 (use `torch.where` or series) — numerics, not physics. **Nothing in this model resists vectorization.**

### 1.4 CTBR interface (two sourced fidelity levels)

CTBR is the sim-to-real-preferred action space: ICRA22 shows CTBR ≫ single-rotor-thrust under model mismatch; Swift (Nature 2023): *"the neural network outputs collective thrust and body rates. This control signal is known to combine high agility with good robustness to simulation-to-reality transfer"*; Swift policy runs at 100 Hz, commands go to a Betaflight STM32 flight controller.

**Level A — response model (recommended for the game).** Replace rows ω̇, Ω̇ by first-order tracking of the commands (structure = Molchanov's first-order filter / SimpleFlight's first-order motor model; used at command level in differentiable-sim RL papers):

```
ω ← ω_cmd + (ω − ω_cmd)·exp(−Δt/τ_ω)      # body-rate channel
c ← c_cmd + (c − c_cmd)·exp(−Δt/τ_c)      # mass-normalized collective thrust channel
v ← v + Δt·(g_W + R(q)·[0,0,c] − K_v v_B/m);  p,q as in §1.3
```

Sourced lag values: motor τ_m = **39.1 ms** measured on Agilicious 5-inch (Foehn et al. 2022: *"the motor's time constant of 39.1 ms"*); end-to-end collective-thrust latency **35 ms** (agiNuttx) / **40.15 ms** (Betaflight) from load-cell step tests (same paper); Crazyflie-scale: 2%-settling T̄ = **0.15 s** randomized 0.1–0.2 s (Molchanov et al. 2019) ⇒ τ_m = T/4 ≈ **37.5 ms**. Use τ_c ≈ τ_ω ≈ 0.03–0.05 s (FPV) — bounds sourced, exact split thrust/rate is an engineering choice, flag it as such.
Command clamps (sourced): Crazyflie-class RL: ω_cmd ∈ **[−π, π] rad/s**, collective accel ∈ **[0, 1.6 g]** (SimpleFlight, arXiv:2412.11764). FPV: Betaflight configurator caps commandable rates at **≈1998 deg/s** (betaflight-configurator issue #997); racing trajectories in ICRA22 reach ‖ω‖ = **11.56 rad/s ≈ 662 deg/s** and mass-normalized thrust **33.04 m/s²** (Table IV).

**Level B — explicit low-level (upgrade path, what Swift actually models).** Keep full §1.2 state; rate-PID → per-rotor thrusts via `M⁻¹` → motor lag. Nature 2023 Methods: onboard is a *"proportional–integral–derivative (PID) controller"* (Betaflight + BLHeli32); in sim they model it with fitted gains from Betaflight logs, capturing: D-term reference ≡ 0, I-term reset on throttle cut, body-rate priority under motor saturation; predicts motor commands with **<1% error**; plus grey-box battery/ESC: `P_mot = c_d Ω³/η` (Eq. 5) and `Ω_ss ~ 1 + U_bat + √u_cmd + u_cmd + U_bat·√u_cmd` (Eq. 6). Branchy logic (I-term reset, saturation priority) vectorizes via `torch.where` masks. Gains are not published numerically — needs your own Betaflight log fit; that's why Level A is the default.

---

## 2) Parameters table

### 2.1 Crazyflie 2.x — quoted verbatim from `gym_pybullet_drones/assets/cf2x.urdf` (verified); provenance: Förster, ETH system-ID thesis (DOI 10.3929/ETHZ-B-000214143)

| Symbol | Meaning | Units | Value | Source |
|---|---|---|---|---|
| m | mass | kg | **0.027** | cf2x.urdf |
| Jx, Jy, Jz | inertia diagonal | kg·m² | **1.4e-5, 1.4e-5, 2.17e-5** | cf2x.urdf |
| L | arm length | m | **0.0397** (props at ±0.028,±0.028) | cf2x.urdf |
| k_f | thrust coeff, T_i=k_f·rpm² | N/RPM² | **3.16e-10** (= **2.88e-8** N/(rad/s)², ×(60/2π)²=91.19) | cf2x.urdf / Förster |
| k_m | drag-torque coeff | N·m/RPM² | **7.94e-12** (= **7.24e-10** N·m/(rad/s)²) | cf2x.urdf / Förster |
| κ=k_m/k_f | torque/thrust ratio | m | 0.02513 (derived) | — |
| T2W | thrust-to-weight | – | **2.25** | cf2x.urdf |
| g | gravity in gym-pybullet-drones | m/s² | **9.8** (`self.G = 9.8`) | BaseAviary.py |
| HOVER_RPM | √(mg/(4k_f)) | RPM | **14468.43** (code formula) | BaseAviary.py |
| MAX_RPM | √(2.25·mg/(4k_f)) = 1.5·HOVER | RPM | **21702.64**; MAX_THRUST = 0.59535 N | BaseAviary.py |
| drag_coeff_xy / z | body drag (PYB_DRAG mode: `drag = base_rot·(−DRAG_COEFF·Σ(2π·rpm/60))·vel`) | N/(rad/s · m/s) | **9.1785e-7 / 10.311e-7** | cf2x.urdf + `_drag` |
| gnd_eff_coeff, prop_radius | ground effect `k_f·rpm²·C·(R_p/4h)²` | –, m | **11.36859, 2.31348e-2** | cf2x.urdf + `_groundEffect` |
| dw_coeff_1/2/3 | downwash Gaussian | – | **2267.18, 0.16, −0.11** | cf2x.urdf + `_downwash` |
| T (motor 2% settling) | Crazyflie-class motor lag | s | **0.15** nominal, DR 0.1–0.2 (τ_m≈0.0375) | Molchanov 2019 |
| ω_cmd, c_cmd limits | CTBR clamps (CF2.1 RL) | rad/s, m/s² | **[−π,π]**, **[0, 1.6g]** | SimpleFlight 2412.11764 |

### 2.2 5-inch FPV racing quad — ICRA22 Table II (verified, sim identified from the real Agilicious-family platform) + Agilicious + Swift hardware

| Symbol | Meaning | Units | Value (±DR) | Source |
|---|---|---|---|---|
| m | mass | kg | **0.768** ±30% | ICRA22 Tab. II |
| Jx, Jy, Jz | inertia diagonal | kg·m² | **2.5e-3, 2.1e-3, 4.3e-3** ±30% | ICRA22 Tab. II |
| c_l | thrust coeff (per rotor, Ω in rad/s) | N/(rad/s)² | **1.563e-6** | ICRA22 Tab. II |
| c_d | drag-torque coeff | N·m/(rad/s)² | **1.909e-8** (κ = 0.01221 m) | ICRA22 Tab. II |
| k_vx,k_vy,k_vz | linear body drag | N·s/m | **0.3, 0.3, 0.15** (±100%) | ICRA22 Tab. II |
| g | gravity | m/s² | **[0,0,−9.81]** ±0.4 | ICRA22 Tab. II |
| τ_m | motor time constant | s | **0.0391**; CT-step latency 0.035–0.04015 | Agilicious §B/Fig.3C |
| T_max | max static thrust | N | **≈35** (Swift, 870 g ⇒ **TWR 4.1**); Agilicious continuous **4×9.5** | Nature 23 / Agilicious |
| motors/props | — | — | T-Motor Velox 2306 2400 kV (758 W), 5.1″ 3-blade | Nature 23 / Agilicious Tab. 2 |
| ‖ω‖ envelope | racing max / firmware cap | rad/s | **11.56** (662°/s) raced; ≈**34.9** (1998°/s) Betaflight cap | ICRA22 Tab. IV / BF #997 |
| c_max | mass-norm. thrust raced | m/s² | **33.04** | ICRA22 Tab. IV |
| Ω_hover | derived: √(mg/(4c_l)) | rad/s | 1097.76 (10,483 RPM) | derived |
| Δt, integrator | sim step | s | **1e-3**, symplectic Euler (ICRA22) / RK4 (Agilicious) | both |

---

## 3) Alternatives considered

- **Euler-angle attitude integration** (gym-pybullet-drones DYN mode does literally `rpy += Δt·rpy_rates` with body rates — verified in source): rejected. Gimbal-locks at FPV attitudes (loops, inverted flight); quaternion zeroth-order integrator is the same cost, singularity-free, norm-preserving by construction (Solà §4.6).
- **Full Betaflight-in-the-loop + battery grey-box** (Nature 2023 Eq. 5–6): highest CTBR fidelity (<1% motor-command error) but needs log-fitted PID gains and battery states; keep as Level B upgrade, not the game default.
- **BEM aerodynamics / NeuroBEM** (Bauersfeld et al., RSS 2021; used as Swift's eval sim): accurate at high speed but per-blade-element integrals + learned residuals resist cheap broadcasting and need data; the ICRA22 linear body-drag `−K_v v_B` is the sourced middle ground. Swift's k-NN residual force model (Nature Eq. 11, k=5) also rejected: data-dependent, gather-heavy.
- **RK4 vs symplectic Euler**: both citable (Agilicious vs ICRA22). Symplectic Euler at 1 kHz picked: 1 force eval/step, and it's what the RL-training sims (ICRA22, gym-pybullet-drones) use — matching your training-sim lineage beats marginal accuracy.
- **Motor pure delay + lag** (arXiv:2404.07837 identifies delays on top of first-order lag): adds a ring buffer (still vectorizable) — omit unless sim-to-real is on the roadmap.
- **Rotor drag / blade flapping** (Mahony-Kumar-Corke RAM 2012 tutorial §rotor aerodynamics): subsumed here by the identified linear drag term; per-rotor H-force not worth it at game fidelity.

---

## 4) Unit-test package (pytest oracles; float64, tolerances noted)

**T1 — Hover equilibrium (T=mg).**
CF2X (g=9.8): set all four `rpm = 14468.43` (`= √(0.027·9.8/(4·3.16e-10))`) ⇒ total thrust `4·k_f·rpm² = 0.264600 N = mg`; assert `a=0, ω̇=0`, state constant over 10⁴ steps (|Δp| < 1e-9 m). FPV: `Ω = 1097.755 rad/s` ⇒ `4·1.563e-6·Ω² = 7.53408 N = 0.768·9.81`. Also assert `HOVER_RPM·1.5 = MAX_RPM = 21702.64` (T2W=2.25 exactly ⇒ factor 1.5).

**T2 — Ballistic free fall (closed form, both discrete and continuous).**
Ω=0, v₀=0, p₀=(0,0,10). Continuous: `z(t)=10−½gt²`. Semi-implicit Euler closed form: `z_N = 10 − g·Δt²·N(N+1)/2`, `v_N = −g·N·Δt` (exact, derivable by summation).
- g=9.81, Δt=1e-3, N=1000: assert `v_z = −9.810000`, `z = 5.090095` (continuous 5.095000; gap = gΔt·t/2 = 4.905e-3 — assert both).
- gym-pybullet-drones convention g=9.8, Δt=1/240, N=240: assert `z = 10 − 9.8·241/480 = 5.0795833`, `v_z = −9.8`.
Invariant: horizontal momentum exactly conserved (`v_x,v_y ≡ 0`).

**T3 — Constant-rate rotation quaternion (closed form; discrete = exact for fixed axis, Solà Eq. 228–229).**
q₀=[1,0,0,0].
- ω=[0,0,π] rad/s, any Δt, t=1 s ⇒ q=[0,0,0,1]; t=0.5 s ⇒ q=[0.7071068,0,0,0.7071068]. Assert `‖q_N − q_exact‖ < 1e-6` after N=1000 steps of `q ⊗ q{ωΔt}`.
- Double-cover check: ω = (2π/√3)·(1,1,1) rad/s, t=1 s (total angle 2π) ⇒ q = [−1,0,0,0], NOT [+1,0,0,0].

**T4 — Quaternion norm preservation.** Random ω ~ U(−20,20)³ per step, 10⁵ steps, no renormalization: assert `|‖q‖−1| < 1e-12` growth per step in float64 (< 1e-5 total in float32) — holds because each step multiplies unit quaternions (Solà §4.6.2 remark). Also assert `R(q)ᵀR(q)=I` to 1e-9.

**T5 — Numeric trajectory vs gym-pybullet-drones explicit-dynamics equations (one-step oracles; m=0.027, k_f=3.16e-10, k_m=7.94e-12, L=0.0397, J=diag(1.4e-5,1.4e-5,2.17e-5), g=9.8, Δt=1/240, start at rest, level).**
(a) `rpm=(10⁴,10⁴,10⁴,10⁴)`: per-rotor F=0.0316 N, T=0.1264 N, `a_z = 0.1264/0.027 − 9.8 = −5.1185185 m/s²`; after 1 step: `v_z = −0.021327160`, `z = 10 − v_z·Δt... = 9.999911137 m` (position uses updated velocity!), τ=0, ω=0.
(b) yaw test `rpm=(14468.43, 0, 14468.43, 0)`: per-rotor F=0.066150 N ⇒ T=0.13230 N ⇒ `a_z = 4.9 − 9.8 = −4.9` exactly; `τ_x=τ_y=0` (opposite arms cancel through the X-mixer), `τ_z = −2·k_m·rpm² = −3.3242467e-3 N·m` ⇒ `ω̇_z = −153.1911 rad/s²`; after 1 step: `v_z=−0.0204167`, `ω_z=−0.6382963 rad/s`.
(c) attitude-rotated thrust: q = [cos45°, sin45°, 0, 0] (90° roll), hover rpm ⇒ `a = (0, −9.8, −9.8)` (thrust maps to −y_W: `R_x(π/2)e₃ = (0,−1,0)`). Oracle for the R(q) code path.

**T6 — Motor first-order lag (published constants).**
Step Ω_cmd: 0→1 (normalized), τ_m = 0.0375 s (=0.15/4, Molchanov) or 0.0391 s (Agilicious). Exact-ZOH update: assert value at t=τ_m is `1−e⁻¹ = 0.6321206`; at t=4τ_m is `1−e⁻⁴ = 0.9816844` (matches Molchanov's "2% settling" definition). Euler-form (Molchanov's exact filter, `4Δt/T` gain), Δt=5 ms, T=0.15: after 30 steps assert `1−(1−0.13333)³⁰ = 0.9863316`; assert Euler-form → ZOH-form as Δt→0 (|diff| < 4Δt/T·e⁻¹).

**T7 — Torque-free rigid-body invariants (Euler equations `Jω̇ = −ω×Jω`).**
(a) principal-axis spin: ω₀=(0,0,10) ⇒ `ω×Jω = 0` ⇒ ω constant to machine precision, forever.
(b) tumbling (intermediate axis, FPV J): ω₀=(0.01, 5, 0.01), no thrust/gravity/drag, Δt=1e-3, 10 s: assert world angular momentum `L_W = R(q)Jω` and kinetic energy `½ωᵀJω` drift < 1e-3 relative (symplectic Euler bounds drift; tighten to 1e-6 with Δt=1e-4 to catch sign errors in the cross term).

**T8 — CTBR clamps & rate response.** Command ω_cmd=(π,0,0) from rest with Level-A model, τ_ω=0.0391: assert ω_x(τ_ω)=0.6321·π, never overshoots, and clamp tests: CF ω_cmd=2π → saturates at π rad/s (SimpleFlight limit); FPV cap 34.87 rad/s (=1998°/s).

---

## 5) Sources (all URLs personally fetched & verified except where noted)

1. **E. Kaufmann, L. Bauersfeld, D. Scaramuzza, "A Benchmark Comparison of Learned Control Policies for Agile Quadrotor Flight," ICRA 2022** — dynamics Eq. (1)–(4), symplectic Euler @1 ms, Table II params (m=0.768, J, c_l=1.563e-6, c_d=1.909e-8, k_v), Table IV envelopes, CTBR robustness result. https://rpg.ifi.uzh.ch/docs/ICRA22_Kaufmann.pdf (arXiv:2202.10796). **[PDF read]**
2. **E. Kaufmann, L. Bauersfeld, A. Loquercio, M. Müller, V. Koltun, D. Scaramuzza, "Champion-level drone racing using deep reinforcement learning," Nature 620:982–987, 2023** — Methods Eq. (1)–(6): motor lag `Ω̇=(Ω_ss−Ω)/k_mot`, Betaflight PID model (<1% motor-cmd error, D-ref=0, I-reset, saturation priority), battery grey-box, k-NN residuals (Eq. 11), CTBR@100 Hz; hardware: 870 g, ≈35 N, TWR 4.1, Velox 2306 2400 kV, 5″ 3-blade. https://rpg.ifi.uzh.ch/docs/Nature23_Kaufmann.pdf, doi:10.1038/s41586-023-06419-4. **[PDF Methods read]**
3. **J. Solà, "Quaternion kinematics for the error-state Kalman filter," arXiv:1711.02508** — `q̇=½q⊗ω` Eq. (200); zeroth-order integrator Eq. (214)–(215) with exp map (Eq. 101); midward Eq. (219); first-order Eq. (227); fixed-axis exactness Eq. (228)–(229); unit-norm-by-construction remark §4.6.2. https://arxiv.org/pdf/1711.02508. **[PDF pp. 45–52 read]**
4. **gym-pybullet-drones (Panerati, Zheng, Zhou, Xu, Prorok, Schoellig, IROS 2021, arXiv:2103.02142) — source code, master branch**: `assets/cf2x.urdf` (all CF2X constants quoted in §2.1) and `envs/BaseAviary.py` (`_dynamics` mixing + semi-implicit Euler order, `G=9.8`, HOVER/MAX_RPM formulas, `_drag`, `_groundEffect`, `_downwash`). https://raw.githubusercontent.com/utiasDSL/gym-pybullet-drones/master/gym_pybullet_drones/assets/cf2x.urdf and .../envs/BaseAviary.py. **[both files read]**
5. **A. Molchanov, T. Chen, W. Hönig, J. A. Preiss, N. Ayanian, G. S. Sukhatme, "Sim-to-(Multi)-Real: Transfer of Low-Level Robust Control Policies to Multiple Quadrotors," IROS 2019** — motor lag as discrete first-order filter `u'_t = u'_{t−1} + (4Δt/T)(u_t − u'_{t−1})`, T = 2% settling, nominal **0.15 s**, DR 0.1–0.2 s. https://arxiv.org/abs/1903.04628. **[formula & values verified via fetched search of the PDF]**
6. **P. Foehn et al., "Agilicious: Open-source and open-hardware agile quadrotor for vision-based flight," Science Robotics 7(67):eabl6259, 2022** — motor τ = **39.1 ms**, collective-thrust step latency 35/40.15 ms (load-cell), 4×9.5 N continuous, 5.1″ 3-blade, sim @1 kHz, motors "modeled as a first-order system with a time constant … identified on a thrust test stand," RK4 @1 ms. https://rpg.ifi.uzh.ch/docs/ScienceRobotics22_Foehn.pdf (arXiv:2307.06100). **[PDF read]**
7. **J. Förster, "System Identification of the Crazyflie 2.0 Nano Quadrocopter," thesis, ETH Zürich, 2015, DOI 10.3929/ETHZ-B-000214143** — provenance of the CF2 k_f/k_m/inertia set used by gym-pybullet-drones (RPM-unit constants in §2.1 convert to the commonly cited 2.88e-8 / 7.24e-10 SI-rad values). https://www.research-collection.ethz.ch/handle/20.500.11850/214143. **[located; numbers cross-checked via source 4, PDF itself not retrievable in-session]**
8. **"What Matters in Learning a Zero-Shot Sim-to-Real RL Policy for Quadrotor Control?" (SimpleFlight), arXiv:2412.11764** — first-order motor model with identified T_m as one of 4 sys-ID params; CF2.1 CTBR limits ω∈[−π,π] rad/s, accel∈[0,1.6g]; 100 Hz control. https://arxiv.org/html/2412.11764v1. **[HTML read]**
9. **R. Mahony, V. Kumar, P. Corke, "Multirotor Aerial Vehicles: Modeling, Estimation, and Control of Quadrotor," IEEE Robotics & Automation Magazine 19(3):20–32, 2012** — canonical tutorial for the Newton–Euler + `k_f ω², k_m ω²` rotor model (background citation; equations used here are taken from sources 1–4).
10. Betaflight rate cap ≈1998 deg/s: betaflight-configurator issue #997 (https://github.com/betaflight/betaflight-configurator/issues/997); typical FPV rates 600–1000°/s: https://oscarliang.com/rates/ (secondary, hobbyist). **[search-verified]**
11. Alternatives referenced: L. Bauersfeld, E. Kaufmann, P. Foehn, S. Sun, D. Scaramuzza, "NeuroBEM: Hybrid Aerodynamic Quadrotor Model," RSS 2021 (arXiv:2106.08015); "Data-Driven System Identification of Quadrotors Subject to Motor Delays" (arXiv:2404.07837). **[not fetched; cited as pointers only]**

**Caveats / honesty notes**: (i) Level-A CTBR time-constant split (τ_ω vs τ_c) is an engineering choice bounded by sources 5–6, not a published constant — flagged in §1.4. (ii) gym-pybullet-drones DYN mode integrates Euler angles, not quaternions; T5 oracles therefore test the translational/body-rate/mixing math (identical equations), while attitude tests use the Solà integrator. (iii) Swift's Betaflight PID gains are fitted from logs and not published numerically.


====================================================================================================
# REPORT: aero-drag-groundeffect
====================================================================================================

All research is complete and verified. Here is the report.

---

# Quadrotor Aerodynamics for a Vectorized Drone-Swarm Simulator
## Drag, Wind Coupling, Ground Effect, Air Density, Rain — with citations and pytest oracles

**Notation** (batch of `B` agents, all quantities `[B,·]` tensors): `p,v ∈ R^{B,3}` world position/velocity, `R ∈ R^{B,3,3}` body→world rotation, `m` mass [kg], `ρ` air density [kg/m³], `v_w` wind velocity [m/s], `dt` fixed step [s]. All models below are pure broadcast/elementwise ops (one `einsum` for frame rotations); no per-agent loops.

---

## 1) Recommended model

### 1.1 Wind coupling — relative airspeed (the only coupling you need)
All aerodynamic forces are functions of **air-relative velocity**, never ground velocity:

```
v_air = v − v_w(p, t)                      # world frame       [B,3]
v_r   = Rᵀ v_air                           # body frame        [B,3]  (einsum('bij,bj->bi', R.transpose(1,2), v_air))
```
Source: the "wind triangle" `Ẋ = V_k = V_r + V_w`, Hattenberger, Bronz & Condomines, *Evaluation of drag coefficient for a quadrotor model*, IMAV 2022, Eq. (1)–(2) — https://www.imavs.org/papers/2022/4.pdf; identical formulation in Chen & Bai (IFAC 2022, below). Gusts: a citable cheap generator is the sinusoidal freestream `V(t)=V∞(1+A·sin(2π f_g t))` (Wan & Tsai, ICAS 2021, Eq. (5)); the aerospace standard is Dryden turbulence (MIL-HDBK-1797), see §3.

### 1.2 Body drag — quadratic, diagonal drag-area matrix
```
F_body = −½ ρ D_A ⊙ |v_r| ⊙ v_r           # body frame, per-axis; D_A = (D_x, D_y, D_z)  [m²]
F_world = R F_body
```
Source (exact form + identified numbers): Chen & Bai, *Incorporating thrust models for quadcopter wind estimation*, IFAC-PapersOnLine 55-37 (2022) 19–24, Eq. (2): `f_d = −½ρD|v_r|v_r`, `D = diag(D_x, D_y, 0)`, with **D_x = D_y = 3.265×10⁻²** for a **0.389 kg** quadcopter, ρ = 1.225 (their Table 1) — https://par.nsf.gov/servlets/purl/10382981. (They zero D_z because vertical aero is folded into their thrust model; for a game, use D_z ≈ D_x with a blunt-body area.)
Whole-airframe free-fall values (CFD, DJI-Phantom-shaped 1.4 kg body, disk-area reference): **C_d = 0.69** props stopped, 0.36 @4319 RPM, 0.31 @6528 RPM; FAA task-force free-fall assumption for small quads: **C_d = 0.3, A = 0.02 m²** — Wan & Tsai, *Numerical study of quad-rotor aircraft performance under adverse situations*, ICAS 2021 paper 0482, §2.5, Table 5–6 — https://www.icas.org/icas_archive/ICAS2020/data/papers/ICAS2020_0482_paper.pdf.
**Validity caveat (published):** below ~8–10 m/s airspeed, measured total drag of small quads is *linear*, not quadratic, because rotor drag dominates (Hattenberger 2022 §3.2, citing Meier et al., *Wind Estimation with Multirotor UAVs*, Atmosphere 13(4):551, 2022 — https://www.mdpi.com/2073-4433/13/4/551). Hence pair quadratic body drag with the linear rotor-drag term of §1.3; the sum reproduces the measured linear-then-quadratic behavior.

### 1.3 Rotor drag — linear D-matrix model (Faessler–Franchi–Scaramuzza)
Continuous model (their Eq. (2), extended to wind by `v → v_air` per §1.1):
```
v̇ = −g z_W + c z_B − R D Rᵀ v_air ,   D = diag(d_x, d_y, d_z)   [1/s, mass-normalized]
c  = c_cmd + k_h (v_airᵀ(x_B + y_B))²                            [m/s², thrust correction]
```
Identified values (610 g FPV racer, 6-inch props, thrust-to-weight 4): **d_x = 0.544 s⁻¹, d_y = 0.386 s⁻¹** (circle trajectory @4 m/s); d_x = 0.491, d_y = 0.236 (lemniscate); d_x = 0.425, d_y = 0.256 (circle @2.8 m/s); **d_z ≈ 0** (no tracking benefit even at 2.5 m/s vertical); **k_h = 0.009 m⁻¹**. d_x > d_y because the frame is wider than long.
Source: M. Faessler, A. Franchi, D. Scaramuzza, *Differential Flatness of Quadrotor Dynamics Subject to Rotor Drag for Accurate Tracking of High-Speed Trajectories*, IEEE RA-L 3(2):620–626, 2018, Eq. (2), (5), §VII-C — https://rpg.ifi.uzh.ch/docs/RAL18_Faessler.pdf (also arXiv:1712.02402).
**Discrete update (exact for the drag term).** `−RDRᵀ` is LTI in the body frame over one step, so the zero-order-hold/exact discretization (Franklin, Powell & Workman, *Digital Control of Dynamic Systems*, 3rd ed., ZOH discretization `x_{k+1}=e^{A dt}x_k`) is a diagonal matrix exponential — pure broadcast:
```
E = diag(exp(−d_x dt), exp(−d_y dt), exp(−d_z dt))     # precomputed scalar constants
v⁺_air = R E Rᵀ v_air                                   # drag decay, exact
v_{k+1} = v⁺_air + v_w + dt·(−g z_W + c z_B + F_body/m + …)   # remaining forces, (semi-implicit) Euler
p_{k+1} = p_k + dt · v_{k+1}
```
The plain forward-Euler alternative `v_{k+1}=v_k+dt·a_k` at fixed 240 Hz is what gym-pybullet-drones/PyBullet uses (Panerati et al., *Learning to Fly*, IROS 2021, arXiv:2103.02142). gym-pybullet-drones' own drag variant (from Förster 2015 sys-ID) is linear in velocity and proportional to total prop rate: `drag = R·(−k_d·Σᵢ ωᵢ)·v`, `k_d,xy = 9.1785×10⁻⁷, k_d,z = 10.311×10⁻⁷` N/(rad/s·m/s) (Crazyflie 2) — `_drag()` in https://github.com/utiasDSL/gym-pybullet-drones/blob/master/gym_pybullet_drones/envs/BaseAviary.py and https://raw.githubusercontent.com/utiasDSL/gym-pybullet-drones/master/gym_pybullet_drones/assets/cf2x.urdf.

### 1.4 Ground effect — Cheeseman–Bennett + multirotor variants
Classic single-rotor hover ratio (I.C. Cheeseman, W.E. Bennett, *The Effect of the Ground on a Helicopter Rotor in Forward Flight*, ARC R&M 3021, 1955), with the forward-flight extension, as reproduced in Kan et al. Eq. (4):
```
T_IGE/T_OGE = 1 / (1 − (R/4z)² / (1 + (V/v_i)²))        # V=0 at hover → 1/(1−(R/4z)²)
```
Singular at z = R/4 → **always clamp z**. Published multirotor facts: ground effect measurably extends to **z ≈ 5R** for quadrotors (higher than C&B predicts), and C&B *underestimates* the effect for quads (Kan et al. §IV).
**gym-pybullet-drones implementation** (per-rotor additive thrust, `_groundEffect()` in BaseAviary.py, constants from cf2x.urdf; provenance: Förster 2015 Eq. 4.2 and Shi et al. 2019 *Neural Lander* baseline):
```
ΔT_i = ω_rpm,i² · KF · G_c · (R_prop / (4 z_i))²ᅟᅟz_i = max(z_i, z_clip)
z_clip = 0.25·R_prop·sqrt(15·MAX_RPM²·KF·G_c / MAX_THRUST)
CF2:  KF = 3.16e-10 N/RPM²,  R_prop = 2.31348e-2 m,  G_c = 11.36859,  → z_clip = 0.0377637 m
```
**Recommended for the game** (explicit, no singularity in range, validated on two platforms — AscTec Hummingbird R=0.1 m/0.551 kg and Crazyflie R=0.023 m/0.032 kg — Kan et al. Model 1, Eq. (11)):
```
T_IGE/T_h = (1 − 3R/(25z)) / (1 + (3/50)(V/v_h)³),      v_h = sqrt(mg/(8 ρ π R²))   (per-rotor hover induced velocity, their Eq. (3) with T_h,r=mg/4)
valid z/R ∈ [0.5, 5], V/v_h ∈ [0, 1.2]; hover: T_IGE = T_h(1 − 3R/(25z)); z>5R ⇒ effect < 2.4 %
```
Source: X. Kan, J. Thomas, H. Teng, H.G. Tanner, V. Kumar, K. Karydis, *Analysis of Ground Effect for Small-scale UAVs in Forward Flight*, IEEE RA-L 4(4), 2019 — https://par.nsf.gov/servlets/purl/10181219.
Quadrotor 4-rotor extension with body-lift (Sanchez-Cuevas, Heredia & Ollero, *Characterization of the Aerodynamic Ground Effect and Its Influence in Multirotor Control*, Int. J. Aerospace Eng. 2017:1823056, DOI 10.1155/2017/1823056), as reproduced in Kan et al. Eq. (7):
```
T_IGE/T_OGE = [ 1 − (R/4z)² − R²·z/√((d²+4z²)³) − (R²/2)·z/√((2d²+4z²)³) − 2R²·z/√((b²+4z²)³)·K_b ]⁻¹
d = rotor-axis separation, b = diagonal separation, K_b = 2 (empirical body-lift coefficient)
```
Vectorization: per-rotor heights `z_i = (p + R r_i)_z` are a batched matmul; everything else elementwise.

### 1.5 Air density — ISA troposphere
ISA (ISO 2533:1975; identical to U.S. Standard Atmosphere 1976 below 32 km), troposphere h < 11 000 m:
```
T(h) = T₀ − L·h
ρ(h) = ρ₀ (1 − L·h/T₀)^(g₀/(R·L) − 1) = 1.225 · (1 − 2.2558×10⁻⁵ h)^4.25588      [kg/m³]
p(h) = p₀ (1 − L·h/T₀)^(g₀/(R·L))     ,  g₀/(R·L) = 9.80665/(287.05287·0.0065) = 5.25588
```
Verified statements of this law: ERAU *Introduction to Aerospace Flight Vehicles*, ISA chapter — https://eaglepubs.erau.edu/introductiontoaerospaceflightvehicles/chapter/international-standard-atmosphere-isa/ (gives `1.225(1−2.2558e-5 h)^4.2586` with R=287); NASA Glenn metric model — https://www.grc.nasa.gov/www/k-12/airplane/atmosmet.html (`p=101.29[(T+273.1)/288.08]^5.256`, `ρ=p/(0.2869(T+273.1))`).
**Below 500 m** the first-order Taylor of the cited law is `ρ ≈ ρ₀(1 − 9.600×10⁻⁵·h)` (slope `−ρ₀(g₀/(RL)−1)L/T₀ = −1.1760×10⁻⁴ kg/m³ per m`); error vs. exact at 500 m is 0.09 %. Constant ρ = 1.225 errs by +4.9 % at 500 m — acceptable for a game if all agents fly a shallow band; otherwise the power law is one `pow` per agent.

### 1.6 Rain — what is actually published (thin literature; honest simplification)
Published, quantitative results for small rotors:
- **Wan & Tsai, ICAS 2021** (two-phase DPM CFD, validated against Brandt & Selig propeller data, APC 10×4.7): at **LWC = 19 g/m³** (≈ 550 mm/h — extreme-thunderstorm level, via LWC = 0.062·R_rain^0.913, Willis & Tattelman 1989): quad thrust coefficient **−2.6 % @ 4319 RPM** (8.217e-3 → 8.000e-3) and **−1.6 % @ 6528 RPM** (8.308e-3 → 8.169e-3). Higher RPM ⇒ less degradation. Raindrop terminal velocity used: `V_T = 9.58(1−exp[−(D_m/1.77)^1.147])` m/s, D_m in mm (Markowitz, J. Appl. Meteorology 15, 1976).
- **Aerospace (MDPI) 12(11):975, 2025** (propeller–wing CFD under heavy rain): raindrop downwash reduces local blade angle of attack → **max thrust loss 2.35 %** — https://doi.org/10.3390/aerospace12110975.
- **AIAA 2024-4342** (experimental, high-speed photography + PIV, hydrophilic vs. superhydrophobic blades): thrust decreases and motor power increases under simulated rain; wake velocity reduced — https://arc.aiaa.org/doi/10.2514/6.2024-4342 (quantities paywalled; direction confirmed).
- Classical fixed-wing anchor: Rhode, NACA TN 903 (1941): momentum imparted by intercepted rain at LWC 50 g/m³ → 18 % airspeed loss on a DC-3 (as summarized in Wan & Tsai §2.4).
**No peer-reviewed source found giving airframe added-mass (water-film) values for multirotors** — do not model it. **Recommended honest simplification** (bounded by the published points): a thrust multiplier, elementwise
```
T ← T · (1 − k_rain·LWC/19),  k_rain = 0.026 (low-RPM published bound; use 0.016 at high RPM)
LWC[g/m³] = 0.062 · RainRate[mm/h]^0.913          # Willis–Tattelman, cited in Wan & Tsai Eq. (12)
```
⇒ realistic "heavy rain" 25 mm/h → LWC ≈ 1.17 → thrust loss ≈ 0.16 % (i.e., rain barely affects thrust; its dominant gameplay effects are the *wind/gusts that accompany it* — Wan & Tsai's own conclusion is that downdraft/gust dominates rain: 0°-horizontal 10 m/s gust changes C_T by +6.6 %, −90° downdraft makes C_T negative).

---

## 2) Parameters table

| Symbol | Meaning | Units | Value(s) | Source |
|---|---|---|---|---|
| CdA (=D_x,D_y) | body drag-area, 0.389 kg quad | m² | 3.265×10⁻² | Chen & Bai 2022, Table 1 |
| C_d (freefall) | blunt-body Cd, props off / 4319 / 6528 RPM | – | 0.69 / 0.36 / 0.31 | Wan & Tsai ICAS 2021, Table 5 |
| A (freefall) | projected area, 250 g-class quad | m² | 0.02 | FAA RTF report via Wan & Tsai §2.5 |
| k (linear drag) | total linear drag, 0.547→1.067 kg quad | N/(m/s) | 0.153–0.230; k = 0.105+0.087·m | Hattenberger 2022, Fig. 6, Tbl 3 |
| d_x, d_y, d_z | mass-normalized rotor-drag coeffs (610 g racer) | s⁻¹ | 0.544, 0.386, ≈0 | Faessler RA-L 2018 §VII-C |
| k_h | thrust vel² correction | m⁻¹ | 0.009 | Faessler RA-L 2018 §VII-C |
| k_d,xy / k_d,z | linear drag per Σω (Crazyflie 2) | N/(rad/s·m/s) | 9.1785e-7 / 10.311e-7 | cf2x.urdf, gym-pybullet-drones |
| G_c | ground-effect gain (Crazyflie 2) | – | 11.36859 | cf2x.urdf |
| KF, KM | thrust/torque per RPM² (CF2) | N/RPM², N·m/RPM² | 3.16e-10, 7.94e-12 | cf2x.urdf |
| R_prop, m, T/W | CF2 prop radius, mass, thrust-to-weight | m, kg, – | 0.0231348, 0.027, 2.25 | cf2x.urdf |
| K_b | body-lift coeff, quad IGE | – | 2 | Sanchez-Cuevas 2017 via Kan Eq. (7) |
| R, m (Hummingbird) | prop radius, mass; k_f = 5.95e-8 N/RPM² | m, kg | 0.1, 0.551 | Kan RA-L 2019 §III-A |
| T₀, p₀, ρ₀ | ISA sea level | K, Pa, kg/m³ | 288.15, 101325, 1.225 | ISO 2533:1975 / ERAU ISA |
| L, R_gas, g₀ | lapse rate, gas const., std gravity | K/m, J/(kg·K), m/s² | 0.0065, 287.05287, 9.80665 | ISO 2533:1975 |
| LWC heavy rain | extreme thunderstorm CFD case | g/m³ | 19 (≈550 mm/h) | Wan & Tsai Table 7 |
| ΔC_T rain | thrust coeff. loss @ LWC 19 | % | −2.6 (4319 RPM), −1.6 (6528 RPM) | Wan & Tsai Table 8 |
| DW₁,DW₂,DW₃ | downwash coeffs (CF2, drone-over-drone) | – | 2267.18, 0.16, −0.11 | cf2x.urdf |

## 3) Alternatives considered — and why not
- **BEMT / gray-box thrust models** (Svacha ICUAS 2017; Sun, de Visser & Chu, J. Aircraft 56(2) 2019; Bauersfeld et al. *NeuroBEM* 2021): more accurate, but require per-rotor Ω, induced-velocity iteration (Sun's `v_in` is defined *implicitly*, Chen & Bai Eq. (10) — needs a fixed-point loop, the one item here that resists single-pass vectorization). Overkill for a game.
- **Cheeseman–Bennett forward-flight term with momentum-theory v_i**: v_i solves an implicit quartic (Kan Eq. (2)) — again iterative. Use Kan Model 1 (explicit) or hover `v_i = v_h`.
- **Hayden 1976** `(0.9926+0.03794/(z/2R)²)^(2/3)`: hover-only, full-scale helicopters; no velocity dependence (Kan Eq. (5)).
- **Li et al. 2015** `T_in/T_out = 1−ρ_c(R/4z)²`, ρ_c = 8.6: refit on quadrotor data gives ρ_c = 3.4 — platform-inconsistent (Kan §IV-A).
- **He & Leang quasi-steady IGE (AIAA J. 2020)**: promising, but source PDF unverifiable in this session (TLS failure) — excluded per no-invented-physics rule.
- **Dryden turbulence (MIL-HDBK-1797)**: the standard gust spectrum; discrete forming-filter is cheap but adds state per agent; the ICAS sinusoidal gust (Eq. 5/11) is a citable cheaper stand-in.
- **Rain added-mass on airframe**: no published multirotor numbers found — omitted (stated explicitly in §1.6).

## 4) Unit-test package (pytest oracles)
All target values computed from the cited closed forms; tolerances `rtol=1e-6` unless noted.

**T1 — zero-wind, at-rest ⇒ zero drag.** `v=0, v_w=0` ⇒ `F_body=0` and `F_rotor=0` exactly (both are odd in `v_air`). Also Galilean/drift test: `v = v_w = (7,−3,1)` ⇒ `v_air=0` ⇒ both forces exactly 0.

**T2 — terminal velocity (quadratic drag).** Closed form `v_t = sqrt(2mg/(ρ C_d A))` from `D=W` (NASA Glenn — https://www1.grc.nasa.gov/beginners-guide-to-aeronautics/termvel/). Inputs m=0.25 kg, C_d=0.3, A=0.02 m², ρ=1.225, g=9.80665 ⇒ **v_t = 25.828648 m/s** (published cross-check: 25.6863 m/s in Wan & Tsai Table 6, same FAA inputs, within 0.6 %). Time solution from rest `v(t)=v_t·tanh(g t/v_t)` (HyperPhysics — http://hyperphysics.gsu.edu/hbase/Mechanics/quadvfall.html): with v_t=25, at t=1 s ⇒ **v = 9.332802 m/s**; at t=5·(v_t/g) ⇒ v = 0.99991·v_t. Simulate 1-D fall at dt=1e-3 and assert |v_sim−v(t)| < 0.1 % v_t.

**T3 — ground-effect ratios.** C&B hover `1/(1−(1/(4·z/R))²)`: z/R=0.5 ⇒ **4/3 = 1.333333**; z/R=1 ⇒ **16/15 = 1.066667**; z/R=2 ⇒ **1.015873**; z/R=4 ⇒ **1.003922**. Forward flight z/R=1, V/v_i=1 ⇒ **32/31 = 1.032258**. Kan Model 1 hover `1−3R/(25z)`: z=R ⇒ **0.8800**, z=2R ⇒ **0.9400**, z=5R ⇒ **0.9760**. gym-pybullet-drones CF2X (g=9.8 as in their code): HOVER_RPM = **14468.429**, MAX_RPM = **21702.644**, MAX_THRUST = **0.59535 N**, z_clip = **0.0377637 m**; at z=0.05 m, hover RPM: per-rotor ΔT = **1.006255×10⁻² N** = **15.21 %** of per-rotor hover thrust (0.066150 N). Invariants: ratio → 1 monotonically as z→∞ (C&B at 5R = 1.002506, assert < 0.3 %); clamp ⇒ finite for all z ≥ 0.

**T4 — ISA density.** From §1.5 with ISO constants: **ρ(0)=1.225000, ρ(100)=1.213276, ρ(500)=1.167268, ρ(1000)=1.111641 kg/m³**; T(500)=284.900 K, p(500)=95460.8 Pa (cross-check: standard tables list 1.1117 kg/m³ at 1000 m). Linear-approx assertion: |ρ_lin(500)−ρ(500)| ≤ 0.001 kg/m³. Invariants: ρ strictly decreasing, ρ>0 for h<11 km.

**T5 — rotor drag exact decay.** Pure drag, hover attitude (R=I), v_air=(1,0,0), d_x=0.544: acceleration = **−0.544 m/s²** (force −0.33184 N at m=0.610 kg). One exact-discretization step dt=0.01: factor **exp(−0.00544)=0.99457477**; assert `v_{k+1}=0.99457477·v_k` and that forward-Euler (0.99456) matches to O(dt²). Frame invariance: for any rotation R, `‖R D Rᵀ v‖` with v along body-x equals d_x‖v‖. Dissipativity invariant: `P = −v_airᵀ(R D Rᵀ)v_air ≤ 0` for all batch entries (energy never injected by drag; equality iff v_air=0 when D≻0).

**T6 — quadratic body drag value.** Chen & Bai params: ρ=1.225, CdA=3.265e-2, |v_air|=5 m/s ⇒ F = ½·1.225·0.03265·25 = **0.499953 N**; a = F/0.389 = **1.285227 m/s²**. Direction: F·v_air < 0 componentwise-signed (opposes motion).

**T7 — linear-regime cross-check (Hattenberger).** Hover in 5 m/s wind, k=0.153 N/(m/s), m=0.547 kg: equilibrium bank `tan φ = k·V/(mg)` = 0.142611 ⇒ **φ = 8.116°** (consistent with their Fig. 4 trend, ~7–8° at 5 m/s). Simulate attitude-held hover and assert steady-state tilt within 5 %.

**T8 — rain multiplier.** LWC=19 ⇒ multiplier **0.974** (low RPM) / 0.984 (high RPM); RainRate=25 mm/h ⇒ LWC = 0.062·25^0.913 = **1.1682 g/m³** ⇒ multiplier **0.99840**; RainRate=0 ⇒ exactly 1. Invariant: multiplier ∈ (0.97, 1] over any sane rain rate (≤ 550 mm/h), monotone in LWC.

**T9 — batch/vectorization sanity.** Running B=1 vs. B=4096 with one identical agent gives bitwise-close (atol 1e-6) forces; permuting the batch permutes outputs (no cross-agent leakage except the explicit O(N²) downwash term, tested separately with 2 agents: gym-pybullet-drones `_downwash`: `ΔF_z = −DW₁(R_prop/4Δz)²·exp(−½(Δxy/(DW₂Δz+DW₃))²)` for Δz>0).

## 5) Sources
1. Faessler, Franchi, Scaramuzza, *Differential Flatness of Quadrotor Dynamics Subject to Rotor Drag…*, IEEE RA-L 3(2), 2018 — https://rpg.ifi.uzh.ch/docs/RAL18_Faessler.pdf (verified: PDF read; Eqs. 1–5, §VII-C values)
2. Chen & Bai, *Incorporating thrust models for quadcopter wind estimation*, IFAC-PapersOnLine 55-37, 2022 — https://par.nsf.gov/servlets/purl/10382981 (verified: PDF read; Eq. 2, Table 1)
3. Hattenberger, Bronz, Condomines, *Evaluation of drag coefficient for a quadrotor model*, IMAV 2022 — https://www.imavs.org/papers/2022/4.pdf (verified: PDF read; Eqs. 1–4, Fig. 6, Table 1/3)
4. Kan, Thomas, Teng, Tanner, Kumar, Karydis, *Analysis of Ground Effect for Small-scale UAVs in Forward Flight*, IEEE RA-L 4(4), 2019 — https://par.nsf.gov/servlets/purl/10181219 (verified: PDF read; Eqs. 3–7, 11–13)
5. Cheeseman & Bennett, *The Effect of the Ground on a Helicopter Rotor in Forward Flight*, ARC R&M 3021, 1955 (as cited/reproduced in [4] Eq. 4)
6. Sanchez-Cuevas, Heredia, Ollero, *Characterization of the Aerodynamic Ground Effect and Its Influence in Multirotor Control*, Int. J. Aerospace Eng. 2017, DOI 10.1155/2017/1823056 (equation and K_b=2 as reproduced in [4] Eq. 7; original paywalled at Wiley)
7. gym-pybullet-drones source: BaseAviary.py — https://github.com/utiasDSL/gym-pybullet-drones/blob/master/gym_pybullet_drones/envs/BaseAviary.py and cf2x.urdf — https://raw.githubusercontent.com/utiasDSL/gym-pybullet-drones/master/gym_pybullet_drones/assets/cf2x.urdf (verified: code lines quoted); paper: Panerati et al., IROS 2021, arXiv:2103.02142
8. Wan & Tsai, *Numerical Study of Quad-rotor Aircraft Performance under Adverse Situations*, ICAS 32nd Congress, 2021 — https://www.icas.org/icas_archive/ICAS2020/data/papers/ICAS2020_0482_paper.pdf (verified: PDF read; Tables 5–8, Eqs. 5, 12, 18)
9. ISO 2533:1975 *Standard Atmosphere*; law verified via ERAU *Intro to Aerospace Flight Vehicles* ISA chapter — https://eaglepubs.erau.edu/introductiontoaerospaceflightvehicles/chapter/international-standard-atmosphere-isa/ and NASA Glenn — https://www.grc.nasa.gov/www/k-12/airplane/atmosmet.html (both verified)
10. NASA Glenn, *Terminal Velocity* — https://www1.grc.nasa.gov/beginners-guide-to-aeronautics/termvel/ (verified: v=√(2W/(C_d ρ A)))
11. HyperPhysics, *Freefall with quadratic drag* — http://hyperphysics.gsu.edu/hbase/Mechanics/quadvfall.html (verified: v = v_t·tanh(gt/v_t), τ = v_t/g)
12. Meier, Hann, Skaloud, Garreau, *Wind Estimation with Multirotor UAVs*, Atmosphere 13(4):551, 2022 — https://www.mdpi.com/2073-4433/13/4/551 (linear→quadratic drag transition at ~8–10 m/s, via [3] §3.2)
13. *Investigation on Aerodynamic Characteristics of Propeller–Wing… Under Heavy Rainfall*, Aerospace 12(11):975, 2025 — https://doi.org/10.3390/aerospace12110975 (2.35 % max thrust loss)
14. AIAA 2024-4342, *An Experimental Study on Aerodynamic Performance Degradation of a Drone Propeller Due to Rainfall* — https://arc.aiaa.org/doi/10.2514/6.2024-4342 (direction only; paywalled)
15. Franklin, Powell, Workman, *Digital Control of Dynamic Systems*, 3rd ed. (ZOH exact discretization `x_{k+1}=e^{A dt}x_k`)
16. Rhode, NACA TN 903, 1941; Willis & Tattelman, J. Appl. Meteo. 28, 1989; Markowitz, J. Appl. Meteo. 15, 1976 (rain microphysics, as cited in [8])
17. Hayden 1976; Li et al. CCC 2015; Svacha ICUAS 2017; Sun et al. J. Aircraft 2019; Bauersfeld et al. 2021 (alternatives, via [1],[2],[4])

**Vectorization status:** every recommended equation is elementwise or a batched 3×3 einsum; the only published components that resist loop-free single-pass evaluation are implicit induced-velocity models (momentum-theory v_i, Sun's v_in) — excluded from the recommendation for exactly that reason.


====================================================================================================
# REPORT: ground-units-terrain
====================================================================================================

All sources verified from primary documents. Composing the final report.

# Ground-Unit Motion Models for a Vectorized Drone-Swarm Game Sim (toy tank + toy soldier)

All equations below were verified against the cited primary documents (PDFs fetched and read during this task). Notation: batch tensors over `N` agents; `⊙` elementwise; all updates are broadcast ops, no loops.

---

## 1) Recommended models

### 1.1 Toy tank — unicycle / differential-drive kinematics with exact-arc discrete update

**Continuous model** (LaValle, *Planning Algorithms*, Cambridge Univ. Press 2006, §13.1.2, Eq. (13.16)–(13.17), verified at https://lavalle.pl/planning/node659.html):

```
ẋ = (r/2)(u_l + u_r) cos θ        # Eq. 13.16, wheel/track angular speeds u_l, u_r, wheel radius r
ẏ = (r/2)(u_l + u_r) sin θ
θ̇ = (r/L)(u_r − u_l)              # L = tread (track-center spacing), here called B
```
Equivalently with `v = (v_r+v_l)/2`, `ω = (v_r−v_l)/B` (same relation appears as Eq. (1) of arXiv:2007.08690 for a real tracked vehicle: `v=(v1+v2)/2, ω=(v1−v2)/B`): `ẋ = v cosθ, ẏ = v sinθ, θ̇ = ω`.

**Discrete update — exact circular arc** (Thrun, Burgard, Fox, *Probabilistic Robotics*, MIT Press 2005, Eq. (5.5)–(5.9) and Table 5.3; verified at https://ccc.inaoep.mx/~mdprl/documentos/CH5.pdf). With constant `(v, ω)` over `Δt`, the robot moves on a circle of radius `r = |v/ω|` (Eq. 5.5) centered at `x_c = x − (v/ω) sinθ, y_c = y + (v/ω) cosθ` (Eq. 5.7–5.8):

```
x' = x − (v/ω) sinθ + (v/ω) sin(θ + ωΔt)      # Eq. (5.9) / Table 5.3 lines 5–7
y' = y + (v/ω) cosθ − (v/ω) cos(θ + ωΔt)
θ' = θ + ωΔt
```
Vectorized `ω→0` guard: `torch.where(|ω|<ε, straight-line update x+vcosθΔt, arc update)`, or the sinc form `x' = x + vΔt·sinc-based blend`; Thrun notes `r` may be infinite for `ω=0` (straight line).

**Actuation limits (policy output shaping, all elementwise clamps):**
1. Track-speed envelope (from Eq. 13.16 algebra, each track `|v_i| ≤ v_track,max`): `|v| + (B/2)|ω| ≤ v_track,max`. Pivot turn: `v=0 ⇒ ω_max = 2 v_track,max / B`.
2. Longitudinal acceleration clamp: `v_{t+1} = clamp(v_t + a_cmd Δt, v_t − a_max Δt, v_t + a_max Δt)`; real anchor: M1 accelerates 0→20 mph in 7 s ⇒ `a_avg = 8.9408/7 = 1.277 m/s²` (FAS M1 fact file, verified).
3. Speed-dependent turn limit (lateral friction). Steady turning lateral acceleration is `a_y = v²/R = |v·ω|` (standard steady-state cornering relation, Gillespie, *Fundamentals of Vehicle Dynamics*, SAE 1992, ch. 6). Track slip limits it to `|v·ω| ≤ λ_t g`, with the lateral (turning) resistance coefficient of a skid-steered track given by the empirical relation (verified in arXiv:2007.08690, Eq. (3), attributed there to Zou et al., *Appl. Energy* 171:372–382, 2016; same relation used across tracked-vehicle literature, cf. Wong & Chiang 2001):

```
λ_t = λ_max · (0.925 + 0.15·R/B)^(−1),   R = |v/ω|         # Eq. (3), arXiv:2007.08690
M_turn = 0.25 · λ_t · m · g · l                              # turning-resistance moment; l = track contact length
```
Implementation: clamp `|ω| ≤ λ_t g / max(|v|, ε)` (elementwise; `R/B` computed from previous-step `v,ω`).

**Slope effect (vehicle):** motion-resistance balance (standard tractive-effort equation, Wong, *Theory of Ground Vehicles*, Wiley, ch. 1: tractive effort = rolling + grade resistance): on slope angle `α` (from heightfield gradient, §1.3),

```
v_cap(α) = min( v_gov , P_w / (m g (sinα + f_r cosα)) ),  sinα = s/√(1+s²), s = ∇h·heading
```
Fitting the two published M1 data points (20 mph @10% grade, 4.5 mph @60% grade, m = 60 short tons = 54,431 kg; FAS fact file) gives `P_w = 571 kW`, `f_r = 0.0203` — and predicts flat-ground power-limited speed 52.8 m/s ≫ governed 20.1 m/s, i.e. flat speed is governor-limited, consistent with the "(Governed)" annotation in the spec. Downhill: clamp `v_cap = v_gov` (do not speed up; game choice). Toy scaling: Froude dynamic similarity `v_toy = v_real·√(L_toy/L_real)` (R. McNeill Alexander, *Nature* 261:129–130, 1976).

### 1.2 Toy soldier — Helbing social force model (escape-panic form)

**Model** (Helbing, Farkas, Vicsek, "Simulating dynamical features of escape panic," *Nature* 407:487–490, 2000; equations verified from the preprint arXiv:cond-mat/0009448, Eq. (1)–(3)):

```
m_i dv_i/dt = m_i (v_i⁰ e_i⁰ − v_i)/τ_i  +  Σ_{j≠i} f_ij  +  Σ_W f_iW                      (1)

f_ij = { A_i exp[(r_ij − d_ij)/B_i] + k·g(r_ij − d_ij) } n_ij
       + κ·g(r_ij − d_ij) Δv_ji^t t_ij                                                     (2)

f_iW = { A_i exp[(r_i − d_iW)/B_i] + k·g(r_i − d_iW) } n_iW
       − κ·g(r_i − d_iW)(v_i·t_iW) t_iW                                                    (3)
```
with `d_ij = ‖r_i − r_j‖`, `r_ij = r_i + r_j` (sum of radii), `n_ij = (r_i − r_j)/d_ij`, `t_ij = (−n_ij^y, n_ij^x)`, `Δv_ji^t = (v_j − v_i)·t_ij`, and `g(x) = x if x>0 else 0` (= `relu(x)`; contact-only body force and sliding friction). `e_i⁰` is the desired direction — in your sim, the learned-policy output. Walls: use your existing SDF shape-primitive base; `d_iW` = SDF value, `n_iW` = SDF gradient.

**Speed cap** (Helbing & Molnár, "Social force model for pedestrian dynamics," *Phys. Rev. E* 51:4282–4286, 1995; verified from arXiv:cond-mat/9805244, Eq. (11)–(12)): realized velocity `v = w·g(v_max/‖w‖)`, `g=1 if ‖w‖≤v_max else v_max/‖w‖`, with `v_max = 1.3 v⁰`.

**Discrete update.** Published SFM discretizations: velocity Verlet with `Δt = 10⁻⁴ s` ("The Eq. (1) was numerically integrated by means of the velocity Verlet algorithm, with a timestep of 10−4 seconds" — Sticco et al., *Safety Science* 121:42–53 2020, verified from arXiv:2003.02890; Verlet scheme: Swope, Andersen, Berens & Wilson, *J. Chem. Phys.* 76:637, 1982). For game `Δt` (0.01–0.05 s) use the symplectic (semi-implicit) Euler method (Hairer, Lubich, Wanner, *Geometric Numerical Integration*, 2nd ed., Springer 2006, §I.1.2):

```
a_t     = F(x_t, v_t)/m                       # Eq. (1)–(3), pure broadcast
v_{t+1} = cap( v_t + a_t Δt )                 # cap per 1995 Eq. (11)–(12)
x_{t+1} = x_t + v_{t+1} Δt
```
At game `Δt`, clamp per-agent force magnitude (e.g. `‖F‖ ≤ m·v_max/Δt`) to keep the stiff contact terms (`k, κ` are large) stable; this is a stability guard, not part of the published model.

**Slope effect (pedestrian) — Tobler's hiking function** (Tobler, W., "Three presentations on geographical analysis and modeling," NCGIA Technical Report 93-1, Feb 1993; formula verified at https://en.wikipedia.org/wiki/Tobler%27s_hiking_function):

```
W(S) = 6 · exp(−3.5 · |S + 0.05|)   [km/h],  S = dh/dx = tanθ (slope along heading)
```
Flat: 5.037 km/h ≈ 1.4 m/s; max 6 km/h at S = −0.05. Apply as desired-speed modulation: `v_i⁰(S) = v_i⁰ · W(S)/W(0)` (keeps Helbing's `v⁰` calibration on flat ground; the ratio is the sourced shape).

### 1.3 Heightfield terrain — bilinear interpolation + gradient

(*Numerical Recipes in Fortran 77*, 2nd ed., Cambridge 1992, §3.6 "Interpolation in Two or More Dimensions", Eq. (3.6.3)–(3.6.5); verified from https://iate.oac.uncor.edu/~mario/materia/nr/numrec/f3-6.pdf):

```
t = (x − x_j)/(x_{j+1} − x_j),  u = (y − y_k)/(y_{k+1} − y_k)          # (3.6.4), t,u ∈ [0,1]
y1=h[j,k], y2=h[j+1,k], y3=h[j+1,k+1], y4=h[j,k+1]                      # (3.6.3), CCW from lower-left
h(x,y) = (1−t)(1−u)·y1 + t(1−u)·y2 + t·u·y3 + (1−t)·u·y4               # (3.6.5)
```
Gradient (analytic ∂ of 3.6.5): `∂h/∂x = [(1−u)(y2−y1) + u(y3−y4)]/Δx`, `∂h/∂y = [(1−t)(y4−y1) + t(y3−y2)]/Δy`. NR notes the interpolant is C0 but its gradient is discontinuous across cell edges (acceptable; use bicubic §3.6 if C1 needed). Vectorized: `j,k = floor(pos/Δ)` then 4 `gather`s + weights — pure tensor ops. Slope along heading for §1.1/§1.2: `S = ∇h · (cosθ, sinθ)`.

---

## 2) Parameters table

| Symbol | Meaning | Units | Value | Source (verified) |
|---|---|---|---|---|
| — | M1 road speed (governed) | m/s | 20.12 (45 mph); M1A1/A2 18.78 (42 mph) | FAS M1 fact file |
| — | M1 cross-country speed | m/s | 13.41 (30 mph) | FAS |
| — | M1 speed @10% slope | m/s | 8.94 (20 mph); M1A1/A2 7.60 (17 mph) | FAS |
| — | M1 speed @60% slope | m/s | 2.01 (4.5 mph); M1A1/A2 1.83 (4.1 mph) | FAS |
| a_avg | M1 accel 0→20 mph in 7 s (M1A1: 7.2 s) | m/s² | 1.277 (1.242) | FAS |
| m | M1 mass | kg | 54,431 (60 short tons); M1A1 63 t, M1A2 69.54 t | FAS |
| — | T-72 road speed | m/s | 16.7 (60 km/h) | Wikipedia T-72 |
| — | T-72 mass / power | t / hp | 41.0–44.5 / 780 (base) | Wikipedia T-72 |
| λ_max | max lateral drag coeff (skid-steer) | – | terrain-dependent; formula λ_t=λ_max/(0.925+0.15R/B) | arXiv:2007.08690 Eq. (3) |
| B | tread (track spacing) | m | model geometry (toy) | LaValle Eq. 13.16 (L) |
| m_i | pedestrian mass | kg | 80 | Helbing 2000 |
| τ_i | acceleration/relaxation time | s | 0.5 | Helbing 2000 & 1995 |
| v⁰ | desired speed: relaxed / normal / nervous / panic | m/s | ≈0.6 / ≈1.0 / ≲1.5 / >5 (up to 10) | Helbing 2000 |
| ⟨v⁰⟩, σ_v | desired speed distribution (walkway) | m/s | Gaussian 1.34 ± 0.26; v_max=1.3 v⁰ | Helbing–Molnár 1995 |
| A_i | repulsion strength | N | 2·10³ | Helbing 2000 |
| B_i | repulsion range | m | 0.08 | Helbing 2000 |
| k | body-force constant | kg·s⁻² | 1.2·10⁵ | Helbing 2000 |
| κ | sliding-friction constant | kg·m⁻¹·s⁻¹ | 2.4·10⁵ | Helbing 2000 |
| 2r_i | pedestrian diameter | m | uniform in [0.5, 0.7] | Helbing 2000 |
| — | door flow oracle | persons/s | 0.73 through 1 m door @ v⁰≈0.8 m/s | Helbing 2000 |
| V⁰_αβ, σ | 1995 pair potential (alternative) | m²s⁻², m | 2.1, 0.3 | Helbing–Molnár 1995 Eq. (13) |
| U⁰_αB, R | 1995 wall potential | m²s⁻², m | 10, 0.2 | Helbing–Molnár 1995 |
| 2φ, c | view-cone angle / rear weight (1995) | °, – | 200, 0.5 | Helbing–Molnár 1995 |
| — | Tobler coefficients | km/h, –, – | 6, −3.5, 0.05 | Tobler 1993 / Wikipedia |

---

## 3) Alternatives considered (and why not)

- **Full skid-steer terramechanics** (Wong & Chiang, "A general theory for skid steering of tracked vehicles on firm ground," *Proc. IMechE Part D* 215:343–355, 2001): shear-displacement integrals over the track contact patch per vehicle — accurate but requires per-track-element integration (inner spatial loop / large extra dim), needless for toys. The λ_t empirical formula is its standard lumped surrogate.
- **Ackermann/simple-car model** (LaValle Eq. 13.15, `θ̇=(u_s/L)tan u_φ`): wrong steering geometry — tanks pivot in place (`v=0, ω≠0` impossible for a car).
- **Dynamic skid-steer with slip-ratio states** (e.g. arXiv:2402.18065): adds ICR/slip states and stochastic terms; the exact-arc unicycle plus λ_t clamp captures the gameplay-relevant envelope.
- **ORCA/RVO** (van den Berg et al., ISRR 2011) for infantry: per-agent linear programs, branch-heavy, poorly batchable; not force-based physics.
- **1995 elliptical-potential SFM** (Eq. (4): `2b = √((‖r_αβ‖+‖r_αβ−v_β Δt e_β‖)² − (v_β Δt)²)`, Δt = 2 s): adds velocity anticipation; fine as an upgrade, but the 2000 circular model has the published contact terms (k, κ) you need for crowding/pushing and is simpler tensor math. View-cone weight `w(e,f)=1 or c=0.5` (1995 Eq. (7)) is an optional cheap mask.
- **Explicit (forward) Euler**: on the unicycle it spirals outward — per-step radius growth factor exactly `√(1+(ωΔt)²)`; exact-arc update has none. For SFM, symplectic Euler at same cost is the standard stable choice (Hairer et al. §I.1.2).
- **Bicubic/TIN terrain** (NR §3.6 bicubic; Delaunay TINs): C1 or adaptive but 16 coeffs/cell or irregular gathers; bilinear is the standard heightfield choice and fully broadcastable.

**Vectorization notes:** SFM pair terms are O(N²) broadcast (or reuse your top-K neighbor attention mask); `g(x)=relu(x)`; walls via SDF base (fits the obstacle-shape-primitives rule). Heightfield = floor + 4 gathers. The only genuinely loop-resistant items are the rejected ones above (contact-patch integrals, ORCA LPs).

---

## 4) Unit-test package (pytest oracles)

### 4.1 Unicycle / tank
- **Exact quarter arc:** `(x,y,θ)=(0,0,0), v=1 m/s, ω=1 rad/s, Δt=π/2` → `(x',y',θ') = (1.0, 1.0, π/2)` exactly (Eq. 5.9). Center `(x_c,y_c)=(0,1)`.
- **Circle closed form:** `v=2, ω=0.5` → radius `R=v/ω=4.0`, center `(0,4)` from origin-heading-0; after `n` steps summing to `t=2π/ω=4π s` pose returns to `(0,0,0 mod 2π)` (atol 1e-6). **Invariant:** `‖p_t−c‖=4.0` every step.
- **Euler-drift regression:** explicit Euler, `ωΔt=0.1` → radius grows by factor `√(1.01)=1.0049876` per step (assert, documents why exact arc is used).
- **ω→0 guard:** `v=1, ω=1e−12, Δt=0.1` → `‖(x',y') − (0.1, 0)‖ < 1e−9`.
- **Diff-drive map (Eq. 13.16):** `r=0.05 m, L=0.3 m`: `u_l=u_r=10` → `v=0.5 m/s, ω=0`; `u_r=10, u_l=−10` → `v=0, ω=10/3 rad/s`.
- **Envelope:** `v_track,max=1, B=0.5`: pivot `ω_max=4.0 rad/s`; at `v=1` → `ω=0`.
- **Friction clamp:** `λ_t g=0.7·9.81=6.867 m/s²`, `v=10 m/s` → `|ω|≤0.6867 rad/s`, `R_min=v²/λ_t g=14.562 m`. **λ_t formula:** `R=0` → `λ_t=λ_max/0.925=1.0811·λ_max`; `R=B` → `λ_max/1.075=0.93023·λ_max`. Moment: `λ_t=0.5, m=1000 kg, l=1.5 m` → `M=0.25·0.5·1000·9.81·1.5=1839.375 N·m`.
- **Slope caps (M1 oracle, P_w=571.34 kW, f_r=0.020271, m=54431 kg):** model reproduces `v(10%)=8.9408 m/s` and `v(60%)=2.0117 m/s` (rtol 1e-3, by construction); flat prediction 52.8 m/s must be cut by governor to 20.117 m/s. **Property:** `v_cap` strictly decreasing in grade for `s∈[0,1]`.
- **Accel limit:** from rest, `a_max=1.277 m/s²` → after 7.0 s, `v=8.94 m/s` (=20 mph).

### 4.2 Social force / soldier (params: m=80, τ=0.5, A=2000, B=0.08, k=1.2e5, κ=2.4e5, r_i=r_j=0.3, v⁰=0.8)
- **Two-agent equilibrium spacing:** desired directions head-on; equilibrium at `v=0` when `A·exp((r_ij−d)/B) = m v⁰/τ = 128 N` ⇒ `d* = r_ij + B·ln(τA/(m v⁰)) = 0.6 + 0.08·ln(15.625) = 0.6 + 0.08·2.7488722 = 0.8199098 m`. Assert net force ≈ 0 (atol 1e−9 N) at `d*`; repulsion wins for `d<d*`, driving wins for `d>d*`. (`d*>0.6=r_ij` ⇒ `g=0`, contact terms off — consistent.)
- **Wall equilibrium:** same balance with Eq. (3): `d* = r_i + 0.2199098 = 0.5199098 m`.
- **Driving-term relaxation closed form:** no interactions, from rest: `v(t)=v⁰(1−e^{−t/τ})`; at `t=τ=0.5 s`: `v=0.8·0.6321206=0.5056965 m/s`. One symplectic-Euler step `Δt=0.1`: `Δv=(0.8/0.5)·0.1=0.16 m/s`.
- **Contact terms:** `d_ij=0.5` (overlap 0.1 m), `Δv_ji^t=1 m/s` → body force `k·0.1=1.2·10⁴ N`, sliding friction `κ·0.1·1=2.4·10⁴ N` (directions `n_ij`, `t_ij`).
- **Momentum invariant:** driving terms and walls off, any config: `Σ m_i v_i` conserved (pair forces antisymmetric: `f_ij=−f_ji`), atol 1e−8.
- **Speed cap (1995 Eq. 11–12):** `‖w‖=2.0 m/s, v⁰=1.34` → realized speed `=1.3·1.34=1.742 m/s`; `‖w‖=1.0` → unchanged.
- **Flow oracle (integration test):** ~0.73 persons/s through a 1 m door at `v⁰=0.8 m/s` (Helbing 2000 calibration; tolerance ±20%).

### 4.3 Tobler (W in km/h; S = tanθ)
- `W(0) = 6e^{−0.175} = 5.0367423` (=1.3990951 m/s)
- `W(+0.10) = 6e^{−0.525} = 3.5493319` (=0.9859255 m/s)
- `W(−0.10) = 6e^{−0.175} = 5.0367423` (mirror of flat)
- `W(−0.05) = 6.0` exactly (global max). **Property:** `W(S) = W(−0.10−S)` (symmetry about S=−0.05); strictly decreasing for `S>−0.05`.

### 4.4 Bilinear heightfield (unit cell, y1=0, y2=1, y3=3, y4=2 per NR corner order)
- Corners: `h(0,0)=0, h(1,0)=1, h(1,1)=3, h(0,1)=2` (exact).
- Center `t=u=0.5`: `h=(0+1+3+2)/4=1.5`. Interior `t=0.25,u=0.75`: `h=0.1875·0+0.0625·1+0.1875·3+0.5625·2=1.75`.
- Gradient at `t=0.25,u=0.75` (Δx=Δy=1): `∂h/∂x=(1−u)(y2−y1)+u(y3−y4)=0.25·1+0.75·1=1.0`; `∂h/∂y=(1−t)(y4−y1)+t(y3−y2)=0.75·2+0.25·2=2.0`.
- **Properties:** exact reproduction of any plane `h=a+bx+cy` (e.g. `2+3x−5y` at 20 random points, atol 1e−6, incl. exact gradient `(3,−5)`); interpolant within `[min(y1..y4), max(y1..y4)]`; value continuous across shared cell edges; gradient may jump across edges (NR §3.6 statement) — assert continuity only for value.

---

## 5) Sources (all URLs fetched and content verified during this task unless noted)

1. LaValle, S. M., *Planning Algorithms*, Cambridge Univ. Press, 2006 — §13.1.2, Eq. (13.15)–(13.17). https://lavalle.pl/planning/node659.html (simple car: node658)
2. Thrun, S., Burgard, W., Fox, D., *Probabilistic Robotics*, MIT Press, 2005 — §5.3, Eq. (5.5)–(5.10), Tables 5.1/5.3. https://ccc.inaoep.mx/~mdprl/documentos/CH5.pdf
3. Helbing, D., Farkas, I., Vicsek, T., "Simulating dynamical features of escape panic," *Nature* 407:487–490 (2000) — Eq. (1)–(3) + all parameters. Preprint: https://arxiv.org/abs/cond-mat/0009448
4. Helbing, D., Molnár, P., "Social force model for pedestrian dynamics," *Phys. Rev. E* 51:4282–4286 (1995) — Eq. (2),(4),(7),(11)–(13) + parameters. Preprint: https://arxiv.org/abs/cond-mat/9805244
5. Sticco, I. M., Frank, G. A., Dorso, C. O., et al., "Effects of the body force on the pedestrian and the evacuation dynamics," *Safety Science* 121 (2020) — velocity Verlet, Δt=10⁻⁴ s. https://arxiv.org/pdf/2003.02890
6. Swope, W. C., Andersen, H. C., Berens, P. H., Wilson, K. R., *J. Chem. Phys.* 76:637 (1982) — velocity Verlet scheme (canonical; not fetched).
7. Hairer, E., Lubich, C., Wanner, G., *Geometric Numerical Integration*, 2nd ed., Springer, 2006, §I.1.2 — symplectic Euler (canonical textbook; not fetched).
8. FAS Military Analysis Network, "M1 Abrams Main Battle Tank" fact file — speeds (road/cross-country/10%/60% slope), 0–20 mph times, weights. https://man.fas.org/dod-101/sys/land/m1.htm
9. Wikipedia, "T-72" — 60 km/h road, 780 hp, 41.0–44.5 t. https://en.wikipedia.org/wiki/T-72
10. Liu, T., et al., "Transfer Deep Reinforcement Learning-enabled Energy Management Strategy for Hybrid Tracked Vehicle" — Eq. (1) skid-steer kinematics, Eq. (3) `λ_t = λ_max(0.925+0.15R/B)^{−1}`, `M = 0.25 λ_t m g l` (attributed therein to Zou et al., *Appl. Energy* 171:372–382, 2016). https://arxiv.org/pdf/2007.08690
11. Wong, J. Y., Chiang, C. F., "A general theory for skid steering of tracked vehicles on firm ground," *Proc. IMechE Part D* 215:343–355 (2001) — full terramechanics alternative. https://journals.sagepub.com/doi/10.1243/0954407011525683 (abstract verified)
12. Wong, J. Y., *Theory of Ground Vehicles*, Wiley — tractive effort / motion-resistance balance (canonical textbook; not fetched).
13. Gillespie, T., *Fundamentals of Vehicle Dynamics*, SAE, 1992, ch. 6 — lateral acceleration `v²/R` in steady cornering (canonical textbook; not fetched).
14. Tobler, W., "Three presentations on geographical analysis and modeling," NCGIA Technical Report 93-1, Feb 1993 — hiking function; formula verified via https://en.wikipedia.org/wiki/Tobler%27s_hiking_function
15. Press, W. H., et al., *Numerical Recipes in Fortran 77*, 2nd ed., Cambridge, 1992, §3.6 — Eq. (3.6.3)–(3.6.5) bilinear interpolation + gradient-discontinuity caveat. https://iate.oac.uncor.edu/~mario/materia/nr/numrec/f3-6.pdf
16. Alexander, R. McN., *Nature* 261:129–130 (1976) — Froude-number dynamic similarity for speed scaling (canonical; not fetched).

**Caveats:** no official published hull pivot-turn rate exists for M1/T-72 (turret rates, e.g. 9 s/360°, are turret-only — do not reuse); derive pivot `ω_max = 2 v_track,max/B` from the sourced kinematics. T-72 cross-country speed and λ_max terrain values were not verifiable from primary sources — treat as tunables. The `P_w=571 kW, f_r=0.0203` pair is fit to the two FAS slope-speed data points, not an independent spec.


====================================================================================================
# REPORT: completeness-audit
====================================================================================================

# Audit: 5 oracle reports for drone-swarm sim physics

## 1) GAPS — physics no report covers

| # | Gap | v1? | Sourced model to use |
|---|---|---|---|
| G1 | **Drone–obstacle / drone–terrain / drone–drone collision & contact.** Core to contact-kamikaze gameplay; the only contact physics anywhere is Helbing's soldier-soldier/wall terms. Nothing says what happens when a drone hits a tree SDF, terrain, or another drone. | **v1 — blocking.** | Compliant (penalty) contact: **Hunt & Crossley, "Coefficient of restitution interpreted as damping in vibroimpact," *J. Appl. Mech.* 42:440–445, 1975** (nonlinear spring–damper `F = kδ^n + λδ^n δ̇`; single-pass, elementwise on SDF penetration δ — fits the no-loops rule, unlike iterative impulse solvers, see §3). Impulse-with-restitution alternative: **Baraff, "Physically Based Modeling: Rigid Body Simulation," SIGGRAPH course notes, 1997/2001.** Position-based alternative: **Macklin, Müller, Chentanez, "XPBD," MIG 2016** (but its Gauss–Seidel form is loop-y; use one Jacobi pass). Note the ground-units report's SDF wall term (Helbing Eq. 3) is a ready-made template: drones can reuse the same relu-penetration force against the existing circle/square SDF base (consistent with the obstacle-shape-primitives memory rule). |
| G2 | **Kamikaze detonation / crash energetics** (kill radius, damage vs impact speed). Reports stop at flight; the *weapon* is unmodeled. | v1 needs a **rule** (contact-kill or fixed radius); sourced energetics can wait. | Impact severity: kinetic energy ½mv² with published injury thresholds — **FAA/ASSURE "UAS Ground Collision Severity Evaluation" Final Report (A4), 2017** (blunt-trauma KE thresholds; historical RCC 58 ft·lbf criterion). Blast radius, if you ever want it: **Kingery & Bulmash, ARBRL-TR-02555, 1984** airblast curves + Hopkinson–Cranz cube-root scaling Z=R/W^{1/3} (UFC 3-340-02). Both are lookups → pure elementwise. |
| G3 | **Battery / endurance.** Quadrotor report mentions the Nature-2023 grey-box (P = c_d Ω³/η) but defers it; no capacity/discharge model exists anywhere. Kamikaze drones with no energy budget never have to commit. | **v1-lite**: integrate `E -= P·dt` against capacity using the already-sourced P = c_d Ω³/η. Voltage-sag thrust derating can wait. | **Traub, "Range and Endurance Estimates for Battery-Powered Aircraft," *J. Aircraft* 48(2):703–707, 2011** (Peukert-corrected endurance, n≈1.3 for LiPo); **Tremblay & Dessaint, *World Electric Vehicle J.* 3, 2009** (the Simulink generic battery voltage model) if sag is wanted. |
| G4 | **Sensor/actuator noise for sim-to-real feel.** Motor lag is modeled; observation noise, gyro bias, and command latency are not — yet the training-sim lineage the reports cite does this. | Can wait for a game; **v1 if RL robustness matters.** | **Molchanov et al., IROS 2019** (the report's own source 5) adds observation + motor noise sampled from real logs — extract that section. IMU noise standard form (white noise + bias random walk, Allan-variance parameters): **IEEE Std 952-1997**; accessible derivation: **Woodman, "An introduction to inertial navigation," Univ. Cambridge UCAM-CL-TR-696, 2007.** Pure delay: ring-buffer, sourced as motor-delay identification in arXiv:2404.07837 (already cited as a pointer in the quadrotor report). |
| G5 | **ρ-coupling of thrust.** Aero report ships ISA ρ(h), but the quadrotor report's c_l/k_f are constants — as written, the density module is dead code. | v1: either drop ISA (band < 500 m ⇒ 5% error) or couple. | Standard rotor nondimensionalization T = C_T ρ A (ΩR)²: **Leishman, *Principles of Helicopter Aerodynamics*, Cambridge Univ. Press, 2000, ch. 2** → scale k_f by ρ(h)/ρ₀. One multiply. |
| G6 | **Rotational gust inputs (p_g, q_g, r_g).** Dryden here produces only linear wind; MIL-F-8785C also specifies angular-rate spectra (gust gradients → body torques). | Wait. | MIL-F-8785C / MIL-HDBK-1797 angular-rate filters, reproduced in the same MATLAB Dryden doc the wind report already cites [S3/S4]. |
| G7 | **Enemy fire / projectile ballistics** — only if tanks/soldiers shoot back (spec says contact-kamikaze, so possibly out of scope). | Conditional. | Point-mass trajectory with drag: **McCoy, *Modern Exterior Ballistics*, Schiffer, 1999** — closed-form-steppable, elementwise. |
| G8 | Terrain-obstacle wind wakes (shelter behind trees/rocks), mud/rain rolling-resistance coupling, drone downwash on soldiers, motor failure. | All wait. | Rotor failure if ever: Sun et al., fault-tolerant quadrotor flight literature; wakes: no cheap sourced model worth it. |

Spawn energetics per se need no physics (initial-state sampling); crash energetics is G2.

## 2) CONFLICTS

1. **Gravity: 9.8 vs 9.81 vs 9.80665.** GPD (quadrotor §2.1, reference-sims) hardcodes **9.8**; ICRA22/ground-units use 9.81; aero/ISA uses 9.80665. **Resolution:** 9.81 game-wide; keep 9.8 *only inside* the GPD parity tests (reference-sims T1–T10 are invalid otherwise). Never let both constants leak into one module.
2. **Three drag models that must not be stacked.** Quadrotor report: linear body drag −K_v v_B (ICRA22, k_v=0.3/0.3/0.15 N·s/m). Aero report: quadratic ½ρC_dA|v|v **plus** Faessler linear rotor drag (d_x=0.544 s⁻¹). GPD: linear ∝ Σω. The ICRA22 K_v is a lumped fit that already *contains* rotor drag over its speed range (mass-normalized: 0.3/0.768 = 0.39 s⁻¹ ≈ Faessler's 0.386–0.544). Stacking ICRA22 K_v + Faessler D + quadratic C_dA double/triple-counts. **Winner:** ICRA22 K_v alone for the FPV parameter set (same platform, same source as the dynamics); Faessler+quadratic is the alternative pair (gives you the k_h thrust correction) — pick one pair per platform, assert in code that only one drag module is active.
3. **Ground-effect ratio semantics are inverted between models.** C&B and GPD give T_IGE/T_OGE **> 1** (thrust augmentation: +15.2% at z=0.05 m); Kan Model 1 gives **0.88** at z=R — that is *required-thrust*-to-hover ratio, not produced thrust. Applied naively as a thrust multiplier, Kan makes ground effect push drones *down*. Magnitudes agree once inverted (1/0.88 = 1.136 ≈ 1.15). **Winner:** GPD additive per-rotor form for the CF set (parity-testable); if Kan is used for forward flight, invert and document the convention, with a sign test (see §4).
4. **Mixer signs / rotor numbering.** Quadrotor report: rotor 0 at (+x,+y), τx = (F0+F1−F2−F3)·L/√2. Reference-sims (quoting the urdf + code verbatim): m0 at (+0.028, −0.028), `x_torque = −(f0+f1−f2−f3)·(L/√2)`. Position labels *and* the roll sign differ. **Winner: reference-sims** — it quotes the fetched urdf and source line; the parity trajectory T10 is the arbiter. Adopt the urdf ordering in code and delete the other convention from docs.
5. **Crazyflie parameter sets.** m = 0.027 (GPD) vs 0.030 (RotorPy); Izz 2.17e-5 vs 2.89e-5; k_f in N/RPM² vs N/(rad/s)² (reference-sims correctly warns not to mix); **τ_m = 0.0375 s (Molchanov) vs 0.072 s (RotorPy)** — a genuine 2× disagreement between two legitimate fits. **Resolution:** GPD set wholesale for parity oracles; for training, domain-randomize τ_m over [0.0375, 0.072] rather than picking a winner.
6. **Body-rate clamp.** Quadrotor report: 1998°/s firmware cap, 11.56 rad/s raced; reference-sims: Betaflight *default* Actual-rates max = 670°/s (= 11.7 rad/s). Not contradictory but two different numbers will get hardcoded. **Resolution:** 670°/s default clamp (matches the raced envelope), 1998°/s as hard saturation. Crazyflie [−π, π] only for the CF param set.
7. **Dryden V.** Wind report sets V = mean wind speed (frozen turbulence past a hoverer, with an unsourced V_min floor); MIL-F-8785C defines V as **vehicle airspeed** — for a 20 m/s FPV drone the report's choice underestimates encounter frequency several-fold. The pregenerated `[N_envs,T,3]` format cannot honor per-agent airspeed. **Winner:** the spec's semantics is the physics; accept the pregen approximation but the docstring must quantify it (the frozen-line advection upgrade partially fixes streamwise; lateral stays wrong). Also: pick MIL-F-8785C vs MIL-HDBK-1797 length-scale conventions once (report flags this — enforce with a test asserting L_u(1000 ft) = 1000 ft).
8. **Quaternion conventions.** Quadrotor: Hamilton **w-first**; GPD/reference-sims: **[x,y,z,w]**. Trivial, and the single most likely parity-test killer. Convert at the oracle boundary only.
9. **Timestep.** 1 kHz symplectic Euler (quadrotor) vs 240 Hz (GPD parity) vs 10–50 ms (ground units). Decide a game tick with drone substeps; note SFM contact stiffness k=1.2e5, m=80 → contact frequency ≈ 38.7 rad/s: at Δt=0.05 s the symplectic-Euler stability bound (ωΔt < 2) is only ~2× away — the report's force clamp is doing real work; test it (§4).

## 3) VECTORIZATION RISKS

- **`torch.where` both-branch NaN poisoning** (the pattern appears 5+ times: quaternion exp `sin‖θ‖/‖θ‖`, GPD `_integrateQ` zero-ω skip, unicycle ω→0 arc, λ_t's R=|v/ω|, C&B pole at z=R/4). `torch.where` evaluates both branches; the unselected 0/0 produces NaN that poisons `forward` under `torch.autograd.detect_anomaly` and any backward pass. Mandate the safe-denominator idiom (`denom = torch.where(mask, denom, ones)` *before* dividing) in the module template, not per-author discretion.
- **Collision resolution (gap G1):** simultaneous multi-contact impulse solvers are Gauss–Seidel loops — banned by the no-loops rule. Choose penalty (Hunt–Crossley) or one Jacobi projection pass per step; accept residual overlap. This should be a stated design decision, not discovered later.
- **SFM O(N²) pair broadcast:** fine for tens of soldiers, but `[E, N, N, 2]` tensors explode with wide-batch envs (the memory rule says saturate GPU with parallel envs). Reuse the existing top-K neighbor gather from the attention enemy instead of full N².
- **Betaflight Level-B PID:** I-term reset, saturation priority, and pure delay need stateful masks + ring buffer — vectorizable but the most branch-dense module proposed; the reports correctly default to Level A. Keep Level B out of v1.
- **Wind biquad pregeneration:** torch has no batched IIR; the sequential scan over T is fine *offline* (scipy `lfilter` over the env axis), but never let it drift into the hot path.
- **Tank slope cap** `P_w/(mg(sinα + f_r cosα))`: denominator → 0 or negative downhill (sinα < −f_r cosα) ⇒ inf/negative v_cap. The report clamps downhill to v_gov by fiat but the formula as written needs an explicit guard before the min().
- Everything genuinely loop-resistant (BEM, implicit induced velocity, ORCA LPs, Veers–Cholesky coherence, Wong–Chiang contact-patch integrals) was already correctly rejected by the reports.

## 4) TEST-PACKAGE QUALITY

Overall unusually strong — nearly every test has a hand-computable number. Weak spots:

- **wind T9** is the weakest in the set ("documentation-level assert" = it tests `exp()`). Replace with a real oracle on the frozen-line path: for the OU u-channel, cross-correlation between agents separated by r must equal the autocorrelation at lag r/Ū = **e^(−r/L_u)**; numbers: r=20 m, L_u=94.73 m (their own T1 value) → **ρ = 0.8097 ± 0.02** pooled over 8192 envs. Also add a pooled-periodogram vs Φ_v(ω) shape test (rtol 5% on a fixed frequency grid) — currently the √3-zero biquad's *spectrum* is never checked, only its variance.
- **quadrotor T8**: "never overshoots" is vacuous for a first-order lag (can't overshoot by construction) and unquantified. Replace with: ω_x(2τ) = π(1−e⁻²) = **2.7163 rad/s** ± 1e-6, plus monotonicity on a 1 ms grid.
- **quadrotor T4**: "growth per step < 1e-12" vs "< 1e-5 total in float32" is ambiguously worded — pin it as total drift: |‖q‖−1| < 1e-9 after 1e5 f64 steps.
- **aero T9**: "bitwise-close (atol 1e-6)" is self-contradictory. For identical dtype/device, elementwise ops must give `torch.equal` (exact); reserve atol for cross-device.
- **aero T7**: "within 5%" and "consistent with Fig. 4 trend" — keep the exact closed form (φ = **8.11648°** from tan φ = kV/mg) and add a convergence criterion (steady within 5τ). Also add a drag-regime crossover test for conflict #2: with m·d_x = 0.3318 N/(m/s) and ½ρC_dA = 0.0200 N/(m/s)², assert linear > quadratic at 5 m/s and quadratic > linear at 25 m/s (crossover ≈ 16.6 m/s) — this pins that only one drag pair is active.
- **aero T3 / ground-effect sign**: add the conflict-#3 direction test — any implemented model must satisfy `thrust_multiplier(z) ≥ 1` and → 1 as z→∞ for the augmentation convention (would have caught Kan misapplied at 0.88).
- **ground-units**: 4.2 flow oracle (±20%, stochastic, integration) is fine but should be marked slow/non-blocking. Missing numeric: Tobler×SFM coupling — v⁰=1.0 flat, S=+0.10 ⇒ v⁰·W(0.1)/W(0) = 3.5493/5.0367 = **0.70468 m/s**. Missing: SFM stability-guard test at game Δt (two overlapping agents, Δt=0.05 s, assert ‖v‖ bounded by the clamp and no oscillation growth over 100 steps) — the guard is load-bearing per conflict #9 and untested. Missing: simultaneous v/ω clamp ordering test (envelope + friction clamp applied in a fixed order gives a specific (v,ω); pin it).
- **reference-sims T10**: "pin to a tag (e.g. current main)" is vague — require an exact commit SHA and a committed golden `.npz` of all 480 steps, so CI never needs to install pybullet.
- **Cross-cutting misses (all reports):** no dt-convergence test anywhere — add a Richardson check on T2's closed form (halve Δt ⇒ error halves, slope 1.0 ± 0.05, catching accidental O(1) integrator bugs); no tests exist for G1–G3 because the modules don't exist — when collision/battery land, seed them with: Hunt–Crossley restitution sweep (e from λ, k against the 1975 closed relation) and battery endurance = capacity/(P_hover) closed form.


====================================================================================================
# REPORT: aa-fire-ballistics
====================================================================================================

# Ground-to-Air Fire vs. Small Drones — Model Recommendation & Grounded Parameters

Scope: batched/vectorized PyTorch sim, ~30–60 Hz, tens of shooters × tens of drones, deterministic. Every equation below is sourced; approximations derived from cited values are flagged `[approx]`.

## 1. Recommended model

**Use option (c): lead-predicted aim + dispersion-perturbed true projectile — but tiered.**

- **Autocannon / tank (25–30 mm, projectile TOF 0.3–1.5 s, drop matters):** true point-mass projectile (Section 3), reusing the sim's existing bullet integrator. Aim direction from the constant-velocity intercept solution (Section 6); perturb the launch direction by a deterministic-hash angular dispersion drawn from the mil-dispersion distribution (Section 5). Hit = geometric bullet-vs-drone overlap already handled by the bullet machinery.
- **Small-arms / soldier (5.56 mm at <=150 m, TOF < 0.2 s, essentially flat-fire):** prefer **CEP-based hitscan** (Section 4) with range- and angular-speed-dependent sigma, evaluated as a closed-form P(hit) and consumed by the deterministic hash. One tensor op per (shooter,drone) pair — no per-bullet state.

**Determinism:** dispersion is a *distribution*, not entropy. Draw the perturbation from a hash of (shooter_id, drone_id, shot_index, tick) mapped through Box–Muller. The model only requires the distribution to be right, which a counter-based hash satisfies exactly and reproducibly across the batch.

## 2. Parameters table

| Quantity | Value | Units | Source |
|---|---|---|---|
| Std gravity g | 9.80665 | m/s^2 | ISO 80000-3 |
| ISA sea-level air density rho | 1.225 | kg/m^3 | Wikipedia External ballistics |
| 5.56 M855 bullet mass | 62 gr = 4.0 g | g | Wikipedia 5.56x45mm NATO |
| M855 diameter d | 5.70 | mm | Wikipedia 5.56x45mm NATO |
| M855 muzzle velocity v0 | 948 | m/s | Wikipedia 5.56x45mm NATO |
| M855 G7 BC | 0.151 | - | Wikipedia 5.56x45mm NATO |
| M855 G1 BC | ~0.304 | - | ShootersCalculator |
| 25 mm M242 MV (M792 HEI-T) | 1100 | m/s | Wikipedia M242 Bushmaster |
| 25 mm M791 APDS-T MV | 1345 | m/s | Wikipedia M242 Bushmaster |
| 30 mm Mk44 HEI-T MV | 1080 | m/s | NavWeaps 30mm Bushmaster II |
| 5.56 inherent 1-sigma/axis dispersion [approx] | 0.17-0.19 (~0.6 MOA) | mrad | Mil-C-71186 via defensereview + USAR marksmanship |
| 5.56 mil-spec acceptance | <=5 MOA | MOA | Mil-C-71186 |
| 25 mm dispersion [approx] | 0.5-1 | mrad | order-of-magnitude (Grokipedia M242) |
| 30 mm Mk44 dispersion [approx] | ~0.5 @1000 m | mrad | order-of-magnitude |
| Conversions | 1 mrad = 3.438 MOA; 1 MOA = 0.2909 mrad | - | standard |

Note: G7 BC 0.151 is the hard-cited drag anchor; constant supersonic Cd ~ 0.30 for M855 is a modeling simplification DERIVABLE from that BC but is [approx].

## 3. Exterior ballistics — point-mass with quadratic drag

Drag (Wikipedia External ballistics; McCoy Modern Exterior Ballistics ch.5):
  F_D = 1/2 rho Cd A v^2,  A = pi d


====================================================================================================
# REPORT: aa-fire-ballistics (ground-to-air fire vs small drones)
====================================================================================================

## Recommended model — tiered hybrid
- TANK autocannon (25-30mm, TOF 0.3-1.5s): TRUE point-mass projectile w/ quadratic drag (reuse the
  3D bullet machinery). Aim = constant-velocity lead intercept; launch direction perturbed by a
  deterministic-hash angular dispersion (det_rand -> Box-Muller). Hit = geometric bullet-vs-drone overlap.
- SOLDIER rifle (5.56mm <=150m, TOF <0.2s): CEP-based HITSCAN, closed-form P(hit), one elementwise op
  over [E,D]. No bullet entities.
- Decision rule: hitscan when t_f * f_maneuver << 1, projectile otherwise.

## Formulas (all cited)
- Point-mass drag ODE: dv/dt = g - k*|v_air|*v_air, k = rho*Cd*A/(2m); semi-implicit Euler.
  (McCoy, Modern Exterior Ballistics ch.5; Wikipedia External ballistics.)
- Flat-fire closed forms (test oracles): u(x)=u0*exp(-k*x); t(x)=(exp(k*x)-1)/(k*u0); drop=-0.5*g*t(x)^2.
- Hit probability (military OR standard, Rayleigh/bivariate normal; Wikipedia CEP, DTIC AD1043284):
  P_hit(r) = 1 - exp(-r^2/(2*sigma^2)); sigma_pos = R*sigma_ang; CEP = 1.17741*sigma.
- Crossing-target degradation: sigma_total^2 = sigma_disp^2 + sigma_track^2 + sigma_maneuver^2,
  sigma_maneuver ~ 0.5*a_perp*t_f^2 (METU air-defense thesis). => drone lateral accel (jinking)
  PHYSICALLY reduces P_hit. This is the sourced mechanism that makes evasion work.
- Lead intercept (Game Developer / Playtechs, standard): (v.v - s^2)t^2 + 2(p.v)t + p.p = 0,
  take smallest positive root; aim = p + v*t.

## Parameters (values, units, sources)
- g = 9.80665 m/s^2; rho = 1.225 kg/m^3 (ISA sea level).
- 5.56 M855: m=4.0 g, d=5.70 mm, v0=948 m/s, G7 BC 0.151; dispersion ~0.6 MOA best .. 5 MOA milspec
  (~0.17-1.5 mrad). (Wikipedia 5.56x45mm NATO; Mil-C-71186.)
- 25 mm M242: v0=1100 m/s (M792), 1345 (APDS); ~0.5-1 mrad. (Wikipedia M242 Bushmaster.)
- 30 mm Mk44: v0=1080 m/s (HEI-T), 1385 (APFSDS); ~0.5 mrad @1000 m. (NavWeaps 30mm Bushmaster II.)
- Reality anchor: unaided rifle P_hit on a small FPV @100 m ~ low tens of % (Ukraine reports, MWI
  West Point); AI fire-control (SMASH) ~68% @100 m. Game numbers scale to toy size but sit in that band.

## Unit-test package (hand-computed vectors)
- T1 vacuum range oracle (k->0): v0=100, theta=30deg -> R=882.799 m, H=127.42 m, T=10.1937 s;
  monotone R decrease as k grows.
- T2 flat-fire drag: u0=948, k=1.17e-3, x=100 -> u=843.3 m/s, t=0.11190 s, drop=6.14 cm (<1%).
- T3 CEP<->sigma: sqrt(2 ln 2)=1.17741; P_hit(r=CEP)=0.5000 exactly; R95=2.4477*sigma -> 0.9500.
- T4 P_hit(r/sigma): 0.5/1.0/2.0/3.0 -> 0.11750/0.39347/0.86466/0.98889. Named: rifleman(100m,3mrad,
  r=0.15)->0.1175; fire-control->0.6753; 30mm(800m,0.5mrad,r=0.25)->0.1774.
- T5 lead quadratic: p=(100,0), v=(0,20), s=300 -> t=0.334077 s, aim=(100,6.68155),
  ||aim||=s*t=100.2230; lead angle 66.75 mrad.

## Sources
Wikipedia CEP; DTIC AD1043284 / AD0412332; Wikipedia External ballistics; McCoy Modern Exterior
Ballistics ch.4-5; arXiv:2206.02397 (vector drag ODE); Wikipedia 5.56x45mm NATO; DTIC ADA530895
(M855 aero); Wikipedia M242 Bushmaster; NavWeaps 30mm Bushmaster II; DefenseReview Mil-C-71186;
METU thesis "Single Shot Hit Probability Computation for Air Defense"; Game Developer "Predictive
Aim Mathematics"; Playtechs "Aiming at a moving target"; MWI West Point; Wikipedia Range of a projectile.


====================================================================================================
# IMPLEMENTATION MANDATES (binding, from the audit + user directives)
====================================================================================================

HARD RULE — NO PYTHON LOOPS anywhere reachable from the sim hot path (env._core, step_dec inner
tick loop excepted and marked TIME-LOOP-OK, both obs fns, and every oracle function). Pure broadcast
tensor ops only. Rationale: the whole point is one batched sim over [P,N,...] running N envs in
lockstep on the GPU; a python for/while over agents/enemies/obstacles/bullets destroys that. Offline
schedule pregen (schedule_drone.py) MAY loop (it's setup, not the hot path), like monstro/froggo.
The AST no-loop test (tests/test_env.py) enforces this mechanically.

CONSTANTS: gravity = 9.81 game-wide (9.8 ONLY inside the gym-pybullet-drones parity test). rho=1.225
constant in v1. ONE drag model active: ICRA22 lumped linear K_v for the FPV param set (code asserts
a single drag path). Ground effect uses the AUGMENTATION convention (multiplier >= 1, -> 1 as z->inf;
sign test enforced). Rotor ordering / mixer signs = the fetched cf2x.urdf convention; the golden
parity trajectory is the arbiter. Quaternion Hamilton w-first internally; convert at the parity
boundary only. Params: GPD cf2x set wholesale for parity; domain-randomize motor tau in [0.0375,0.072]s
for training.

VECTORIZATION SAFETY: safe-denominator idiom is mandatory — denom = where(mask, denom, 1.0) BEFORE
dividing (torch.where evaluates BOTH branches, so a 0/0 in the dead branch NaN-poisons the backward
pass). Applies to: quaternion exp sinc at |theta|->0, unicycle omega->0 arc, R=|v/omega|, C&B pole at
z=R/4, lead-solution discriminant, tank slope-cap downhill guard. eps inside every sqrt.

GAPS resolved in v1: G1 drone<->drone contact = Hunt-Crossley penalty (oracles/contact.py, single
Jacobi pass, residual overlap accepted). G2 kamikaze = contact-kill rule (KE-severity upgrade later).
G3 battery = E -= P*dt, P = c_d*Omega^3/eta grey-box (Nature 2023), E=0 -> forced descent. G5 rho
constant (<5% error <500m AGL). Deferred (documented): ISA density coupling, rotational gusts,
voltage sag, sensor/actuator noise, downwash-on-soldiers.
