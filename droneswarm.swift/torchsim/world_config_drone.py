"""WorldConfig — every global physics/game constant for the droneswarm tensor sim in ONE place.

The tensor sim (env_drone.py) is the source of truth for ALL simulation; a future Swift/Metal
client will only DRAW state and copy these constants from the exported JSON, so they can never
drift (the drift that broke the old Metal demos). Per-type unit stats (drone/enemy/weapon) that
vary within a game live in the schedule; this holds the globals only.

UNITS ARE STRICT SI: metres, seconds, kilograms, radians. Every value below is either (a) quoted
from a cited source in oracles/SOURCES.md, or (b) a deliberate game-design choice flagged as such.
NO invented physics: the drone dynamics constants come from the FPV / gym-pybullet-drones parameter
sets, wind from MIL-F-8785C Dryden, ground units from Helbing/Tobler, AA from exterior-ballistics +
military-OR CEP. See oracles/SOURCES.md §<report> for each.

Decision cadence (froggo semi-MDP precedent): physics runs at `1/dt` Hz inside the compiled `_core`;
the policies act every `act_every` ticks (zero-order hold). One env decision step = `act_every`
compiled ticks. This keeps CTBR faithful (the inner rate loop runs at physics rate) and cuts PPO
rollout storage by `act_every`.
"""
from dataclasses import dataclass, asdict, fields
import json
import math


