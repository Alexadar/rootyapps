# Big Pink Cat - Unity to SpriteKit Port

## Overview
This is a port of the "Astronaut and the Mysterious Pink Cat" visual novel from Unity/C# to SpriteKit/Swift.

## What Has Been Ported

### ✅ Data Models
- `GameDataModels.swift` - All game data structures (GameMeta, Character, Dialog, etc.)
- Properly structured with Codable support for YAML parsing

### ✅ YAML Parser
- `YAMLParser.swift` - Basic YAML parser for game data files
- Handles the specific YAML format used by the game
- Converts YAML to JSON for Codable decoding

### ✅ Game Data Loader
- `GameDataLoader.swift` - Loads all game content from Resources
- Parses characters, dialogs, story summaries
- Builds dialog tree with proper navigation

### ✅ Visual Novel Game Logic
- `VisualNovelScene.swift` - Main game scene with complete visual novel system
- State machine: Loading → Main Menu → Dialog → Options → Final Words
- Dialog system with text display
- Choice-based branching story
- Touch/mouse input handling for all platforms (iOS, macOS, tvOS)

### ✅ Assets Copied
- All YAML story files (characters_meta, game_meta, dialogs, etc.)
- Audio files (bgm.wav)
- Video files for characters and background

## Architecture Comparison

### Unity (C#)
```
QuestGameComponent
  ├── State Machine (UIState enum)
  ├── LoadResources()
  ├── GameMenu()
  ├── Dialog System
  └── Options System

QuestGameModel
  ├── YAML Deserialization (YamlDotNet)
  ├── Data Loading
  └── Dialog Tree Building
```

### SpriteKit (Swift)
```
VisualNovelScene
  ├── State Machine (UIState enum)
  ├── loadGameData()
  ├── Main Menu
  ├── Dialog System
  └── Options System

GameDataLoader
  ├── YAML Parsing (Custom parser)
  ├── Data Loading
  └── Dialog Tree Building

YAMLParser
  └── YAML → JSON → Codable
```

## Game Features

### Implemented
- ✅ Main menu with game title
- ✅ Dialog system with character names
- ✅ Text display with fade animations
- ✅ Multiple choice branching
- ✅ Story progression
- ✅ End game / final words display
- ✅ Multi-platform input (iOS/macOS/tvOS)

### TODO - Next Steps

1. **Add Resources to Xcode Project**
   - Open `bigpinkcat.swift.xcodeproj` in Xcode
   - Add the `Resources` folder to the project
   - Make sure YAML files are included in Copy Bundle Resources

2. **Improve YAML Parser**
   - Consider using the `Yams` library (via Swift Package Manager)
   - Current parser works but could be more robust
   - Add dependency: `https://github.com/jpsim/Yams`

3. **Video Integration**
   - Implement video playback with AVPlayer + SKVideoNode
   - Play character videos during dialog
   - Play background video on main menu

4. **Background Music**
   - Fix audio file path
   - Ensure BGM loops correctly
   - Add fade in/out effects

5. **UI Polish**
   - Better text rendering (word wrap, typing effect)
   - Character portrait display
   - Background images/videos
   - Transition animations between states

6. **Testing**
   - Test all story branches
   - Test on all platforms (iOS, macOS, tvOS)
   - Verify all assets load correctly

## How to Build

1. Open `bigpinkcat.swift.xcodeproj` in Xcode
2. Select your target platform (iOS, macOS, or tvOS)
3. Add the Resources folder to the project if not already included
4. Build and run

## Story Structure

The game has:
- **2 Characters**: Astronaut (id: 1) and Pink Cat (id: 2)
- **Multiple Story Branches**: Based on player choices
- **Dialog Files**: dialog_0.yaml through dialog_3.yaml
- **Summary Parts**: Define story structure and branching

## Code Files

### Core Game Files
- `VisualNovelScene.swift` - Main game scene
- `GameDataModels.swift` - Data structures
- `GameDataLoader.swift` - Asset loading
- `YAMLParser.swift` - YAML parsing
- `GameScene.swift` - Scene factory

### Resources
- `Resources/output_story/` - All game content
  - `game_meta.yaml` - Game title and description
  - `characters_meta.yaml` - Character definitions
  - `dialogs/` - Dialog content
  - `summary_parts/` - Story structure
  - `audio/` - Background music
  - `video/` - Character animations

## Known Limitations

1. YAML parser is simplified - may not handle all edge cases
2. Video playback not yet implemented
3. Background music path needs to be verified
4. No typing effect for dialog text (only fade-in)
5. Options UI could be more polished

## Original Unity Version

The Unity version used:
- TextMeshPro for text rendering
- VideoPlayer for character animations
- YamlDotNet for YAML parsing
- Unity UI system for buttons and layout

This SpriteKit version recreates the same functionality using:
- SKLabelNode for text
- AVPlayer (to be implemented) for video
- Custom YAML parser
- SKShapeNode for buttons

## License

Same as original Unity version.
