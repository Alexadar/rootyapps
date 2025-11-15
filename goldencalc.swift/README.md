# Golden Ratio Tech Calculator

A cross-platform SwiftUI calculator for golden ratio computations, featuring a modern liquid glass design on macOS.

## Overview

This app calculates golden ratio relationships between three values (a, b, c) where:
- `a × φ = c` (where φ ≈ 1.618)
- `c × 0.618 = a`
- `c × 0.382 = b`

## Architecture

### GoldenRatioModel

The app uses a clean separation between UI and business logic through the `GoldenRatioModel` class.

**Key Design Pattern: Preventing Circular Updates**

The model follows a simple principle: when one field changes, only the other two fields are recalculated.

#### How It Works

1. **User edits field A**: The model returns new values for **(b, c)** only
   ```swift
   func calcFromA(_ a: Float) -> (b: Float, c: Float)
   ```

2. **User edits field B**: The model returns new values for **(a, c)** only
   ```swift
   func calcFromB(_ b: Float) -> (a: Float, c: Float)
   ```

3. **User edits field C**: The model returns new values for **(a, b)** only
   ```swift
   func calcFromC(_ c: Float) -> (a: Float, b: Float)
   ```

#### Preventing Circular Updates

The UI uses an `isApplyingModelUpdate` flag to prevent infinite loops:

```
User types "11" in field A
  ↓
calculateFromA() is called
  ↓
isApplyingModelUpdate = true
  ↓
Update valueB and valueC (calculated values)
  ↓
B and C's onChange fires
  ↓
Check: isApplyingModelUpdate == true? → Skip calculation!
  ↓
DispatchQueue.main.async { isApplyingModelUpdate = false }
```

**Why DispatchQueue.main.async?**

Without the async dispatch, there's a race condition where:
1. Flag is set to `false` immediately
2. SwiftUI propagates changes to B and C
3. B and C's `onChange` sees `false` and recalculates A
4. Field A gets reformatted (e.g., "11" → "11.000000")

By using `DispatchQueue.main.async`, we defer setting the flag to false until the next run loop, ensuring all SwiftUI updates complete while the flag is still `true`.

### Golden Ratio Constants

- `coefA = 0.6180339887` (φ - 1, or 1/φ)
- `coefB = 0.3819660113` (2 - φ)
- `ratio = 1.6180339887` (φ, the golden ratio)

### Platform Support

- **macOS**: Features liquid glass transparent window with blurred background
- **iOS**: Standard SwiftUI interface
- **watchOS**: Simplified interface for Apple Watch
- **tvOS**: TV-optimized layout

## Liquid Glass Design (macOS)

The macOS version features a modern liquid glass aesthetic:

### Window Transparency
- Custom `TransparentWindow` class extends `NSWindow`
- Uses `NSVisualEffectView` with `.hudWindow` material
- `.behindWindow` blending mode shows desktop through the window
- Rounded corners (12px) with subtle white border (20% opacity)

### Card Styling
- All cards use `.ultraThinMaterial` background
- Rounded corners with drop shadows for depth
- Consistent spacing and padding

### Implementation Details

```swift
// Custom window with liquid glass effect
class TransparentWindow: NSWindow {
    // Sets up NSVisualEffectView as content view
    // Applies rounded corners and border
    // Enables .behindWindow blending for transparency
}

// Window controller manages SwiftUI content
class TransparentWindowController: NSWindowController {
    // Wraps SwiftUI view in NSHostingView
    // Adds to visual effect view
}
```

The `AppDelegate` creates the transparent window instead of using SwiftUI's default `WindowGroup`, allowing full control over window appearance.

## Code Structure

```
goldencalc/
├── GoldenRatioModel.swift          # Core calculation logic
├── ContentView.swift                # Main view coordinator
├── goldencalcApp.swift             # App entry point with AppDelegate
└── Views/
    ├── MacOSContentView.swift      # macOS-specific UI with liquid glass
    ├── IOSContentView.swift        # iOS-specific UI
    ├── WatchOSContentView.swift    # watchOS-specific UI
    └── TVOSContentView.swift       # tvOS-specific UI
```

## Building

Requires:
- Xcode 15.0 or later
- macOS Sequoia 15.0+ for liquid glass features
- iOS 17.0+, watchOS 10.0+, tvOS 17.0+

## Features

- ✅ Real-time golden ratio calculations
- ✅ Copy/paste values between fields
- ✅ Platform-specific optimized layouts
- ✅ Liquid glass transparent window (macOS)
- ✅ Dark mode support
- ✅ No circular update loops
- ✅ Clean architecture with separated concerns

## License

Created by Oleksandr Koreniuk
