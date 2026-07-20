"""common — the SHARED torchsim engine, scenario-agnostic. Everything here is reused by BOTH the
`arena` combat game and the `cherrypick` harvesting demo (and any future scenario):

  common.oracles     REAL, unit-tested, loop-free physics/geometry primitives (rotation, collide3,
                     quadrotor, terrain, wind, aero, ...). A scenario COMPOSES these; adds no physics.
  common.navfield    the quantized 3D geodesic route field (Godunov Eikonal solver + flow + sampler).
  common.controller  the differentiable velocity-tracking geometric flight controller (route -> CTBR).
  common.render_core the GPU rasterizer primitives (projection, sprites, lines, z-buffer, cameras).

Scenario packages (arena/, cherrypick/) sit next to this one under torchsim/ and import it as
`from common.oracles import ...`, `from common import navfield`, etc. (a small path bootstrap in each
entry script / test conftest puts the torchsim root on sys.path).
"""
