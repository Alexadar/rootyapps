# MVP Code Fixes for Big Pink Cat Visual Novel

## Overview

This document outlines code improvements Claude Code can implement to transform Big Pink Cat into a minimum viable visual novel for iOS/macOS App Store.

**Current State:** Basic visual novel engine with branching narrative, video characters, and background music.

**Target:** Market-ready visual novel with essential player features.

---

## Phase 1: Core Persistence (Critical)

### 1.1 Save/Load System
**Files to modify:** `GameDataModels.swift`, `GameDataLoader.swift`, `VisualNovelScene.swift`

**Tasks:**
- [ ] Create `SaveData` struct in `GameDataModels.swift`:
  ```swift
  struct SaveData: Codable {
      let slotId: Int
      let summaryIndex: Int
      let dialogIndex: Int
      let timestamp: Date
      let previewText: String
  }
  ```
- [ ] Add `SaveManager` class to handle save/load operations using `UserDefaults` or file system
- [ ] Implement 3 save slots with timestamp and scene preview
- [ ] Add save functionality triggered by player action or auto-save
- [ ] Add load functionality to restore exact game state
- [ ] Track current `dialogIndex` within summary (currently only `summaryIndex` is tracked)

**Estimated complexity:** Medium

### 1.2 Settings Persistence
**Files to modify:** `VisualNovelScene.swift`, `GameDataModels.swift`

**Tasks:**
- [ ] Create `GameSettings` struct:
  ```swift
  struct GameSettings: Codable {
      var textSpeed: TextSpeed  // slow, normal, fast, instant
      var autoPlayDelay: Double // 2.0, 4.0, 6.0 seconds
      var bgmVolume: Float      // 0.0 - 1.0
      var sfxVolume: Float      // 0.0 - 1.0
      var isMuted: Bool
  }
  ```
- [ ] Replace single `muteSettingKey` with full `GameSettings` persistence
- [ ] Apply settings on app launch

**Estimated complexity:** Low

---

## Phase 2: UI/UX Improvements (High Priority)

### 2.1 Text Speed Control
**Files to modify:** `VisualNovelScene.swift`

**Tasks:**
- [ ] Replace instant `fadeIn` with typewriter effect in `animateDialogText()`
- [ ] Implement character-by-character reveal with configurable speed
- [ ] Add tap-to-complete for impatient players
- [ ] Speed options: Slow (50ms/char), Normal (30ms/char), Fast (15ms/char), Instant

**Estimated complexity:** Low-Medium

### 2.2 Auto-Play Mode
**Files to modify:** `VisualNovelScene.swift`

**Tasks:**
- [ ] Add `isAutoPlaying: Bool` state variable
- [ ] After dialog text completes, wait `autoPlayDelay` then call `advanceDialog()`
- [ ] Add auto-play toggle button to main menu and in-game UI
- [ ] Show visual indicator when auto-play is active
- [ ] Pause auto-play when options are presented

**Estimated complexity:** Low

### 2.3 Settings Menu UI
**Files to modify:** `VisualNovelScene.swift`

**Tasks:**
- [ ] Add new `UIState.settings` case to state machine
- [ ] Create settings menu with sliders/buttons:
  - Text speed selector
  - Auto-play delay selector
  - BGM volume slider
  - SFX volume slider (for future use)
  - Back button
- [ ] Add "Settings" button to main menu (alongside Start/Mute)
- [ ] Remove standalone "Mute" button (replaced by volume controls)

**Estimated complexity:** Medium

### 2.4 Title Screen Redesign
**Files to modify:** `VisualNovelScene.swift`

**Tasks:**
- [ ] Reorganize main menu buttons:
  - "New Game" - starts from beginning
  - "Continue" - loads most recent save (disabled if no saves)
  - "Load Game" - shows save slots
  - "Settings" - opens settings menu
- [ ] Add save slot selection UI for Load Game
- [ ] Add confirmation dialog for "New Game" if saves exist

**Estimated complexity:** Medium

---

## Phase 3: Enhanced Features (Important)

### 3.1 Text History/Backlog
**Files to modify:** `VisualNovelScene.swift`, `GameDataModels.swift`

**Tasks:**
- [ ] Create `DialogHistoryEntry` struct:
  ```swift
  struct DialogHistoryEntry {
      let characterName: String
      let text: String
      let timestamp: Date
  }
  ```
