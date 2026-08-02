# Monster Shooter Equipment Inventory

Complete catalog of all equipment items extracted from the old game and organized for Swift implementation.

## Summary

- **Total Items**: 33 individual JSON files
- **Categories**: 5 (Weapons, Exoskeletons, Boosters, Tools, Consumables)
- **Source**: Old Monster Shooter C# server code and ActionScript client

---

## Weapons (6 types)

Located in: `weapons/`

1. **pistol.json** - ID: 1
   - Standard sidearm, balanced stats
   - Level 0, Free

2. **dual_pistols.json** - ID: 2
   - Two pistols, 2 bullets per shot
   - Level 5, 5000 soft / 100 hard

3. **rifle.json** - ID: 3
   - High precision automatic, penetrates 2 enemies
   - Level 10, 15000 soft / 250 hard

4. **minigun.json** - ID: 4
   - Extreme fire rate, 200 round magazine
   - Level 15, 25000 soft / 500 hard

5. **shotgun.json** - ID: 5
   - Close range, 7 pellets per shot
   - Level 8, 10000 soft / 200 hard

6. **sniper_rifle.json** - ID: 6
   - Extreme damage (50), long range (1500), penetrates 5
   - Level 20, Rank 3, 40000 soft / 800 hard

---

## Exoskeletons (7 types)

Located in: `exoskeletons/`

Defense values are damage reduction (0.0-1.0), Speed is multiplier (1.0 = normal)

1. **standard_suit.json** - ID: 1
   - No bonuses, Level 0, Free
   - Defense: 0.0, Speed: 1.0

2. **light_armor.json** - ID: 2
   - Slight protection with speed boost
   - Defense: 0.1 (10%), Speed: 1.05
   - Level 3, 3000 soft / 75 hard

3. **medium_armor.json** - ID: 3
   - Balanced
   - Defense: 0.2 (20%), Speed: 1.0
   - Level 7, 8000 soft / 150 hard

4. **heavy_armor.json** - ID: 4
   - Tank build
   - Defense: 0.35 (35%), Speed: 0.85
   - Level 12, 18000 soft / 350 hard

5. **recon_suit.json** - ID: 5
   - Speed focused
   - Defense: 0.05 (5%), Speed: 1.25
   - Level 10, 12000 soft / 200 hard

6. **elite_assault.json** - ID: 6
   - Best of both worlds
   - Defense: 0.3 (30%), Speed: 1.1
   - Level 20, Rank 5, 50000 soft / 1000 hard

7. **stealth_ops.json** - ID: 7
   - Ultra-light, maximum speed
   - Defense: 0.08 (8%), Speed: 1.35
   - Level 18, Rank 4, 35000 soft / 700 hard

---

## Boosters (8 types)

Located in: `boosters/`

Temporary buffs with duration in milliseconds. Effect types match old game enum values.

1. **damage_boost.json** - ID: 100
   - +50% weapon damage, 5 minutes
   - Level 5, 2000 soft / 50 hard

2. **defense_boost.json** - ID: 101
   - +30% defense, 5 minutes
   - Level 5, 2000 soft / 50 hard

3. **speed_boost.json** - ID: 102
   - +25% movement speed, 3 minutes
   - Level 3, 1500 soft / 35 hard

4. **rapid_fire.json** - ID: 103
   - -30% fire delay (faster shooting), 4 minutes
   - Level 8, 3000 soft / 65 hard

5. **extended_magazine.json** - ID: 104
   - 2x magazine capacity, 5 minutes
   - Level 10, 2500 soft / 55 hard

6. **penetration_rounds.json** - ID: 105
   - +3 penetration power, 5 minutes
   - Level 12, 3500 soft / 75 hard

7. **fast_reload.json** - ID: 106
   - -50% reload time, 4 minutes
   - Level 7, 2200 soft / 45 hard

8. **money_multiplier.json** - ID: 107
   - 2x earned money, 10 minutes
   - Level 1, 5000 soft / 100 hard

---

## Tools (5 types)

Located in: `tools/`

Consumable tactical items with explosion mechanics.

### Mines

