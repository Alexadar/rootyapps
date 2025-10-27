# Monstro Shooter Maps Documentation

## Overview

- **Total Maps**: 250
- **Active Maps**: 250 (all maps, none removed)
- **Map ID Range**: 1, 14-37, 1029-1273

## Monster Types Used in Maps

**Total Unique Monster IDs**: 21

### Monster ID to Name Mapping

Based on Swift implementation and database:

| ID | Name | Resource Name | Status | Used in Maps |
|----|------|---------------|--------|--------------|
| 1  | Bug | Bug | ✅ Implemented | 97 maps |
| 2  | Walker/Berserker | Beetle1 | ✅ Implemented | 104 maps |
| 3  | Bird | Beetle | ✅ Implemented | 93 maps |
| 4  | Bug2 | Bug2 | ✅ Implemented | 50 maps |
| 5  | Bird2 | Beetle2 | ✅ Implemented | 42 maps |
| 6  | Unknown | - | ❌ Not Implemented | 42 maps |
| 7  | Unknown | - | ❌ Not Implemented | 31 maps |
| 8  | Unknown | - | ❌ Not Implemented | 35 maps |
| 9  | Unknown | - | ❌ Not Implemented | 37 maps |
| 10 | Unknown | - | ❌ Not Implemented | 33 maps |
| 11 | Unknown | - | ❌ Not Implemented | 35 maps |
| 12 | Unknown | - | ❌ Not Implemented | 26 maps |
| 13 | Unknown | - | ❌ Not Implemented | 44 maps |
| 14 | Unknown | - | ❌ Not Implemented | 18 maps |
| 15 | Unknown | - | ❌ Not Implemented | 34 maps |
| 16 | Unknown | - | ❌ Not Implemented | 44 maps |
| 17 | Unknown | - | ❌ Not Implemented | 23 maps |
| 18 | Unknown | - | ❌ Not Implemented | 15 maps |
| 22 | Unknown | - | ❌ Not Implemented | 3 maps |
| 23 | Walker | - | ✅ Implemented | 3 maps |
| 24 | Unknown | - | ❌ Not Implemented | 4 maps |

**Note**: IDs 19, 20, 21 are not used in any maps.

## Active Maps

**Status**: All 250 maps are active (`"removed": false`)

Maps are sorted by `orderNumber` field for progression:
- **Order 0**: 109 maps (test/tutorial maps)
- **Order 100-500**: Early game maps
- **Order 500+**: Advanced maps

Example active maps (first 10 by orderNumber):
1. Map 16 (Order 0) - "Тест жук" - 600s - Test map
2. Map 21 (Order 0) - "Карта 6" - 40s
3. Map 22 (Order 0) - "Карта 7" - 45s
4. Map 23 (Order 0) - "Карта 8" - 50s
5. Map 24 (Order 0) - "Карта 9" - 55s
6. Map 25 (Order 0) - "Карта 10" - 60s
7. Map 26 (Order 0) - "Карта 11" - 60s
8. Map 27 (Order 0) - "Карта 12" - 60s
9. Map 28 (Order 0) - "Карта 13" - 60s
10. Map 29 (Order 0) - "Карта 14" - 60s

**Map Selection**: In the original game, maps were likely filtered/unlocked based on:
- Player level
- `orderNumber` for progression
- `removed` flag for availability
- Possibly by `dropPointId` (landing zones on world map)

## Game Resources (Map Backgrounds)

The `gameResource` field determines which background tileset/texture is loaded for the map.

| Resource | Maps Count | Description |
|----------|------------|-------------|
| map_1    | 60 maps    | Default background |
| map_2    | 98 maps    | Most popular background |
| map_3    | 19 maps    | Alternative background |
| map_4    | 15 maps    | Alternative background |
| map_5    | 14 maps    | Alternative background |
| map_6    | 15 maps    | Alternative background |
| map_7    | 28 maps    | Alternative background |
| map_8    | 1 map      | Rare background |

**Total**: 8 different map backgrounds/tilesets

**How it works**:
- Each map JSON has a `gameResource` field (e.g., `"gameResource": "map_1"`)
- The game loads corresponding background tiles/texture from `Resources/` directory
- Background is purely visual - doesn't affect gameplay mechanics