- [ ] Maintain array of last 100 dialog entries
- [ ] Add `UIState.backlog` state
- [ ] Create scrollable backlog view (swipe up or button to open)
- [ ] Style to match game aesthetic

**Estimated complexity:** Medium

### 3.2 Skip Read Text
**Files to modify:** `VisualNovelScene.swift`, `GameDataLoader.swift`

**Tasks:**
- [ ] Track which dialog IDs have been seen (persist in UserDefaults)
- [ ] Add "Skip" button that fast-forwards through seen dialog only
- [ ] Add setting for skip mode: "Skip All" vs "Skip Read Only"
- [ ] Visual feedback when skipping

**Estimated complexity:** Medium

### 3.3 Scene Transitions
**Files to modify:** `VisualNovelScene.swift`

**Tasks:**
- [ ] Add fade-to-black transition between scenes
- [ ] Implement crossfade for video changes
- [ ] Add transition when entering/leaving options state
- [ ] Smooth fade for final words display

**Estimated complexity:** Low

### 3.4 Endings Gallery
**Files to modify:** `VisualNovelScene.swift`, `GameDataModels.swift`

**Tasks:**
- [ ] Track unlocked endings by `summaryIndex` that has `finalWordsOfTheStory`
- [ ] Add "Gallery" or "Endings" option to main menu
- [ ] Create `UIState.gallery` to display unlocked endings
- [ ] Show locked endings as "???" placeholders
- [ ] Allow replay of unlocked endings

**Estimated complexity:** Medium

---

## Phase 4: Polish (Nice to Have)

### 4.1 Sound Effects
**Files to modify:** `VisualNovelScene.swift`

**Tasks:**
- [ ] Add UI click sound on button press
- [ ] Add dialog advance sound (optional)
- [ ] Add transition sounds
- [ ] Load SFX files from bundle (need to add audio files)

**Estimated complexity:** Low

### 4.2 Button Hover/Press States
**Files to modify:** `VisualNovelScene.swift`

**Tasks:**
- [ ] Highlight button on hover (macOS)
- [ ] Scale/color change on press
- [ ] Add subtle animation to selected options

**Estimated complexity:** Low

### 4.3 Loading Indicator
**Files to modify:** `VisualNovelScene.swift`

**Tasks:**
- [ ] Replace static "Loading..." text with animated indicator
- [ ] Add spinner or pulsing animation
- [ ] Show progress if possible

**Estimated complexity:** Low

### 4.4 Haptic Feedback (iOS)
**Files to modify:** `VisualNovelScene.swift`

**Tasks:**
- [ ] Add `UIImpactFeedbackGenerator` for button presses
- [ ] Subtle haptics on dialog advance
- [ ] Conditional compilation for iOS only

**Estimated complexity:** Low

---

## Implementation Order (Recommended)

| Priority | Feature | Impact | Effort |
|----------|---------|--------|--------|
| 1 | Settings persistence model | Foundation | Low |
| 2 | Text speed control | UX | Low |
| 3 | Auto-play mode | UX | Low |
| 4 | Save/Load system | Critical | Medium |
| 5 | Settings menu UI | UX | Medium |
| 6 | Title screen redesign | UX | Medium |
| 7 | Text history/backlog | UX | Medium |
| 8 | Scene transitions | Polish | Low |
| 9 | Skip read text | UX | Medium |
| 10 | Endings gallery | Engagement | Medium |
| 11 | Sound effects | Polish | Low |
| 12 | Button states | Polish | Low |

---

## Files Summary

| File | Changes Needed |
|------|----------------|
| `GameDataModels.swift` | Add SaveData, GameSettings, DialogHistoryEntry structs |
| `GameDataLoader.swift` | Add SaveManager, settings loader |
| `VisualNovelScene.swift` | All UI features, state machine updates, settings integration |
| `GameContentView.swift` | Minor - may need settings binding |

---

## Notes

- All features are pure Swift/SpriteKit - no new dependencies needed
- Save system uses existing YAML indices for state restoration
- Settings use `UserDefaults` for simplicity (CloudKit sync can be added later)
- Maintain backward compatibility with existing story data format
- Test on both macOS windowed and iOS fullscreen modes

---

*Generated by Claude Code analysis of bigpinkcat.swift codebase*