1. **mine_basic.json** - ID: 200
   - Proximity mine, 150 explosion radius
   - 100 damage, 1 second arm delay
   - Stack: 5, Usage: 3 at once
   - Level 6, 500 soft / 15 hard

2. **mine_cluster.json** - ID: 201
   - Splits into 5 explosions, 200 radius
   - 80 damage each
   - Stack: 3, Usage: 2 at once
   - Level 15, 1500 soft / 35 hard

### Artillery

3. **artillery_strike.json** - ID: 202
   - 5 explosions over 3 seconds
   - 120 damage, 180 radius
   - Stack: 3, Usage: 1 at once
   - Level 10, 2000 soft / 50 hard

4. **artillery_barrage.json** - ID: 203
   - 10 explosions over 6 seconds
   - 150 damage, 200 radius
   - Stack: 2, Usage: 1 at once
   - Level 18, 4000 soft / 90 hard

### Explosion Belt

5. **explosion_belt.json** - ID: 204
   - Massive close-range blast
   - 200 damage, 250 radius
   - Stack: 1, Usage: 1 (one-time use)
   - Level 12, 1000 soft / 25 hard

---

## Consumables (3 types)

Located in: `consumables/`

Health restoration items usable during combat.

1. **health_kit_small.json** - ID: 300
   - Restores 25% health
   - Stack: 10
   - Level 0, 300 soft / 10 hard

2. **health_kit_large.json** - ID: 301
   - Restores 75% health
   - Stack: 5
   - Level 5, 800 soft / 20 hard

3. **health_kit_full.json** - ID: 302
   - Restores 100% health
   - Stack: 3
   - Level 10, 1500 soft / 35 hard

---

## File Organization

```
Resources/Equipment/
├── README.md                     # System documentation
├── EXTRACTION_SUMMARY.md         # Technical extraction details
├── INVENTORY.md                  # This file - complete catalog
├── weapon_schema.json            # Weapon JSON schema
├── exoskeleton_schema.json       # Exoskeleton JSON schema
├── weapons_example.json          # Legacy combined file
├── exoskeletons_example.json     # Legacy combined file
├── weapons/                      # 6 individual weapon files
├── exoskeletons/                 # 7 individual armor files
├── boosters/                     # 8 individual booster files
├── tools/                        # 5 individual tool files
└── consumables/                  # 3 individual consumable files
```

---

## Implementation Notes

### Loading Strategy

1. **On Demand**: Load individual files as needed
2. **Batch**: Create combined JSON arrays per category
3. **Swift Codable**: Use existing patterns from WeaponConfig

### Example Swift Structure

```swift
// Extend WeaponConfig to support all 6 weapon types
enum WeaponType: Int, Codable {
    case pistol = 1
    case dualPistols = 2
    case rifle = 3
    case minigun = 4
    case shotgun = 5
    case sniperRifle = 6
}

// Create ExoskeletonConfig
struct ExoskeletonConfig: Codable, Identifiable {
    let id: Int
    let name: String
    let defence: Double
    let speed: Double
    // ... other properties
}

// Create BoosterConfig
struct BoosterConfig: Codable, Identifiable {
    let id: Int
    let name: String
    let duration: Int
    let effects: [BoosterEffect]
    // ... other properties
}
```

### Usage in Game

- **Weapons**: Player equips one at a time (already implemented)
- **Exoskeletons**: Player equips one at a time, affects defense/speed
- **Boosters**: Activate during mission, stack multiple effects
- **Tools**: Consumable, limit active placements
- **Health Kits**: Instant use, restore health percentage

---

## Currency System

- **Soft Money**: In-game currency earned from kills/missions
- **Hard Money**: Premium currency (real money purchases)
- Both can be used to buy items, hard money items are premium

---

## Level Requirements

Items unlock as player progresses:
- Level 0-5: Basic items (pistol, light armor, small kits)
- Level 6-12: Intermediate (shotgun, medium armor, mines)
- Level 13-20: Advanced (minigun, heavy armor, artillery)
- Rank requirements for elite items (20+ with rank 3-5)

---

Generated: October 27, 2025
Source: Monster Shooter old_shooter codebase
