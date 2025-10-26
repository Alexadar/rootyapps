# Monster Shooter Swift

Swift/SpriteKit port of Flash Monster Shooter. Cross-platform: macOS, iOS, iPadOS, visionOS.

## Status

**Core**: Wave-based spawning, 12000x12000 map, 4500x4500 spawn box, smooth camera, modular architecture
**Gameplay**: WASD/joystick movement, mouse/touch aim, pistol (20-round mag, auto-reload), collision physics
**UI**: Arcade menu backgrounds, HUD (time/health/ammo/percentage), settings popup (BGM/SFX toggles)
**Audio**: Random BGM (menu_1/2, fight_1/2), SFX (pistol, reload, walker), persistent settings (UserDefaults)
**Monsters**: Berserker (walk/dying animations, chase AI)

## Controls

**Desktop**: WASD move, mouse aim/shoot, Q/E rotation debug, R toggle debug
**Mobile**: Left 25% joystick, right 25% aim/shoot

## Structure

```
monstro_client/
├── Core/              # GameScene extensions (8 files)
├── UI/                # GameHUD, UIStyleGuide, touch controls
├── Input/             # KeyboardMouseInput, TouchInput
├── Entities/          # Player, Bullet, Monster, Weapon, GameLevel
├── Monsters/          # Berserker
├── Audio/             # AudioManager (BGM/SFX)
├── Settings/          # SettingsManager (UserDefaults)
├── Assets/Audio/      # BGM/*.mp3, SFX/*.wav
└── Resources/         # Sprites, textures, animations
```

## Constants (GameConstants.swift)

Spawn box: 4500x4500, Camera smooth: 0.1, Player: 300, Monster: 100, Bullet: 800
HUD: 20px margin, 60px top, 40px row spacing, 32px height, z-pos 1000

## Tech Notes

- Centered anchor (0,0 = center, use -size/2 to +size/2)
- Map (level bounds) ≠ Spawn box (monster spawn) ≠ Viewport (screen)
- Tiled ground (576 sprites, no scaling)
- Numeric frame sorting (not lexicographic)
- Camera clamped to mapMin + viewport/2, mapMax - viewport/2
- Resources in app bundle root (no subdirectories)
- Random selection via @State (runtime, not compile-time)

## Build

macOS 26.0+, Xcode 16+, Swift 5.0+, SwiftUI/SpriteKit/AVFoundation

## Known Issues

Single monster type, no player damage system, no score tracking, test level only
