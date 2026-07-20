"""Oracle package — REAL, vectorized, unit-tested physics for the droneswarm sim. Every formula
traces to oracles/SOURCES.md (cited standards / papers / reference sims). NO invented physics, NO
python loops in any oracle. The worldsim (env_drone.py) COMPOSES these; it adds no physics of its own.
"""
from . import rotation, collide3, contact, aero, aa_fire, terrain, wind, quadrotor, ground

__all__ = ["rotation", "collide3", "contact", "aero", "aa_fire", "terrain", "wind", "quadrotor", "ground"]
