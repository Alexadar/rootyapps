# Equipment Data Extraction Summary

## Extraction Date
October 27, 2025

## Source
Extracted from Monster Shooter old_shooter C# server code and ActionScript client code.

## Findings

### 1. Equipment System Architecture

The old game used a complex item system with:

**Base Class**: `ItemType`
- Located: `Bdgilka.GameServer.MonstroShooter.Model.Entities.Market.ItemType.cs`
- All items inherit from this base class
- Contains common properties: id, name, description, prices, requirements

**Main Equipment Classes**:
1. **Weapon** (`ItemTypes/Weapon.cs`)
   - 29 specific properties for combat mechanics
   - Includes damage, fire rate, magazine, bullet behavior

2. **Exoskeleton** (`ItemTypes/Exoskeleton.cs`)
   - Armor/suit system
   - Properties: defence (damage reduction), speed (movement modifier)

3. **Tool** (consumables)
   - Mine, Artillery, ExplosionBelt

4. **Booster** (temporary buffs)
5. **Cosmetics** (visual items)

### 2. Database Integration

**Stored Procedure**: `GetItemTypes(@Culture nvarchar(10))`
- Returns all items with localization
- Item-specific data stored as XML in `Data` column
- Server deserializes XML into typed objects at runtime

**File Locations**:
- Server: `/old_shooter/src/trunk/SourceFiles/Server/GameServer/Bdgilka.GameServer.MonstroShooter.Model/`
- Client: `/old_shooter/src/trunk/SourceFiles/Client/MonsterShooterApplication/Game/src/com/monstershooter/model/vo/`

### 3. Key Weapon Properties Extracted

From `Weapon.cs`:
```csharp
public class Weapon : ItemType {
    public double Damage { get; set; }
    public int ShotRange { get; set; }
    public int ShotDelay { get; set; }              // milliseconds
    public int CageSize { get; set; }                // magazine size
    public int RechargeDelay { get; set; }           // reload time
    public int BulletsCount { get; set; }            // bullets per shot
    public double BulletSpeed { get; set; }
    public int BulletDeviation { get; set; }         // spread angle
    public int BulletMaxDeviation { get; set; }
    public int PenetrationPower { get; set; }        // piercing
    public WeaponType Type { get; set; }             // enum: 1-4
    public double BulletStartScale { get; set; }
    public double BulletMaxScale { get; set; }
    public double BulletScaleFactor { get; set; }
    public string WeaponSound { get; set; }
}
```

### 4. Key Exoskeleton Properties Extracted

From `Exoskeleton.cs`:
```csharp
public class Exoskeleton : ItemType {
    public double Defence { get; set; }          // damage reduction
    public double Speed { get; set; }            // movement modifier
    public GraphicResource LobbyResource { get; set; }
    public GraphicResource GameResource { get; set; }
}
```

### 5. Weapon Types

From analysis:
- **Type 1**: Pistol - Single shot, balanced
- **Type 2**: Dual Pistols - Two bullets, fast fire
- **Type 3**: Rifle - High precision, fast rate, good range
- **Type 4**: Minigun - Very fast, lower damage, spray pattern

### 6. Game Mechanics Insights

**Weapon Firing** (from ActionScript client `Weapon.as`):
1. Fire every `shotDelay` milliseconds
2. Create `bulletsCount` bullets per shot
3. Each bullet gets random deviation angle
4. Bullet travels at `bulletSpeed` pixels/frame
5. Bullet grows from `bulletStartScale` to `bulletMaxScale`
6. Hits up to `penetrationPower` enemies
7. Max range is `shotRange` pixels
8. After `cageSize` shots, reload for `rechargeDelay` ms

**Exoskeleton Effects**:
- `defence`: Reduces incoming damage (percentage 0.0-1.0 likely)
- `speed`: Modifies movement speed (1.0 = normal, higher = faster)
- Trade-off: Heavy armor = more defense but slower

### 7. Missing Data

Could not extract from database files:
- Actual item names from production database (SQL Server .mdf files not accessible)
- Exact numeric values for all items
- Localized descriptions
- Pricing information
- Level/rank requirements

### 8. Created Files

1. **README.md** - Complete equipment system documentation
2. **weapon_schema.json** - JSON schema for weapon data structure
3. **exoskeleton_schema.json** - JSON schema for exoskeleton data
4. **weapons_example.json** - Example weapons with balanced stats
5. **exoskeletons_example.json** - Example exoskeletons with varied stats

### 9. Recommendations for Swift Implementation

1. **Use the example JSON files** as a starting point
2. **Convert units**:
   - ActionScript `bulletSpeed` was pixels-per-frame at 60fps
   - Convert to absolute velocity for SpriteKit
3. **Balance adjustments**:
   - Original values may need tweaking for Swift version
   - Test and iterate on damage/speed/range values
4. **Implement exoskeleton visual system**:
   - Different sprites for each armor type
   - Smooth transitions when equipping
5. **Add to current WeaponConfig**:
   - Expand existing WeaponConfig.swift
   - Add ExoskeletonConfig.swift with similar pattern

### 10. Next Steps

To implement equipment system:
1. Create `ExoskeletonConfig.swift` similar to `WeaponConfig.swift`
2. Expand `weapons_example.json` with more weapon types
3. Add equipment selection UI (similar to map/weapon selector)
4. Implement equip/unequip functionality
5. Apply exoskeleton defense/speed modifiers in game
6. Add market/shop UI for purchasing equipment
