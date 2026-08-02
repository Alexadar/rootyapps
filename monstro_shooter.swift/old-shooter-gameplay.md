# Old Monster Shooter (ActionScript) - Gameplay Math & Parameters

## Hero/Player Movement

**File**: `SimpleHero.as` lines 87-133

### Movement System
- **Base speed**: `speed = exoskeletonVO.speed` (from ExoskeletonVO)
- **Diagonal multiplier**: `0.75` (not normalized!)
- **Per-frame movement**:
  - Cardinal: `x += speed` or `y += speed`
  - Diagonal: `x += speed*0.75`, `y += speed*0.75`
- **Rotation**: `rotation = atan2(mouse.y - hero.y, mouse.x - hero.x) + PI/2`

### Movement Math
```actionscript
// Cardinal
case "top":    y += -speed;
case "bottom": y += speed;
case "left":   x += -speed;
case "right":  x += speed;

// Diagonal (0.75 multiplier)
case "topright":    x += (speed*0.75); y += -(speed*0.75);
case "bottomright": x += (speed*0.75); y += (speed*0.75);
case "topleft":     x += -(speed*0.75); y += -(speed*0.75);
case "bottomleft":  x += -(speed*0.75); y += (speed*0.75);
```

## Exoskeleton System

**File**: `ExoskeletonVO.as`, `BaseHero.as` line 66

### Properties
- `defence: Number` - Absolute damage reduction
- `speed: Number` - Movement speed per frame
- `id: int` - Exoskeleton ID
- `config: ExoskeletonConfigVO` - Visual config

### Damage Calculation
```actionscript
// BaseHero.as line 66
actualDamage = damage - defence <= 0 ? getMinDamage() : damage - defence;
life = life - actualDamage;
```

### Minimum Damage
```actionscript
// Every 4th hit deals 0.4 minimum damage to prevent zero damage
counter++;
if (counter == 4) {
    counter = 0;
    return 0.4;
}
return 0;
```

## Weapon System

**File**: `WeaponVO.as`, `Weapon.as`

### WeaponVO Properties
```actionscript
bulletStartScale: Number = 0.3
bulletMaxScale: Number = 1
bulletScaleFactor: Number = 0.05
damage: Number = 10
shotRange: Number = 350
penetrationPower: Number = 1
shotDelay: Number = 1200        // milliseconds
cageSize: Number = 9            // magazine size
rechargeDelay: Number = 20000   // milliseconds
bulletsCount: Number = 1        // bullets per shot
bulletDeviation: Number = 2     // degrees
bulletMaxDeviation: Number = 2  // degrees
bulletSpeed: Number = 0.175     // per frame at ~60fps
type: Number = 0
bulletType: Number = 0
weaponSound: String = ""
```

### Weapon Firing Logic
```actionscript
// Weapon.as lines 48-68
if (_cageSize > 0) {
    _cageSize--;
    dispatchEventWith(SHOT, {cageSize:_cageSize, data:_data, deviation:_data.bulletDeviation});
}

if (_cageSize == 0) {
    _recharge = true;
    setTimeout(function() {
        _recharge = false;
        _cageSize = _data.cageSize;
    }, _data.rechargeDelay);
}
```

### Fire Rate Control
```actionscript
// Update every frame
if (time - _shotTime > _data.shotDelay && _isShot) {
    shot();
}
```

## Bullet System

**File**: `Bullet.as`, `Game.as` lines 348-357

### Bullet Creation with Deviation
```actionscript
// Game.as - pushBullet method
for (var i:int = 0; i < data.bulletsCount; i++) {
    var bullet:Bullet = new Bullet(data);

    // Create random deviation in polar coordinates
    var deviation:Point = Point.polar(
        currentDeviation * Math.random(),  // radius: 0 to currentDeviation
        Math.PI * Math.random()            // angle: 0 to PI
    );

    // Apply deviation to target point
    dx = (mouse.x + deviation.x) - start.x;
    dy = (mouse.y + deviation.y) - start.y;

    bullet.push(Math.atan2(dy, dx), new Point(start.x, start.y));
}
```

### Bullet Movement
```actionscript
// Bullet.as lines 60-78
push(rotation:Number, start:Point):
    this.start = start;
    x = start.x;
    y = start.y;
    image.rotation = rotation;
    vector = Point.polar(_data.bulletSpeed, rotation);

update():
    x += vector.x;
    y += vector.y;

    if (image.scaleX < _data.bulletMaxScale) {
        image.scaleX += _data.bulletScaleFactor;
    }
```

