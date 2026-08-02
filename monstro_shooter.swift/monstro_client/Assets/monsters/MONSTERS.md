# Monster Animation Assets

This directory contains animation frames for all monster types in Monster Shooter.

## Directory Structure

```
Monsters/
├── berserker/          # Monster Type ID: 2 (Berserker/Beetle1)
│   ├── walk/          # Walking animation frames
│   └── dying/         # Death animation frames
├── walker/            # Monster Type ID: 23 (Basic Walker)
│   ├── walk/
│   └── dying/
├── bird/              # Monster Type ID: 3 (Flying Beetle)
│   ├── walk/          # Actually "flying" animation
│   └── dying/
├── bird2/             # Monster Type ID: 4 (Flying Beetle variant)
│   ├── walk/
│   └── dying/
├── bug/               # Monster Type ID: 1 (Bug/Beetle base)
│   ├── walk/
│   └── dying/
└── bug2/              # Monster Type ID: 5 (Bug variant)
    ├── walk/
    └── dying/
```

## Animation Frame Naming Convention

All frames must follow this naming pattern:

### Walk/Movement Animation
```
walk_1.png
walk_2.png
walk_3.png
...
walk_N.png
```

### Dying Animation
```
dying_1.png
dying_2.png
dying_3.png
...
dying_N.png
```

## Frame Requirements

- **Format**: PNG with transparency
- **Naming**: Sequential numbers (1, 2, 3...), not zero-padded
- **Size**: Varies by monster (see specifications below)
- **Pivot**: Center anchor point (0.5, 0.5)

## Monster Specifications

### Berserker (ID: 2)
- **Box Size**: 60x60 pixels
- **Speed**: 94 units
- **Health**: 10 HP
- **Damage**: 4 HP
- **Type**: Melee ground unit
- **Frame Rate**: 0.08s per frame
- **Status**: ✅ Frames included (29 walk, 31 dying)

### Walker (ID: 23)
- **Box Size**: 60x60 pixels
- **Speed**: 60 units (slower than Berserker)
- **Health**: 10 HP
- **Damage**: 4 HP
- **Type**: Heavy ground unit
- **Frame Rate**: 0.08s per frame
- **Status**: ⏳ Awaiting frames

### Bird (ID: 3)
- **Box Size**: 50x50 pixels
- **Speed**: 210 units (fast flyer)
- **Health**: 6 HP
- **Damage**: 2 HP
- **Type**: Flying unit
- **Frame Rate**: 0.08s per frame
- **Death Sound**: monster_avia_1.wav, monster_avia_2.wav
- **Status**: ⏳ Awaiting frames

### Bird2 (ID: 4)
- **Box Size**: 50x50 pixels
- **Speed**: 176 units
- **Health**: 8 HP
- **Damage**: 3 HP
- **Type**: Flying unit (tougher variant)
- **Frame Rate**: 0.08s per frame
- **Death Sound**: monster_avia_1.wav, monster_avia_2.wav
- **Status**: ⏳ Awaiting frames

### Bug (ID: 1)
- **Box Size**: 40x40 pixels
- **Speed**: 200 units
- **Health**: 4 HP
- **Damage**: 1 HP
- **Type**: Fast ground unit
- **Frame Rate**: 0.08s per frame
- **Death Sound**: monster_bug_1.wav, monster_bug_2.wav
- **Status**: ⏳ Awaiting frames

### Bug2 (ID: 5)
- **Box Size**: 40x40 pixels
- **Speed**: 158 units
- **Health**: 6 HP
- **Damage**: 2 HP
- **Type**: Ground unit (tougher bug)
- **Frame Rate**: 0.08s per frame
- **Death Sound**: monster_bug_1.wav, monster_bug_2.wav
- **Status**: ⏳ Awaiting frames

## Animation Loading

The game uses `Monster.loadTextures(fromDirectory:)` to load frames:

1. Searches for all PNG files in the specified directory
2. Extracts numeric frame numbers from filenames
3. Sorts frames numerically (not alphabetically)
4. Creates SKTexture array for animation

## File Placement

Place your animation frames in the corresponding folders:

- `berserker/walk/` - Berserker walking frames
- `berserker/dying/` - Berserker death animation
- `walker/walk/` - Walker walking frames
- `walker/dying/` - Walker death animation
- `bird/walk/` - Bird flying frames
- `bird/dying/` - Bird death animation
- `bird2/walk/` - Bird2 flying frames
- `bird2/dying/` - Bird2 death animation
- `bug/walk/` - Bug walking frames
- `bug/dying/` - Bug death animation
- `bug2/walk/` - Bug2 walking frames
- `bug2/dying/` - Bug2 death animation

## Notes

- Empty folders contain `.gitkeep` files to preserve folder structure in git
- Remove `.gitkeep` files after adding actual animation frames
- Frame count can vary per monster (some may need more frames for smooth animation)
- All monsters use the same frame rate by default (0.08s), but this can be adjusted per monster type
- Death animations use 0.06s frame rate for faster playback

## Swift Integration

Monster classes automatically reference these directories:

```swift
class Berserker: Monster {
    override init() {
        super.init()
        walkAnimationDirectory = "monsters/berserker/walk"
        dyingAnimationDirectory = "monsters/berserker/dying"
    }
}
```

The path is relative to the app bundle's Resources folder.

## Adding New Monsters

To add a new monster type:

1. Create new subfolder under `Monsters/`
2. Create `walk/` and `dying/` subfolders
3. Add animation frames following naming convention
4. Create Swift class inheriting from `Monster`
5. Set `walkAnimationDirectory` and `dyingAnimationDirectory` paths
6. Update this README with specifications

---

**Last Updated**: October 27, 2025
**Berserker Frames**: Included
**Other Monsters**: Awaiting asset placement
