"""Load the SAME game data files the Swift engine uses (mirror of Configs.swift):
maps from monstro_client/Resources/MapConfigs/*.json, units from Assets/configs/**/*.yaml."""
import os, json, glob, yaml

DEFAULT_CLIENT = os.path.join(os.path.dirname(__file__), "..", "monstro_client")


def _load_yaml_dir(d):
    out = []
    for f in glob.glob(os.path.join(d, "*.yaml")):
        with open(f) as fh:
            y = yaml.safe_load(fh)
            if isinstance(y, dict):
                out.append(y)
    return out


def load_monsters(root=DEFAULT_CLIENT):
    res = {}
    for y in _load_yaml_dir(os.path.join(root, "Assets/configs/monsters")):
        if "monsterTypeID" in y and "speed" in y:
            res[int(y["monsterTypeID"])] = y
    return res


def load_weapons(root=DEFAULT_CLIENT):
    res = {}
    for y in _load_yaml_dir(os.path.join(root, "Assets/configs/weapons")):
        if "id" in y and "shotDelay" in y:
            res[int(y["id"])] = y
    return res


def load_exoskeletons(root=DEFAULT_CLIENT):
    res = {}
    for y in _load_yaml_dir(os.path.join(root, "Assets/configs/exoskeletons")):
        if "id" in y and "defence" in y:
            res[int(y["id"])] = y
    return res


def load_map(path):
    with open(path) as fh:
        return json.load(fh)


def sim_level(mapcfg):
    """Mirror of convertMapConfigToLevel: each spawn wave with count>0 spawns from ALL available types."""
    all_types = [t for p in mapcfg.get("monsterTypes", []) for t in p["monsterTypeIds"]]
    waves = [(int(w["startTime"]), int(w["count"]), all_types)
             for w in mapcfg.get("monsterSpawnWaves", []) if int(w["count"]) > 0 and all_types]
    name = (mapcfg.get("defaultNameLocalizations") or {}).get("ru-ru") \
        or (mapcfg.get("defaultNameLocalizations") or {}).get("en-us") or f"map {mapcfg.get('id')}"
    return {
        "id": int(mapcfg.get("id", 0)),
        "name": name,
        "duration": float(mapcfg.get("landingDuration", 60)),
        "waves": waves,
        "expected_total": sum(c for _, c, _ in waves),
    }


class GameData:
    def __init__(self, root=DEFAULT_CLIENT):
        self.monsters = load_monsters(root)
        self.weapons = load_weapons(root)
        self.exoskeletons = load_exoskeletons(root)
