"""Parity bridge: export everything the Swift port needs to reproduce the torch sim 1:1, plus the
torch REFERENCE trajectories to diff against.

Writes to parity/ (gitignored):
  world.json          - the shared WorldConfig (constants)
  sched_<gid>.json    - per-game baked schedule (N=1): spawn_tick/offset/hp0/speed/boxW/dmg/direct +
                        weapon/exo scalars + arena_half. No MonstroSim dep needed Swift-side.
  torch_<gid>.json    - torch per-tick positions (player/monsters/bullets) = the parity reference
  index.json          - game list

Games = the 3 held-out eval maps x 3 seeds (same base_seed=1000+sd*7919 as run_eval) = 9.
Both player and enemy are driven by the trained models (deterministic) so the trajectory is fixed.
"""
import glob, json, os
import yaml
import torch
import data, schedule
import policy_torch as P
from world_config import WorldConfig
from env_torch import EnvTorch

OUT = "parity"
DATASET = "datasets/surround"
BULLETS = 24
SEEDS = 3
PLAYER = "../MonstroSim/models/player.json"
ENEMY = "../MonstroSim/models/monster.json"


def main():
    os.makedirs(OUT, exist_ok=True)
    cfg = WorldConfig()
    cfg.to_json(os.path.join(OUT, "world.json"))

    # monster typeID -> sprite folder (= yaml basename, which matches Assets.xcassets/Monsters/<folder>)
    type_folder = {}
    for f in glob.glob("../monstro_client/Assets/configs/monsters/*.yaml"):
        y = yaml.safe_load(open(f))
        if isinstance(y, dict) and "monsterTypeID" in y:
            type_folder[int(y["monsterTypeID"])] = os.path.basename(f)[:-5]
    json.dump(dict(
        assets_root="../../monstro_client/Assets.xcassets",
        resources_root="../../monstro_client/Resources",
        type_folder={str(k): v for k, v in type_folder.items()},
        walk_subpath="Walk.spriteatlas",
        player_image="exoskeletons_0.png",         # the real player = exoskeleton atlas frame
        player_crop=[1, 1, 62, 57],                # _0_exoskeleton0000 sub-rect (from the .xml)
        # bullet = yellow quad (the game's bullet_pistol fallback)
    ), open(f"{OUT}/sprites.json", "w"))

    gd = data.GameData("../monstro_client")
    weapon = gd.weapons.get(1) or next(iter(gd.weapons.values()))
    exo = gd.exoskeletons.get(1) or next(iter(gd.exoskeletons.values()))
    player, _ = P.from_json(PLAYER)
    enemy, _ = P.from_json(ENEMY)
    pf = lambda o: P.apply_mlp(player, o)
    ef = lambda o: P.apply_enemy(enemy, o)

    maps = sorted(glob.glob(os.path.join(DATASET, "eval", "*.json")))[:3]
    games = []
    for mi, mp in enumerate(maps):
        level = data.sim_level(data.load_map(mp))
        total = max(level["expected_total"], 1)
        ah = float(level["arena_half"])
        ticks = int(level["duration"] * 30)
        for sd in range(SEEDS):
            gid = f"g{mi}_{sd}"
            sched = schedule.build(level, gd.monsters, base_seed=1000 + sd * 7919, n_envs=1, cap=min(total, 1024))
            env = EnvTorch(sched, weapon, exo, device="cpu", bullets=BULLETS, cfg=cfg)
            M = env.M
            json.dump(dict(
                name=os.path.basename(mp).replace(".json", ""), gid=gid, M=M, B=BULLETS, ticks=ticks,
                arena_half=ah,
                spawn_tick=sched["spawn_tick"][0].tolist(), offset=sched["offset"][0].tolist(),
                hp0=sched["hp0"][0].tolist(), speed=sched["speed"][0].tolist(),
                boxW=sched["boxW"][0].tolist(), dmg=sched["dmg"][0].tolist(), direct=sched["direct"][0].tolist(),
                type=sched["type"][0].tolist(),
                bullet_speed=env.bullet_speed, bullet_damage=env.bullet_damage, bullet_range=env.bullet_range,
                fire_interval=env.fire_interval, contact_interval=env.contact_interval, defense=env.defense,
                bullets_per_shot=env.bullets_per_shot, penetration=env.penetration, max_dev=env.max_dev,
                mag_size=env.mag_size, reload_ticks=env.reload_ticks, exo_speed=env.exo_speed,
            ), open(f"{OUT}/sched_{gid}.json", "w"))

            s = env.reset(1)
            frames = []
            with torch.no_grad():
                for t in range(1, ticks + 1):
                    s, _, _ = env.step(s, t, pf, ef)
                    al = ((s["mon_act"][0, 0] > 0.5) & (s["mon_hp"][0, 0] > 0)).int().tolist()
                    ba = (s["bul_alive"][0, 0] > 0.5).int().tolist()
                    frames.append(dict(
                        t=t, player=s["player_pos"][0, 0].tolist(),
                        mon_alive=al, mon_pos=s["mon_pos"][0, 0].reshape(-1).tolist(),
                        bul_alive=ba, bul_pos=s["bul_pos"][0, 0].reshape(-1).tolist(),
                        kills=int(s["kills"][0, 0]), hp=round(float(s["player_hp"][0, 0]), 4)))
                    if float(s["player_hp"][0, 0]) <= 0 or int(s["kills"][0, 0]) >= M:
                        break
            json.dump(frames, open(f"{OUT}/torch_{gid}.json", "w"))
            games.append(gid)
            print(f"  {gid} ({os.path.basename(mp)}): M={M} ticks={len(frames)} kills={frames[-1]['kills']} hp={frames[-1]['hp']:.0f}")
    json.dump(dict(games=games, bullets=BULLETS), open(f"{OUT}/index.json", "w"))
    print(f"exported {len(games)} games + world.json -> {OUT}/")


if __name__ == "__main__":
    main()
