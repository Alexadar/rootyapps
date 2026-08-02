#!/usr/bin/env python3
import json
import shutil
from pathlib import Path

# Paths
project_root = Path(__file__).parent.parent
frames_src = project_root / "tmp" / "frames_converted"
monsters_dst = project_root / "monstro_client" / "Assets.xcassets" / "Monsters"

# Monster name mapping (folder name -> clean name)
monster_mapping = {
    "1_bug": "Bug",
    "2_berserker": "Berserker",
    "3_bird": "Bird",
    "4_bug2": "Bug2",
    "5_bird2": "Bird2",
    "6_bug3": "Bug3",
    "7_berserker2": "Berserker2",
    "8_bird3": "Bird3",
    "9_walker3": "Walker3",
    "10_bug4": "Bug4",
    "11_bird4": "Bird4",
    "12_walker4": "Walker4",
    "13_bug5": "Bug5",
    "14_bird5": "Bird5",
    "15_walker": "Walker",
    "16_berserker4": "Berserker4",
    "17_bug6": "Bug6",
    "18_walker6": "Walker6",
    "22_walker2": "Walker2",
    "23_berserker6": "Berserker6",
    "24_bird6": "Bird6",
}

# JSON templates
imageset_contents = {
    "images": [
        {"idiom": "universal", "scale": "1x"},
        {"idiom": "universal", "scale": "2x"},
        {"idiom": "universal", "scale": "3x"}
    ],
    "info": {"author": "xcode", "version": 1}
}

spriteatlas_contents = {
    "info": {"author": "xcode", "version": 1}
}

monster_contents = {
    "info": {"author": "xcode", "version": 1},
    "properties": {"provides-namespace": True}
}

# Remove existing monster folders (except Contents.json)
for item in monsters_dst.iterdir():
    if item.is_dir():
        shutil.rmtree(item)

# Process each monster
for src_folder, monster_name in monster_mapping.items():
    src_path = frames_src / src_folder
    if not src_path.exists():
        print(f"Warning: {src_folder} not found, skipping")
        continue

    # Create monster folder
    monster_dir = monsters_dst / monster_name
    monster_dir.mkdir(exist_ok=True)

    # Write monster Contents.json
    with open(monster_dir / "Contents.json", "w") as f:
        json.dump(monster_contents, f, indent=2)

    # Process dying and walk animations
    for anim_type in ["dying", "walk"]:
        anim_src = src_path / anim_type
        if not anim_src.exists():
            print(f"Warning: {src_folder}/{anim_type} not found, skipping")
            continue

        # Create spriteatlas folder
        spriteatlas_name = anim_type.capitalize() + ".spriteatlas"
        spriteatlas_dir = monster_dir / spriteatlas_name
        spriteatlas_dir.mkdir(exist_ok=True)

        # Write spriteatlas Contents.json
        with open(spriteatlas_dir / "Contents.json", "w") as f:
            json.dump(spriteatlas_contents, f, indent=2)

        # Process each frame
        for frame_file in sorted(anim_src.glob("*.png")):
            frame_name = frame_file.stem  # e.g., "dying_01"

            # Create imageset folder
            imageset_dir = spriteatlas_dir / f"{frame_name}.imageset"
            imageset_dir.mkdir(exist_ok=True)

            # Copy frame
            shutil.copy(frame_file, imageset_dir / frame_file.name)

            # Write imageset Contents.json with filename reference
            imageset_json = imageset_contents.copy()
            imageset_json["images"] = [
                {"filename": frame_file.name, "idiom": "universal", "scale": "1x"},
                {"idiom": "universal", "scale": "2x"},
                {"idiom": "universal", "scale": "3x"}
            ]
            with open(imageset_dir / "Contents.json", "w") as f:
                json.dump(imageset_json, f, indent=2)

    print(f"Created {monster_name}")

print("\nFrame copy complete")