### Bullet Range Check
```actionscript
// Bullet.as lines 47-57
if (_hit >= _data.penetrationPower || _data.shotRange < Point.distance(start, shotRangePoint)) {
    remove();
    return true;
}
```

### Penetration Logic
```actionscript
// Bullet.as lines 37-44
hit():Boolean {
    _hit++;
    if (_hit <= _data.penetrationPower) {
        return true;  // Continue flying
    }
    return false;     // Destroy bullet
}
```

## Monster System

**File**: `BaseMonster.as`, `MonsterVO.as`

### MonsterVO Properties
```actionscript
hitDistance: int = 0         // Detection range for attacking
kickDistance: int = 0        // Range to deal damage
speed: Number = 34           // Movement speed per frame
turnRate: Number = 34        // Turn speed (steering)
health: Number = 1           // Hit points
bodyRadius: int = 0          // Collision radius
damage: Number = 0           // Damage dealt to player
kickPeriod: int = 0          // Damage interval (milliseconds)
```

### Monster Movement (Steering Behavior)
```actionscript
// BaseMonster.as lines 121-159
doFollow(destination:Point, monsters:Vector.<BaseMonster>):
    speed = _data.speed + _addSpeed;
    distanceX = destination.x - this.x;
    distanceY = destination.y - this.y;

    distanceTotal = sqrt(distanceX*distanceX + distanceY*distanceY);

    // Steering toward target
    moveDistanceX = _data.turnRate * distanceX / distanceTotal;
    moveDistanceY = _data.turnRate * distanceY / distanceTotal;

    _moveX += moveDistanceX;
    _moveY += moveDistanceY;

    // Normalize and apply speed
    totalmove = sqrt(_moveX*_moveX + _moveY*_moveY);
    _moveX = speed * _moveX / totalmove;
    _moveY = speed * _moveY / totalmove;

    x += _moveX;
    y += _moveY;

    rotation = atan2(_moveY, _moveX);
```

### Monster AI Behavior
```actionscript
// BaseMonster.as lines 40-68
update(referencePoint:Point, monsters:Vector.<BaseMonster>):
    distance = sqrt(pow(x-referencePoint.x, 2) + pow(y-referencePoint.y, 2));

    if (distance < _data.kickDistance) {
        onKickDistance();  // Deal damage
        return;
    }

    if (distance < 300) {
        // Direct chase
        doFollow(referencePoint, monsters);
        _destination = null;
    } else {
        // Chase with random deviation (wandering)
        deviation = Point.polar(600 * Math.random(), Math.PI * Math.random());
        _destination = new Point(
            referencePoint.x + deviation.x,
            referencePoint.y + deviation.y
        );
        doFollow(_destination, monsters);
    }
```

### Monster Damage
```actionscript
// BaseMonster.as lines 76-97
setDamageAndIsDead(damage:Number):Boolean {
    live -= damage;

    if (live <= 0) {
        return true;  // Dead
    }
    return false;     // Still alive
}
```

## Key Formulas

### Player Damage Reduction
```
actualDamage = max(damage - defence, minDamage)
minDamage = (hitCount % 4 == 0) ? 0.4 : 0
```

### Bullet Deviation (Polar)
```
deviationPoint = Point.polar(
    currentDeviation * random(0, 1),  // Random radius
    PI * random(0, 1)                 // Random angle (0 to 180°)
)
targetPoint = mousePos + deviationPoint
angle = atan2(targetPoint.y - start.y, targetPoint.x - start.x)
```

### Monster Steering
```
direction = normalize(target - position)
steering = turnRate * direction
velocity += steering
velocity = normalize(velocity) * speed
position += velocity
```

### Diagonal Movement
```
// NOT normalized! Uses 0.75 multiplier instead of 0.707
diagonalSpeed = speed * 0.75
```

## Critical Differences from Standard Game Math

1. **Diagonal movement**: Uses `0.75` instead of `1/sqrt(2)` (0.707)
2. **Bullet deviation**: Polar coordinates (radius + angle), not simple angle offset
3. **Monster AI**: Distance-based behavior switch at 300 units
4. **Damage reduction**: Absolute subtraction, not percentage
5. **Speed units**: Per-frame at ~60fps, not pixels/second
6. **Turn rate**: Separate from speed for steering behavior

## Unit Conversions

**Old (per-frame @ 60fps) → New (per-second)**:
- Speed: `oldSpeed * 60 = newSpeed`
- Example: `0.175 per-frame * 60 = 10.5 pixels/second`

**Old milliseconds → New seconds**:
- Delay: `oldMs / 1000 = newSeconds`
- Example: `1200ms = 1.2 seconds`
