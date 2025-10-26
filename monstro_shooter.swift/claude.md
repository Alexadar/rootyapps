# Claude Dev Log - Monster Shooter Swift

**Communication Style**: Terse, laconic, concise. Only what's asked, nothing more. Short answers. Only build to check compilation. User runs all by himself.

---

## Session 1: Refactoring & Wave System

**Tasks**: Split monolithic files, implement level system
**Files**: GameScene split into 8 extensions, InputManager → protocol + implementations, Monster split

**Key Fixes**:
- Animation frame ordering: numeric extraction vs lexicographic
- Spawn coordinates: centered anchor (-size/2 to +size/2)
- Camera bounds: account for viewport in clamping
- Wave spawning: time-based triggers, not intervals

**Architecture**: GameLevel struct, LevelManager singleton, map size ≠ spawn box ≠ viewport

---

## Session 2: Media Integration

**Tasks**: Audio, backgrounds, tiling, resource paths
**Files**: AudioManager created, ContentView updated, tiled map implementation

**Key Fixes**:
- Resource loading: no subdirectories in Bundle.main
- Map boundaries: use level mapSize, not viewport size
- Ground texture: tiled (576 sprites) vs scaled single sprite
- Camera clamping: prevent black areas at edges

**Assets**: BGM (menu_1/2, fight_1/2), SFX (pistol, walker_1/2, reload), arcade backgrounds

---

## Session 3: UI/UX & Settings

**Tasks**: HUD, weapon system, settings menu, persistence
**Files**: GameHUD, UIStyleGuide, SettingsManager, Weapon/WeaponConfig, updated ContentView

**Key Fixes**:
- HUD positioning: parallelogram panels, camera-following layer
- Weapon reload: magazine system with progress tracking
- Settings: BGM/SFX toggles, UserDefaults persistence
- Random selection: @State initialization (runtime vs compile-time)

**UI**: 4 HUD elements (time/health/ammo/percentage), settings popup, styled buttons

---

## Architecture Decisions

**Coordinate System**: Centered anchor (0.5, 0.5) for camera math simplicity
**Input**: Protocol-based (KeyboardMouseInput, TouchInput, AIInput)
**Level System**: Wave-based spawning with time triggers
**Audio**: Singleton AudioManager with category-based random selection
**Map Rendering**: Tiled sprites for quality preservation
**Settings**: UserDefaults for persistence

---

## Common Pitfalls

1. Resource loading: all in app bundle root, no subdirectories
2. Coordinates: -size/2 to +size/2 for centered anchor
3. Animation frames: extract numeric part, sort numerically
4. Camera bounds: clamp to mapMin + viewport/2, mapMax - viewport/2
5. Physics: set anchor point before physics coordinates
6. Random selection: use @State/@Published for runtime evaluation

---

## Tech Stack

- macOS 26.0 (Darwin 25.0.0), Xcode 16+, Swift 5.0+
- SwiftUI, SpriteKit, AVFoundation
- ~30 Swift files, ~4000 lines total
