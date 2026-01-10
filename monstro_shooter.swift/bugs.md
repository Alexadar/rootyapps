# Bug Fixes

## 1. App State Persistence (FIXED)

**Original Issue:** On iOS and macOS, minimizing to tray and going back resets game state.

**What Changed:**
- Created `SavedGameState.swift` with Codable struct for serialization
- Added `saveGameState()` called on `appDidEnterBackground` (iOS) and `appWillResignActive` (macOS)
- Added `restoreGameState()` called in `didMove(to:)` to restore state after app termination
- Added `clearSavedGameState()` called on game over, victory, and return to menu
- Saves: elapsed time, player position/health/ammo, wave index, spawned waves, kill count, monsters (position/health/typeID), tutorial state
- State expires after 1 hour and validates map filename matches

**How to Test:**
1. Start game, play for 30+ seconds, let some monsters spawn
2. Press Home button (iOS) or Cmd+H (macOS) to minimize
3. Wait a few seconds, then return to app
4. Player position, health, and monsters should be preserved
5. Kill all monsters or die - state should clear (no restore on next minimize/restore)

---

## 2. Performance Optimizations (FIXED)

**Original Issue:** Performance issues in gameplay.

**What Changed:**
- Removed 4 print statements from hot paths in `GameScene+Monsters.swift`:
  - Removed spawn position logging
  - Removed monster stats logging
  - Removed damage range logging
  - Removed total monster count logging
- Removed 1 print statement from `Player.swift`:
  - Removed takeDamage logging

**How to Test:**
1. Run game in Debug configuration
2. Open Console.app and filter by app name
3. Play game - should see minimal console output during gameplay
4. Only reload and config loading messages should appear

---

## 3. Monster Damage Range Calculation (FIXED)

**Original Issue:** Sometimes monsters "stick" to player without dealing damage, only damage on rollover.

**What Changed:**
- Modified `updateDamageFromMonsters()` in `GameScene+Monsters.swift`
- Previously only used `playerHitboxRadius + 5.0` for damage range
- Now accounts for monster size: `playerRadius + monsterRadius + 5.0`
- Uses squared distance for performance

**How to Test:**
1. Start game and let a monster reach you
2. Stand still - monster should deal damage every ~1 second
3. Try with different monster types (different sizes)
4. All monsters should consistently deal damage on contact

---

## 4. Pause Button for iOS/iPad (FIXED)

**Original Issue:** No pause menu button on iOS/iPad touch devices.

**What Changed:**
- Added pause button to `HUDCamera.swift` (iOS only, `#if !os(macOS)`)
- 44x44pt button positioned at top center of screen
- Uses double-bar pause icon with UIStyleGuide colors
- Added `handleTouch(at:)` method to HUDCamera
- Added `onPauseTapped` callback connected to `pauseGame()` in `GameScene+Lifecycle.swift`
- Touch handling in `GameScene+Input.swift` checks pause button before processing game touches

**How to Test:**
1. Run on iOS device or simulator
2. Pause button appears at top center during gameplay
3. Tap pause button - pause menu should appear
4. Tap Resume - game continues
5. Tap Main Menu - returns to main menu
6. Button should not appear on macOS (use Escape key instead)

---

## 5. Monster Spawn Distance (FIXED)

**Original Issue:** Monsters spawn from map start (far away), making them invisible for too long.

**What Changed:**
- Modified `spawnMonster()` in `GameScene+Monsters.swift`
- Previously used fixed 4500x4500 spawn box
- Now calculates spawn box based on viewport: `(viewportSize / 2) / cameraScale + 100`
- Monsters spawn just 100 points outside the visible screen edge
- Spawn position centered on player, not map center

**How to Test:**
1. Start game and wait for monster spawns
2. Monsters should appear at screen edges within ~1 second of spawning
3. Test on different screen sizes (iPhone, iPad, Mac)
4. Spawn timing should feel consistent regardless of device

---

## 6. UI Styles Consolidation (FIXED)

**Original Issue:** Some UI uses "on the fly" styles instead of UIStyleGuide.

**What Changed:**
- Added new style sections to `UIStyleGuide.swift`:
  - `HUD`: panelWidth, panelHeight, cornerRadius, colors, fontSize, fontName
  - `PauseMenu`: panel styles, title styles, button styles (colors, fonts, sizes, spacing)
  - `GameOver`: titleFontSize, titleFontName, colors for victory/death
  - `Tutorial`: fontSize, fontName, colors, padding
  - `Dropdown`: colors for SwiftUI dropdowns
- Updated `PauseMenuUI.swift` to use UIStyleGuide:
  - Panel uses `PauseMenu.panelBackgroundColor`, `panelBorderColor`, etc.
  - Title uses `PauseMenu.titleFontName`, `titleFontSize`, `titleColor`
  - Buttons use `PauseMenu.buttonFontName`, `buttonFontSize`, `buttonHighlightColor`, etc.

**How to Test:**
1. Open pause menu (Escape on Mac, pause button on iOS)
2. Verify consistent styling with main menu
3. Colors should match UIStyleGuide definitions (cyan accents, deep space blue backgrounds)
4. Search codebase for hardcoded color values - should be minimal
