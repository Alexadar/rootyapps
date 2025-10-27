# Monster Shooter Swift

Swift/SpriteKit port of Flash Monster Shooter. Cross-platform: macOS, iOS, iPadOS, visionOS.

## Status

**Core**: Wave-based spawning, 12000x12000 map, 4500x4500 spawn box, smooth camera, modular architecture
**Gameplay**: WASD/joystick movement, mouse/touch aim, pistol (20-round mag, auto-reload), collision physics, player damage system
**UI**: Arcade menu backgrounds, HUD (time/health/ammo/kills), settings popup (BGM/SFX toggles), game over screen with Try Again/Menu buttons
**Audio**: Random BGM with auto-cycling (menu_1/2, fight_1/2), SFX (pistol, reload, walker), persistent settings (UserDefaults)
**Monsters**: 6 types (Bug, Bug2, Bird, Bird2, Walker, Berserker) with walk/dying animations, chase AI, configurable stats, death sounds

## Controls

**Desktop**: WASD move, mouse aim/shoot, Q/E rotation debug, R toggle debug
**Mobile**: Left 25% joystick, right 25% aim/shoot

## Structure

```plaintext
monstro_client/
├── Core/              # GameScene extensions (8 files), GameConstants, GameTypes
├── Rendering/         # GameRenderer, WorldCamera, HUDCamera, GameWorld, TextureAtlas
├── UI/                # UIStyleGuide, StyledButton, GameHUD, GameOverUI
├── Input/             # KeyboardMouseInput, TouchInput
├── Entities/          # Player, Bullet, Monster, Weapon, WeaponConfig, GameLevel, MapConfig
├── Monsters/          # Berserker, Walker, Bug, Bug2, Bird, Bird2
├── Physics/           # GameScene+Physics (collision handling)
├── Audio/             # AudioManager (BGM/SFX with auto-cycling)
├── Settings/          # SettingsManager (UserDefaults)
├── Assets/Audio/      # BGM/*.mp3, SFX/*.wav
└── Resources/
    ├── MapConfigs/    # 250 map JSON configs + monster_types.json + all_maps.json
    └── Sprites/       # Textures, animations
```

## Rendering Architecture

**Hierarchy**: `renderer.camera.contains(hud), renderer.world.contains(gameplay)`

- **GameRenderer**: Master renderer managing all rendering layers
- **WorldCamera**: Follows player with smooth interpolation, bounded by map
- **HUDCamera**: Isolated UI layer that follows world camera
- **GameWorld**: Contains all gameplay elements (map, player, monsters, bullets)

**Separation**: UI (HUD) and game world are on separate layers with independent cameras

## Constants (GameConstants.swift)

Spawn box: 4500x4500, Camera smooth: 0.1, Player: 300, Monster: 100, Bullet: 800
HUD: 20px margin, 60px top, 40px row spacing, 32px height, z-pos 1000

## Map System

**Config Format**: JSON files defining wave-based gameplay
- **250 maps** imported from SQL database (IDs: 1, 14-37, 1029-1273)
- **Wave system**: Time-triggered spawn events with monster counts
- **Progressive difficulty**: Monster types unlock at specific timestamps
- **Duration**: 40-600 seconds per map
- **Max victims**: Per-monster-type kill limits
- **Localization**: Russian (ru-ru) and English (en-us) names/descriptions
- **Encoding**: Imported from SQL dump with windows-1251 → UTF-8 conversion

**Example** (map_0014.json):
```plaintext
Name: "карта 5" (ru-ru)
Duration: 45s, Resource: map_1
Waves: t=1s(5), t=11s(15), t=31s(15)
Types: t=30s → [Bug], t=30s → [Bug, Walker]
```

**MapConfig.swift**: Codable struct with `load(filename:)` and `loadAll()` helpers

## Tech Notes

- Centered anchor (0,0 = center, use -size/2 to +size/2)
- Map (level bounds) ≠ Spawn box (monster spawn) ≠ Viewport (screen)
- Tiled ground (576 sprites, no scaling)
- Numeric frame sorting (not lexicographic)
- Camera hierarchy: WorldCamera → HUDCamera (isolated layers)
- All gameplay elements added to GameWorld layer
- HUD follows camera position, maintains viewport coords
- Resources in app bundle root (no subdirectories)
- Random selection via @State (runtime, not compile-time)

## Build

macOS 26.0+, Xcode 16+, Swift 5.0+, SwiftUI/SpriteKit/AVFoundation

## Recent Updates

- **Map import**: Imported 250 maps from SQL database with proper windows-1251 → UTF-8 encoding conversion
- **Audio refactor**: Abstracted AudioManager - sound filenames now stored in Monster subclasses, not hardcoded
- **Monster system**: Added 5 new monster types (Bug, Bug2, Bird, Bird2, Walker) with unique stats, animations, death sounds
- **Architecture**: Monster base class handles animations/sounds generically, subclasses configure via properties
- **Type safety**: Fixed CGFloat/Int conversions for damage calculations
- **macOS compilation**: All compilation errors fixed, builds successfully on macOS

## Monster Types Database

**monster_types.json**: 24 monster definitions with stats
- ID 1-5: Bug, Walker, Bird, Bug2, Bird2 (implemented)
- ID 6-24: Additional types (not yet implemented)
- Properties: speed, health, damage, bodyRadius, experienceReward, moneyReward
- Resource mapping: resourceFile + resourceName for sprite loading

## Known Issues

250 maps parsed but not integrated into gameplay, weapon switching not implemented, only 6/24 monster types implemented
