# Add New Swift Files to Xcode Project

## Quick Instructions

The new Swift files for the visual novel system are already created in the `bigpinkcat.swift Shared` folder but need to be added to the Xcode project.

### Files to Add:
1. `GameDataModels.swift` - Data structures
2. `YAMLParser.swift` - YAML parsing
3. `GameDataLoader.swift` - Data loading
4. `VisualNovelScene.swift` - Main game scene

### Steps to Add Files:

1. Open the project in Xcode:
   ```bash
   open bigpinkcat.swift.xcodeproj
   ```

2. In Xcode's Project Navigator (left sidebar), locate the **"bigpinkcat.swift Shared"** folder

3. Right-click on **"bigpinkcat.swift Shared"** → **"Add Files to bigpinkcat.swift..."**

4. Navigate to: `bigpinkcat.swift Shared/` folder

5. Select all 4 new Swift files:
   - GameDataModels.swift
   - YAMLParser.swift
   - GameDataLoader.swift
   - VisualNovelScene.swift

6. Make sure these options are checked:
   - ✅ **"Copy items if needed"** (UNCHECKED - files are already in place)
   - ✅ **"Create groups"** (selected)
   - ✅ **"Add to targets"**: Check ALL three targets:
     - bigpinkcat.swift iOS
     - bigpinkcat.swift macOS
     - bigpinkcat.swift tvOS

7. Click **"Add"**

8. Also add the **Resources** folder:
   - Right-click on "bigpinkcat.swift Shared" again
   - Select "Add Files to bigpinkcat.swift..."
   - Select the **"Resources"** folder (contains output_story)
   - Check "Create folder references" (NOT "Create groups")
   - Add to all targets

9. Build the project: **⌘B** (Command-B)

## Alternative: Use Xcode's File Inspector

If files are already visible but not added to targets:

1. Select each Swift file in Project Navigator
2. Open File Inspector (right sidebar, first tab)
3. Under "Target Membership", check all three targets

## Verify Success

After adding files, you should see in the Project Navigator:

```
bigpinkcat.swift Shared/
├── Actions.sks
├── Assets.xcassets
├── GameDataLoader.swift ⭐ NEW
├── GameDataModels.swift ⭐ NEW
├── GameScene.sks
├── GameScene.swift (modified)
├── Resources/ ⭐ NEW
│   └── output_story/
├── VisualNovelScene.swift ⭐ NEW
└── YAMLParser.swift ⭐ NEW
```

## Build Again

After adding files:
```bash
xcodebuild -project bigpinkcat.swift.xcodeproj -scheme "bigpinkcat.swift macOS" -configuration Debug build
```

Or just press **⌘B** in Xcode!
