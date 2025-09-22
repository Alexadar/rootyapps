# Monster Shooter Swift Port

A macOS Swift/SpriteKit port of the original Flash Monster Shooter game.

## What's Implemented

### Core Game Mechanics ✅
- **WASD Movement**: Smooth character movement with proper velocity normalization
- **Mouse Aiming**: Player character rotates to face mouse cursor
- **Mouse Shooting**: Click to shoot bullets toward mouse position
- **Custom Crosshair**: Target cursor replaces system cursor during gameplay
- **Monster Spawning**: Enemies spawn from screen edges every 2 seconds
- **Collision Detection**: Physics-based collision between bullets and monsters
- **Monster AI**: Monsters chase the player using basic pathfinding

### Assets ✅
- **Map Background**: Uses original `map_0.png` from Flash game as background
- **Player Sprite**: Attempts to load `exoskeletons_0.png` spritesheet (fallback to green rectangle)
- **Bullet Graphics**: Attempts to load from `weapons.png` spritesheet (fallback to yellow dots)
- **Monster Graphics**: Red rectangles (placeholder for future sprite implementation)

### Technical Implementation ✅
- **SpriteKit Framework**: Hardware-accelerated 2D graphics
- **Physics System**: Proper collision detection and response
- **Memory Management**: Automatic cleanup of off-screen bullets and distant monsters
- **Input Handling**: Native macOS keyboard and mouse events
- **Modular Architecture**: Separate Monster class for easy extension

## Controls

- **WASD**: Move player character
- **Mouse**: Aim weapon (crosshair follows mouse)
- **Mouse Click**: Shoot toward crosshair
- **Cursor**: Custom white crosshair with red center dot (system cursor hidden during gameplay)

## Project Structure

```
monstro_client/
├── monstro_clientApp.swift    # Main SwiftUI app entry point
├── ContentView.swift          # SwiftUI wrapper for SpriteKit scene
├── GameScene.swift           # Main game logic and rendering
├── TextureAtlas.swift        # Sprite atlas parsing for Flash textures
└── Resources/                # Game assets from original Flash game
    ├── map_background.png    # Level background (from map_0.png)
    ├── exoskeletons_0.png   # Player sprites spritesheet
    ├── exoskeletons_0.xml   # Sprite atlas coordinates
    └── weapons.png          # Weapon/bullet sprites
```

## Game Features

### Implemented Features
1. **Real-time Action**: Smooth 60 FPS gameplay
2. **Physics-based Combat**: Realistic bullet trajectory and collision
3. **Dynamic Enemy Spawning**: Monsters appear from random screen edges
4. **Boundary Collision**: Player stays within screen bounds
5. **Resource Management**: Automatic cleanup prevents memory leaks

### Potential Future Enhancements
1. **Sprite Animation**: Implement walking/shooting animations from spritesheets
2. **Multiple Monster Types**: Add different enemy variants with unique behaviors
3. **Power-ups**: Implement boosters from original game
4. **Sound Effects**: Add audio from original Flash assets
5. **Score System**: Track kills, implement progression
6. **Multiple Maps**: Port additional backgrounds from original game
7. **Weapon Variety**: Implement different weapon types
8. **Health System**: Add player health and damage mechanics

## Technical Notes

- **Performance**: Optimized for macOS with hardware acceleration
- **Resolution**: Scales to window size (currently 1024x768 default)
- **Asset Loading**: Graceful fallback if original textures can't be loaded
- **Physics Categories**: Properly categorized collision detection (player, monster, bullet)
- **Delta Time**: Frame-rate independent movement calculations

## Build Requirements

- macOS 26.0+
- Xcode 16+
- Swift 5.0+

## Known Limitations

1. Player sprite shows entire spritesheet instead of individual frames
2. Monsters use placeholder graphics instead of original sprites
3. No sound effects or music
4. Single map only
5. Basic AI (monsters only chase player directly)

This port successfully demonstrates the core gameplay loop of the original Monster Shooter game with modern Swift/SpriteKit technology, providing a solid foundation for further development.