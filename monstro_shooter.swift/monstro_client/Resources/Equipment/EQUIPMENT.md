# Equipment System - Monster Shooter

## Overview

The equipment system in Monster Shooter consists of several item types that players can purchase and equip.

## Item Class Hierarchy

```
ItemType (Base Class)
├── Weapon
├── Exoskeleton (Armor)
├── Tool
│   ├── Mine
│   ├── Artillery
│   └── ExplosionBelt
├── Booster
├── Cosmetics
├── Bottle
├── RestoreHealthInGame (Action Item)
├── MoneyItem
└── ItemsPackage
```

## Base ItemType Properties

All items inherit these properties:

- **id**: Unique identifier
- **name**: Localized item name
- **description**: Localized item description
- **levelRequirement**: Minimum player level to use
- **rankRequirement**: Minimum player rank to use
- **buyPriceHard**: Purchase price in hard currency (premium)
- **buyPriceSoft**: Purchase price in soft currency (regular)
- **sellPriceHard**: Sell value in hard currency
- **sellPriceSoft**: Sell value in soft currency
- **marketAvailability**: Whether item appears in market
- **orderId**: Display order in market
- **itemClass**: Item class/category ID
- **discountPriceHard**: Discounted hard currency price (for ranked players)
- **discountPriceSoft**: Discounted soft currency price (for ranked players)

## Weapon Properties

Weapons extend ItemType with:

### Damage & Range
- **damage**: Base damage per bullet
- **shotRange**: Maximum range in pixels
- **penetrationPower**: Number of enemies a bullet can pierce through

### Fire Rate & Magazine
- **shotDelay**: Time between shots in milliseconds
- **cageSize**: Magazine size (bullets per magazine)
- **rechargeDelay**: Reload time in milliseconds

### Bullet Behavior
- **bulletsCount**: Number of bullets fired per shot (1 for single, 5+ for shotgun)
- **bulletSpeed**: Bullet velocity (pixels per frame in AS3, or absolute value)
- **bulletDeviation**: Spread angle for accuracy (in degrees or radians)
- **bulletMaxDeviation**: Maximum spread angle
- **bulletType**: Bullet graphic type ID

### Visual Effects
- **bulletStartScale**: Initial bullet size (e.g., 0.3)
- **bulletMaxScale**: Maximum bullet size (e.g., 1.0)
- **bulletScaleFactor**: Growth rate per frame (e.g., 0.05)
- **bloodSpotImages**: Array of blood splatter graphic IDs

### Audio
- **weaponSound**: Sound effect name for firing

### Weapon Types
- **type**: WeaponType enum value
  - 0: Unknown/Default
  - 1: Pistol (single shot, balanced)
  - 2: Dual Pistols (two bullets, fast)
  - 3: Rifle (fast fire rate, medium damage)
  - 4: Minigun (very fast, lower damage, spray)

## Exoskeleton (Armor) Properties

Exoskeletons extend ItemType with:

- **defence**: Damage reduction value (percentage or absolute)
- **speed**: Movement speed modifier (percentage or absolute)
- **gameResource**: In-game sprite/animation resource
- **lobbyResource**: Lobby/menu preview resource

### Special Notes
- Exoskeletons and Weapons are **unique per inventory** - player can only have one of each equipped at a time
- The `defence` value likely reduces incoming damage
- The `speed` value affects player movement speed (higher = faster)

## Tool Properties

Tools are consumable items used in combat:

### Mine
- Deployable explosive trap
- Detonates when enemy approaches

### Artillery
- Area of effect attack
- Called in on target location

### ExplosionBelt
- Explosive device worn by player
- Large AoE damage when triggered

## Booster Properties

Boosters provide temporary effects:

- **BoosterEffect**: Array of effects
  - **BoosterEffectType**: Type of boost (damage, defense, speed, etc.)
  - **BoosterEffectValueType**: How value is applied (percentage, absolute)
  - **Value**: Magnitude of effect
  - **Duration**: How long the boost lasts

## Game Integration

### How Weapons Work in Game

Based on the ActionScript client code:

1. **Firing Mechanism**:
   - Player fires weapon every `shotDelay` milliseconds
   - Each shot creates `bulletsCount` bullets
   - Each bullet has random deviation within `bulletDeviation` to `bulletMaxDeviation`

2. **Bullet Lifecycle**:
   - Bullet starts at `bulletStartScale` size
   - Grows by `bulletScaleFactor` each frame until reaching `bulletMaxScale`
   - Travels at `bulletSpeed` pixels per frame
   - Hits up to `penetrationPower` enemies before disappearing
   - Deals `damage` to each enemy hit
   - Maximum travel distance is `shotRange` pixels

3. **Reload**:
   - After `cageSize` bullets fired, weapon must reload
   - Reload takes `rechargeDelay` milliseconds

### How Exoskeletons Work in Game

1. **Defense**:
   - Reduces incoming damage by `defence` amount
   - Likely a percentage reduction (e.g., 0.2 = 20% damage reduction)

2. **Speed**:
   - Modifies player movement speed
   - Likely a multiplier (e.g., 1.2 = 20% faster, 0.8 = 20% slower)
   - Trade-off: Heavy armor = more defense but slower movement

3. **Visual**:
   - Changes player sprite/animation based on `gameResource`
   - Different exoskeletons have different visual appearances

## Database Storage

Items are stored via:

- **Stored Procedure**: `GetItemTypes(@Culture nvarchar(10))`
- Returns all items with localized name/description based on culture
- Item-specific data (like Weapon or Exoskeleton properties) is stored in XML format in the `Data` column
- Server deserializes XML into appropriate ItemType subclass

## Example Weapon Stats

From the ActionScript default values:

```javascript
// Default Weapon (likely Pistol)
{
  damage: 10,
  shotRange: 350,
  shotDelay: 1200,      // 1.2 seconds between shots
  cageSize: 9,          // 9 bullets per magazine
  rechargeDelay: 20000, // 20 seconds to reload (seems high, likely milliseconds)
  bulletsCount: 1,      // Single bullet per shot
  bulletSpeed: 0.175,   // Pixels per frame (AS3 value)
  bulletDeviation: 2,   // 2 degrees of spread
  penetrationPower: 1   // Hits 1 enemy
}
```

## Notes for Swift Implementation

1. Weapon values need conversion from ActionScript to Swift/SpriteKit units
2. `bulletSpeed` in AS3 is pixels-per-frame (at ~60fps)
3. Delays are in milliseconds
4. Deviation likely in degrees, may need conversion to radians
5. Consider weapon balance when porting stats
6. Exoskeleton defense/speed likely percentage modifiers (0.0-1.0 or higher)