@dataclass
class WorldConfig:
    # ================= core kinematics =================
    dt: float = 1.0 / 50.0          # physics timestep (50 Hz). Level-A CTBR updates are exact ZOH
    #                                 exponentials (unconditionally stable), so 50 Hz is ample; the
    #                                 1 kHz figure in SOURCES applies to the full Level-B explicit sim.
    act_every: int = 5              # policy acts every 5 ticks -> 10 Hz decisions (Swift/Nature CTBR nets
    #                                 run 100 Hz; 10 Hz is the game-decision rate, held between ticks)
    gravity: float = 9.81           # m/s^2 GAME-WIDE (SOURCES conflict #1: 9.8 ONLY inside the GPD parity test)

    # ================= drone: FPV kamikaze quad, CTBR Level-A response model =================
    # 5-inch-class FPV scale (SOURCES quadrotor-ctbr: Agilicious/racing envelope). Mass/T2W are the
    # game-design platform; lags/clamps are the sourced numbers.
    drone_mass: float = 0.65        # kg — 5-inch FPV airframe (design choice within the 0.5-0.9 kg class)
    drone_t2w: float = 2.5          # thrust-to-weight at full throttle (SOURCES: cf2x 2.25; FPV racers 2-4)
    drone_omega_max: float = 11.7   # rad/s body-rate command clamp = 670 deg/s (Betaflight default Actual-rates)
    drone_omega_hard: float = 34.9  # rad/s hard saturation = 1998 deg/s (Betaflight configurator cap)
    tau_omega: float = 0.030        # s body-rate first-order tracking lag (SOURCES: 0.03-0.05 FPV)
    tau_thrust: float = 0.030       # s collective-thrust first-order lag (Agilicious end-to-end ~35-40 ms)
    tau_motor_lo: float = 0.0375    # s domain-randomization range for the motor lag (Molchanov CF fit ..
    tau_motor_hi: float = 0.072     #   RotorPy fit) — a 2x legitimate-fit disagreement, randomize don't pick
    # DRAG — the single active model is QUADRATIC body drag (SOURCES aero: F=0.5*rho*Cd*A*|v|v), the
    # physically dominant term at CRUISE speed. STEP-0 finding: the ICRA22 lumped LINEAR K_v is a
    # near-hover small-signal fit; extrapolated to cruise it under-damps and gives a 56 m/s terminal
    # (turn radius > arena -> the drone can't turn to intercept). Quadratic caps the drone at a realistic
    # ~22 m/s. Do NOT stack both (SOURCES conflict #2 double-count warning): drag_lin stays 0 in the game
    # (kept only as the rotor-drag knob / GPD-parity path).
    drag_quad: float = 0.046        # 1/m MASS-NORMALIZED quadratic drag c2 = 0.5*rho*Cd*A/m. terminal
    #                                 v = sqrt(a_lat_max/c2) ~= 22 m/s; Cd*A = c2*2m/rho ~= 0.049 m^2
    #                                 (SOURCES aero: small-quad Cd*A in 0.01-0.06 m^2).
    drag_lin: float = 0.0           # 1/s linear rotor-drag (OFF in game; ICRA22 K_v/m ~0.39-0.54 used
    #                                 only in the gym-pybullet-drones parity test with GPD coefficients).
    drone_speed_max: float = 22.0   # m/s documented terminal (= sqrt(a_lat_max/drag_quad)); realistic 5-inch FPV.
    rotor_radius: float = 0.0635    # m (5-inch prop radius = 2.5 in) — ground-effect length scale
    ge_coef: float = 1.0            # Cheeseman-Bennett multiplier scale (augmentation convention: >=1, ->1 far)
    drone_radius: float = 0.12      # m collision/contact radius (prop-tip to prop-tip ~0.24 m diameter)
    drone_kill_radius: float = 2.5  # m kamikaze WARHEAD lethal radius (NOT bare-body contact). A kamikaze
    #                                 FPV drone detonates a warhead; lethal radius is metres (SOURCES G2:
    #                                 FAA/ASSURE KE severity + Kingery-Bulmash blast). STEP-0 finding: a
    #                                 0.6 m contact radius is un-interceptable — turn radius (~21 m) >> that,
    #                                 so a fast drone cannot turn tight enough to touch a juking target.
    # battery (SOURCES G3 grey-box P = c_d*Omega^3/eta; Level-A proxy P ~ p_hover*(thrust/mg)^1.5)
    batt_capacity_j: float = 9000.0 # J usable energy (design: ~1300 mAh 4S LiPo ~ 19 Wh ~ 68 kJ; toy-scaled
    #                                 down so endurance forces commitment within an episode)
    hover_power_w: float = 90.0     # W electrical hover power (design, 5-inch class ~80-120 W)

    # ================= wind: Dryden turbulence (MIL-F-8785C) + log shear =================
    wind_mean_lo: float = 0.0       # m/s per-env mean wind speed drawn in [lo, hi] (schedule pregen)
    wind_mean_hi: float = 8.0       # m/s (design: up to ~fresh breeze; drone v_max ~12 m/s stays controllable)
    wind_z0: float = 0.20           # m surface roughness length (SOURCES wind: open field ~0.03, trees ~0.5;
    #                                 0.2 = mixed low vegetation) — log-law u(z)=u_ref*ln(z/z0)/ln(z_ref/z0)
    wind_z_ref: float = 6.0         # m reference height for the mean-wind draw
    dryden_sigma_frac: float = 0.15 # turbulence intensity sigma_w/W (SOURCES: low-alt light turb ~0.1-0.2)
    dryden_L_w: float = 30.0        # m vertical turbulence length scale at low altitude (MIL-F-8785C band)
    dryden_L_uv: float = 60.0       # m horizontal turbulence length scales (u,v)

    # ================= terrain: procedural heightfield =================
    terrain_grid: int = 64          # G: heightfield resolution GxG (bilinear-sampled, analytic gradient)
    terrain_amp: float = 15.0       # m peak-to-trough terrain relief (design)
    arena_half: float = 60.0        # m arena half-extent in x and y (drones + enemies clamp to +/- this)
    ceiling: float = 45.0           # m z ceiling for drones above terrain base

    # ================= enemies: toy soldiers (social force) + toy tanks (unicycle) =================
    soldier_speed: float = 1.5      # m/s desired walking speed (Helbing v0=1.34; 1.5 design round number)
    soldier_speed_max: float = 3.0  # m/s running cap (Helbing panic; also the SFM velocity clamp)
    soldier_radius: float = 0.35    # m body radius (Helbing r_i ~ 0.3)
    soldier_tau: float = 0.5        # s SFM relaxation time (Helbing tau=0.5)
    sfm_A: float = 2000.0           # N social repulsion strength (Helbing A=2000)  [per unit mass below]
    sfm_B: float = 0.08             # m social repulsion range (Helbing B=0.08)
    sfm_mass: float = 80.0          # kg pedestrian mass (Helbing) — A/mass = accel scale
    tank_speed: float = 4.0         # m/s tank cruise (design; scaled-down tracked vehicle)
    tank_speed_max: float = 6.0     # m/s tank top speed
    tank_omega_max: float = 0.8     # rad/s tank yaw-rate cap (unicycle; slow heavy turn)
    tank_accel: float = 3.0         # m/s^2 tank longitudinal accel cap
    tank_radius: float = 1.2        # m tank body radius (also the box half-extent for collision)
    tobler_flat_speed_frac: float = 1.0   # Tobler W(0)=exp(-0.175)=0.8395 is folded into the factor (=1 at flat)

    # ================= anti-air fire (SOURCES aa-fire; tiered hybrid) =================
    aa_range: float = 35.0          # m engagement range (design; toy-scaled from small-arms effective range)
    aa_cooldown: float = 0.4        # s between shots per shooter (design: ~2.5 shots/s aimed fire)
    aa_muzzle_soldier: float = 300.0# m/s effective projectile speed for lead calc (toy-scaled from 948)
    aa_muzzle_tank: float = 500.0   # m/s tank autocannon (toy-scaled from 1100)
    aa_sigma_ang: float = 0.024     # rad/m angular dispersion sigma (STEP-0 calibrated -> ~45% nominal loss;
    #                                 hit on a small drone at engage range, matches the C-UAS reality anchor)
    aa_target_radius: float = 0.20  # m effective drone hit radius for P_hit (SOURCES: r in 1-exp(-r^2/2sigma^2))
    aa_maneuver_penalty: float = 0.5# s^2 scale on the sigma_maneuver^2 = 0.5*a_perp*t_f^2 term -> jinking evades

    # ================= contact (Hunt-Crossley penalty, drone<->drone) =================
    hc_stiffness: float = 800.0     # N/m^n contact stiffness k (design; soft toy contact, one Jacobi pass)
    hc_damping: float = 40.0        # contact damping lambda (Hunt-Crossley F = k*d^n + lambda*d^n*ddot)
    hc_exponent: float = 1.5        # n (Hertzian sphere contact n=1.5, Hunt-Crossley 1975)

    # ================= obs normalizers (must match train + deploy) =================
    engage_range: float = 40.0      # m THE operating-scale normalizer for all distance obs (NOT arena_half;
    #                                 monstro desertion-bug rule: normalize by the scale the agent operates at)
    obs_clamp: float = 2.0          # all obs features clamped to +/- this after normalization
    max_flight_ticks: int = 750     # safety cap = 15 s at 50 Hz (episode = 150 decisions * act_every)
    eps: float = 1e-6

    # ---- derived (not stored; exported for the Swift client's convenience) ----
    @property
    def drone_t_max(self) -> float:
        """Max collective thrust force [N] = T2W * m * g."""
        return self.drone_t2w * self.drone_mass * self.gravity

    @property
    def drone_accel_max(self) -> float:
        """Max upward acceleration magnitude [m/s^2] at full throttle (= (T2W-1)*g net of gravity is the
        climb accel; the raw thrust accel is T2W*g). Used by the gate for the tilt/interception envelope."""
        return self.drone_t2w * self.gravity

    @property
    def decision_dt(self) -> float:
        """Wall-clock seconds per policy decision = act_every * dt."""
        return self.act_every * self.dt

    def to_json(self, path):
        d = asdict(self)
        d["drone_t_max"] = self.drone_t_max            # derived, exported
        d["drone_accel_max"] = self.drone_accel_max
        d["decision_dt"] = self.decision_dt
        json.dump(d, open(path, "w"), indent=2)

    @classmethod
    def from_json(cls, path):
        d = json.load(open(path))
        known = {f.name for f in fields(cls)}
        return cls(**{k: v for k, v in d.items() if k in known})
