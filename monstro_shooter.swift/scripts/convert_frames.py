#!/usr/bin/env python3
import shutil
from pathlib import Path

# Paths
project_root = Path(__file__).parent.parent
frames_src = project_root / "tmp" / "frames"
frames_dst = project_root / "tmp" / "frames_converted"

# Remove frames_converted if exists
if frames_dst.exists():
    shutil.rmtree(frames_dst)

# Copy frames to frames_converted
shutil.copytree(frames_src, frames_dst)

# Process each monster subfolder
for monster_dir in frames_dst.iterdir():
    if not monster_dir.is_dir():
        continue

    # Process dying and walk subdirectories
    for anim_dir in monster_dir.iterdir():
        if not anim_dir.is_dir():
            continue

        anim_type = anim_dir.name  # "dying" or "walk"

        # Rename files: n.png -> dying_nn.png or walk_nn.png (zero-padded)
        for file in anim_dir.iterdir():
            if not file.is_file() or file.suffix != '.png':
                continue

            frame_num = int(file.stem)
            new_name = f"{anim_type}_{frame_num:02d}.png"
            file.rename(anim_dir / new_name)

print("Frame conversion complete")
