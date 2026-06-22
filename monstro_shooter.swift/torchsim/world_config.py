"""WorldConfig — every global physics constant in ONE place (the "model+world setup").

torchsim and the Metal game read the SAME config (exported to JSON), so constants can never drift —
that drift is exactly what broke the old Metal demo. Per-type monster / per-weapon / per-exo stats
still come from the YAML configs; this holds the globals only. Defaults = the canonical values
(RULES.md "Proposed Metal"); change any field per setup (e.g. turn_rate is a knob now, not a literal).
"""
from dataclasses import dataclass, asdict, fields
import json


@dataclass
class WorldConfig:
    # --- core kinematics ---
    dt: float = 1.0 / 30.0          # fixed sim timestep (render lerps to 60/120; sim stays 1/30)
    player_speed: float = 300.0
    player_half: float = 30.0       # sprite half-size (clamp)
    player_radius: float = 30.0     # hitbox radius
    map_half: float = 6000.0        # default arena half (per-map override via schedule arena_half)
    turn_rate: float = 34.0         # arc-steering turn rate
    buffer: float = 5.0             # contact-range slack
    bullet_radius: float = 6.0
    damage_interval: float = 1.0    # seconds between periodic contact-damage pulses
    # --- OLD-SpriteKit combat rules (canonical) ---
    diagonal_factor: float = 0.75   # move-speed mult when both axes active
    defense_min_floor: float = 0.4  # CombatMath minimum applied damage
    # --- obs normalizers (must match between train + deploy) ---
    player_max_hp: float = 100.0
    dist_norm: float = 1000.0
    monster_speed_norm: float = 300.0
    monster_count_norm: float = 64.0
    bullet_norm: float = 1000.0
    eps: float = 1e-6

    def to_json(self, path):
        json.dump(asdict(self), open(path, "w"), indent=2)

    @classmethod
    def from_json(cls, path):
        d = json.load(open(path))
        known = {f.name for f in fields(cls)}
        return cls(**{k: v for k, v in d.items() if k in known})
