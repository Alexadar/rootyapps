"""SensorChannel — Layer 2 of the three-layer decoupling (WorldSim / SensorChannel / Control).

The env's `_core` (Layer 1) owns the GROUND TRUTH and exposes nothing to the brain directly. The
brain (Layer 3, policy_attn) consumes only the PERCEIVED PICTURE this module produces — the "shared
3D picture" that dumb machines report up to the one centralized controller. Keeping this a hard,
named seam means future realism (comms lag, jamming, sensor noise, occlusion, a learned detector)
plugs in HERE without touching the physics or the policy.

v1 = IDENTITY (perfect picture). The degradation hooks below are all OFF by default (froggo's
"seam defaults to identity, enable later" pattern) and every one of them is vectorized + deterministic
(pregenerated schedules, no runtime RNG) so batch==singles bit-identity is preserved when enabled:

  * LAG      — the brain acts on a delayed snapshot. Implemented as a compact-picture ring buffer in
               the env's game_loop (NOT in the compiled _core), so it never complicates the physics.
  * JAMMING  — per-env per-tick per-drone dropout mask (pregenerated jam[N,T,D]); a jammed drone goes
               dark (its own pose uncertain, cannot report detections).
  * OCCLUSION— an enemy is in the picture only if some alive drone has line-of-sight (the SDF
               segment test collide3.segment_clearance reused as line-of-SIGHT).

The picture is a COMPACT projection of state (external kinematics only — pose/velocity/alive, NOT the
drone's internal quaternion-omega-energy), which is (a) what any sensor could actually observe and
(b) small enough to buffer cheaply for lag.
"""


def perceive(state, cfg=None, jam=None, lag_buffer=None):
    """state (the full ground-truth dict) -> perceived picture (the compact external kinematics the
    brain is allowed to see). v1 identity: the picture IS the true kinematics. Degradation args are
    accepted but unused at v1 (documented seams).

    picture keys: d_pos, d_vel, d_quat, d_alive, d_act (drone external state);
                  e_pos, e_vel, e_head, e_alive, e_cd (enemy external state)."""
    return dict(
        d_pos=state["d_pos"], d_vel=state["d_vel"], d_quat=state["d_quat"],
        d_omega=state["d_omega"], d_energy=state["d_energy"],        # proprioception (own IMU/battery)
        d_alive=state["d_alive"], d_act=state["d_act"],
        e_pos=state["e_pos"], e_vel=state["e_vel"], e_head=state["e_head"],
        e_alive=state["e_alive"], e_cd=state["e_cd"],
    )
