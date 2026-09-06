"""pytest path bootstrap for the arena suite. Placed inside the tests/ dir (== pytest rootdir, next to
pytest.ini) so pytest auto-loads it before collection. Puts BOTH arena/ (sibling modules under test:
env_drone, schedule_drone, world_config_drone, ...) AND the torchsim root (the shared `common` package)
on sys.path, so the tests resolve regardless of the cwd pytest is invoked from."""
import os
import sys

_here = os.path.dirname(os.path.abspath(__file__))   # arena/tests
_arena = os.path.dirname(_here)                       # arena
_root = os.path.dirname(_arena)                       # torchsim  (holds the `common` package)
for _p in (_arena, _root):
    if _p not in sys.path:
        sys.path.insert(0, _p)
