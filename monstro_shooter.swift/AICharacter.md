# AI Character Training System - Technical Specification

**Purpose**: This document contains everything needed to containerize the Monster Shooter game engine for ML model training. It serves as the authoritative reference for implementing an AI agent that can play the game.

---

## Table of Contents

1. [Game Architecture Overview](#1-game-architecture-overview)
2. [Input Abstraction System](#2-input-abstraction-system)
3. [Observation Space](#3-observation-space)
4. [Action Space](#4-action-space)
5. [Reward Function Design](#5-reward-function-design)
6. [Time Warping System](#6-time-warping-system)
7. [Containerization Strategy](#7-containerization-strategy)
8. [Implementation Roadmap](#8-implementation-roadmap)
9. [File Reference](#9-file-reference)

---

## 1. Game Architecture Overview

### Core Game Loop

The game runs on SpriteKit's update cycle at ~60fps. The main loop is in `GameScene+Update.swift:21`:

```
┌─────────────────────────────────────────────────────────────────┐
│                    GameScene.update(currentTime)                 │
├─────────────────────────────────────────────────────────────────┤
│  1. Guard: Skip if isGameOver or isGamePaused                   │
│  2. Calculate deltaTime from lastUpdateTime                      │
│  3. Get input: inputController.movementVector/aimPoint/isShooting│
│  4. Apply player movement (deltaTime-scaled)                     │
│  5. Process aiming and shooting                                  │
│  6. Update weapon (reload progress)                              │
│  7. Update monsters (AI pathfinding toward player)               │
│  8. Update bullets (movement + distance tracking)                │
│  9. Update monster damage (collision detection)                  │
│  10. Process wave spawning (time-based triggers)                 │
│  11. Cleanup expired bullets                                     │
│  12. Update camera (follow player with bounds)                   │
│  13. Check victory/defeat conditions                             │
└─────────────────────────────────────────────────────────────────┘
```

### Entity Hierarchy

```
GameScene (SKScene)
├── renderer: GameRenderer
│   └── world: GameWorld
│       └── worldLayer: SKNode  ← All game entities live here
├── playerEntity: Player
│   ├── sprite: SKSpriteNode
│   ├── health: Int (0-100)
│   ├── speed: CGFloat (300 base)
│   ├── currentWeapon: Weapon
│   ├── defense: Double (armor)
│   └── hitboxRadius: CGFloat
├── monsters: [Monster]
│   ├── sprite: SKSpriteNode
│   ├── health: CGFloat
│   ├── speed: CGFloat (100 base)
│   ├── damage: CGFloat
│   ├── isDead/isDying: Bool
│   └── velocityX/Y: CGFloat (AI steering)
├── bullets: [Bullet]
│   ├── sprite: SKSpriteNode
│   ├── info: BulletInfo (damage, speed, range)
│   ├── hitCount: Int (penetration tracking)
│   └── distanceTraveled: CGFloat
└── inputController: InputController  ← AI INJECTION POINT
```

### Coordinate System

- **Anchor**: Center (0.5, 0.5) - origin at scene center
- **Map bounds**: -mapSize/2 to +mapSize/2 on each axis
- **Default map**: 12000x12000 units
- **Player spawn**: (0, 0) center
- **Monster spawn**: Edge of viewport + 100 unit buffer

### Physics Categories

```swift
struct PhysicsCategory {
    static let player: UInt32 = 1
    static let monster: UInt32 = 2
    static let bullet: UInt32 = 4
}
```

Collisions are contact-based (no physical response). Damage uses distance checks, not physics contacts.

---

## 2. Input Abstraction System

### InputController Protocol

**File**: `monstro_client/Core/GameTypes.swift:17-49`

```swift
protocol InputController {
    /// Returns movement vector with components in range -1..1
    func movementVector() -> CGVector

    /// Returns aim point in world coordinates (nil = use player facing)
    func aimPoint() -> CGPoint?

    /// Returns true when firing action should occur this frame
    func isShooting() -> Bool

    // Optional debug visualization methods (can be no-op for AI)
    func setupDebugVisuals(in scene: SKScene)
    func updateDebugVisuals(movementVector: CGVector, aimPoint: CGPoint?)
    func hideDebugVisuals()
    func showDebugVisuals()
}
```

### External Input Injection

**File**: `monstro_client/Core/GameScene+Core.swift:39`

```swift
var externalInput: InputController?
```

**File**: `monstro_client/UI/GameScene+Input.swift:11-21`

```swift
func setupInput() {
    // External input (AI) overrides platform input
    if let ext = externalInput {
        inputController = ext
    } else {
        #if os(macOS)
        inputController = KeyboardMouseInput()
        #else
        inputController = TouchInput(scene: self)
        #endif
    }
}
```

### Existing Implementations

1. **KeyboardMouseInput** (`Input/KeyboardMouseInput.swift`)
   - Movement: WASD keys (keyCodes 13/0/1/2)
   - Aim: Mouse position in camera-relative coordinates
   - Shoot: Mouse button state

2. **TouchInput** (`Input/TouchInput.swift`)
   - Left zone: Virtual joystick for movement
   - Right zone: Aim direction + auto-fire

### AI Input Implementation Template

```swift
class MLAgentInput: InputController {
    // Action buffer (set by training loop before each step)
    var pendingAction: MLAction?

    // Reference to game state for observation extraction
    weak var gameScene: GameScene?

    func movementVector() -> CGVector {
        guard let action = pendingAction else { return .zero }
        return CGVector(dx: CGFloat(action.moveX), dy: CGFloat(action.moveY))
    }

    func aimPoint() -> CGPoint? {
        guard let action = pendingAction, let player = gameScene?.playerEntity else { return nil }
        // Convert aim angle to world point
        let aimDistance: CGFloat = 500  // Arbitrary distance for aim direction
        let x = player.sprite.position.x + cos(CGFloat(action.aimAngle)) * aimDistance
        let y = player.sprite.position.y + sin(CGFloat(action.aimAngle)) * aimDistance
        return CGPoint(x: x, y: y)
    }

    func isShooting() -> Bool {
        return pendingAction?.shoot ?? false
    }

    // No-op for AI
    func setupDebugVisuals(in scene: SKScene) {}
    func updateDebugVisuals(movementVector: CGVector, aimPoint: CGPoint?) {}
    func hideDebugVisuals() {}
    func showDebugVisuals() {}
}
```

---

## 3. Observation Space

### Complete Game State

The full observable state can be extracted from `GameScene`:

```swift
struct MLObservation: Codable {
    // === PLAYER STATE ===
    let playerX: Float              // Position X (normalized to map)
    let playerY: Float              // Position Y (normalized to map)
    let playerRotation: Float       // Current facing angle (radians)
    let playerHealth: Float         // 0.0 to 1.0 (normalized)
    let playerSpeed: Float          // Current speed value

    // === WEAPON STATE ===
    let currentAmmo: Int            // Bullets in magazine
    let maxAmmo: Int                // Magazine capacity
    let isReloading: Bool           // Currently reloading
    let reloadProgress: Float       // 0.0 to 1.0 if reloading
    let canShoot: Bool              // Fire rate cooldown ready

    // === MONSTERS (sorted by distance, capped) ===
    let monsterCount: Int           // Total alive monsters
    let nearestMonsters: [MonsterObs]  // Up to N nearest monsters

    // === BULLETS (optional, for advanced agents) ===
    let activeBullets: [BulletObs]  // Player's active projectiles

    // === GAME PROGRESS ===
    let elapsedTime: Float          // Seconds since level start
    let killCount: Int              // Monsters killed
    let totalExpectedKills: Int     // Target for victory
    let currentWaveIndex: Int       // Current wave number
    let progressPercent: Float      // killCount / totalExpected

    // === MAP INFO ===
    let mapWidth: Float             // For position normalization
    let mapHeight: Float
}

struct MonsterObs: Codable {
    let dx: Float                   // Relative X (monster.x - player.x)
    let dy: Float                   // Relative Y (monster.y - player.y)
    let distance: Float             // Euclidean distance
    let angle: Float                // Angle from player to monster
    let health: Float               // Monster health (normalized)
    let speed: Float                // Monster speed
    let typeID: Int                 // Monster type for behavior prediction
    let velocityX: Float            // Current movement direction
    let velocityY: Float
}

struct BulletObs: Codable {
    let dx: Float                   // Relative to player
    let dy: Float
    let angle: Float                // Travel direction
    let remainingRange: Float       // Distance left before expiry
}
```

### Observation Extraction

```swift
extension GameScene {
    func extractObservation() -> MLObservation {
        guard let player = playerEntity, let level = currentLevel else {
            fatalError("Cannot extract observation without player/level")
        }

        let mapW = Float(currentMapSize.width)
        let mapH = Float(currentMapSize.height)
        let playerPos = player.sprite.position

        // Sort monsters by distance
        let sortedMonsters = monsters
            .filter { !$0.isDead }
            .map { monster -> (Monster, Float) in
                let dx = Float(monster.sprite.position.x - playerPos.x)
                let dy = Float(monster.sprite.position.y - playerPos.y)
                let dist = sqrt(dx*dx + dy*dy)
                return (monster, dist)
            }
            .sorted { $0.1 < $1.1 }

        // Take nearest N monsters
        let maxMonsters = 20
        let nearestMonsters: [MonsterObs] = sortedMonsters.prefix(maxMonsters).map { (monster, dist) in
            let dx = Float(monster.sprite.position.x - playerPos.x)
            let dy = Float(monster.sprite.position.y - playerPos.y)
            return MonsterObs(
                dx: dx / mapW,  // Normalize
                dy: dy / mapH,
                distance: dist / max(mapW, mapH),
                angle: atan2(dy, dx),
                health: Float(monster.health) / 100.0,  // Assume max 100
                speed: Float(monster.speed),
                typeID: monster.monsterTypeID,
                velocityX: Float(monster.velocityX),
                velocityY: Float(monster.velocityY)
            )
        }

        let weapon = player.currentWeapon
        let expectedTotal = level.spawnWaves.reduce(0) { $0 + $1.monsterCount }

        return MLObservation(
            playerX: Float(playerPos.x) / mapW + 0.5,  // Normalize to 0-1
            playerY: Float(playerPos.y) / mapH + 0.5,
            playerRotation: Float(player.sprite.zRotation),
            playerHealth: Float(player.health) / Float(player.maxHealth),
            playerSpeed: Float(player.speed),
            currentAmmo: weapon.currentAmmo,
            maxAmmo: weapon.config.magazineSize,
            isReloading: weapon.isReloading,
            reloadProgress: Float(weapon.getReloadProgress(currentTime: gameClock.gameTime)),
            canShoot: !weapon.isReloading && weapon.currentAmmo > 0,
            monsterCount: monsters.filter { !$0.isDead }.count,
            nearestMonsters: nearestMonsters,
            activeBullets: [],  // Optional
            elapsedTime: Float(gameClock.gameTime - levelStartTime),
            killCount: killCount,
            totalExpectedKills: expectedTotal,
            currentWaveIndex: currentWaveIndex,
            progressPercent: Float(killCount) / Float(max(1, expectedTotal)),
            mapWidth: mapW,
            mapHeight: mapH
        )
    }
}
```

### Simplified Observation (for faster training)

For initial training, use a flattened vector:

```
[
  player_x, player_y, player_rot, player_health,      // 4
  ammo_ratio, is_reloading, can_shoot,                // 3
  progress_percent, elapsed_time_normalized,          // 2
  monster_0_dx, monster_0_dy, monster_0_dist, ...,    // N * 4
  monster_1_dx, ...
]

Total: ~9 + (N_monsters * 4) floats
With 10 monsters: 49 floats
```

---

## 4. Action Space

### Continuous Action Space (Recommended)

```swift
struct MLAction {
    var moveX: Float      // -1.0 to 1.0 (left/right)
    var moveY: Float      // -1.0 to 1.0 (down/up)
    var aimAngle: Float   // 0 to 2*pi (radians) OR -pi to pi
    var shoot: Bool       // Binary fire trigger
}
```

**Dimensions**: 3 continuous + 1 discrete = Box(3) + Discrete(2)

### Alternative: Discrete Action Space

For simpler RL algorithms (DQN):

```swift
enum DiscreteAction: Int, CaseIterable {
    // Movement (8 directions + stationary)
    case moveNone = 0
    case moveUp, moveUpRight, moveRight, moveDownRight
    case moveDown, moveDownLeft, moveLeft, moveUpLeft

    // Combined with shooting (9 * 2 = 18 actions)
    // Or separate: 9 movement + 8 aim directions + 2 shoot = multi-discrete
}
```

### Action Application

Actions are applied through the `InputController` interface every frame:

```swift
// In MLAgentInput
func setAction(_ action: MLAction) {
    self.pendingAction = action
}

// GameScene.update() calls:
let moveVec = inputController?.movementVector()  // Reads pendingAction.moveX/Y
let aimPt = inputController?.aimPoint()          // Converts aimAngle to world point
let firing = inputController?.isShooting()       // Reads pendingAction.shoot
```

### Action Normalization

Movement is already normalized (-1 to 1). The game applies:
- Speed multiplier: `300 units/sec * exoskeleton.speed`
- Diagonal penalty: `0.75` multiplier when moving diagonally
- Bounds clamping: Player stays within map

---

## 5. Reward Function Design

### Primary Reward Components

```swift
struct RewardCalculator {
    var prevHealth: Int = 100
    var prevKillCount: Int = 0
    var prevTime: TimeInterval = 0

    mutating func calculate(scene: GameScene) -> Float {
        guard let player = scene.playerEntity else { return 0 }

        var reward: Float = 0.0

        // === KILL REWARD (primary objective) ===
        let killDelta = scene.killCount - prevKillCount
        reward += Float(killDelta) * 10.0  // +10 per kill

        // === HEALTH PENALTY ===
        let healthDelta = player.health - prevHealth
        if healthDelta < 0 {
            reward += Float(healthDelta) * 0.1  // -0.1 per HP lost
        }

        // === TIME PRESSURE (small) ===
        let timeDelta = scene.gameClock.gameTime - prevTime
        reward -= Float(timeDelta) * 0.01  // -0.01 per second

        // === TERMINAL REWARDS ===
        if scene.isGameOver {
            if player.health <= 0 {
                reward -= 50.0  // Death penalty
            } else {
                reward += 100.0  // Victory bonus
            }
        }

        // Update state for next calculation
        prevHealth = player.health
        prevKillCount = scene.killCount
        prevTime = scene.gameClock.gameTime

        return reward
    }

    mutating func reset() {
        prevHealth = 100
        prevKillCount = 0
        prevTime = 0
    }
}
```

### Reward Shaping Options

| Component | Value | Purpose |
|-----------|-------|---------|
| Kill | +10.0 | Primary objective |
| Damage taken | -0.1/HP | Survival incentive |
| Time | -0.01/sec | Efficiency (optional) |
| Victory | +100.0 | Episode completion |
| Death | -50.0 | Avoid dying |
| Near miss | +0.1 | Encourage dodging (advanced) |
| Accuracy | +0.5/hit | Shot efficiency (advanced) |
| Ammo waste | -0.01/miss | Conservation (advanced) |

### Sparse vs Dense Rewards

- **Sparse**: Only kill/death/victory rewards. Harder to learn, more stable.
- **Dense**: Add health/time/position rewards. Faster learning, risk of reward hacking.

**Recommendation**: Start with sparse (kills + terminal), add shaping if learning stalls.

---

## 6. Time Warping System

### Problem Statement

The game currently uses **wall-clock time** from SpriteKit's `update(_ currentTime)`. For ML training:
- Need **accelerated time** (10-1000x faster than real-time)
- Need **deterministic stepping** (fixed delta, reproducible)
- Need **step-on-demand** (agent controls time progression)

### Current Time Dependencies

| System | Time Source | Issue |
|--------|-------------|-------|
| Player/Monster/Bullet movement | `deltaTime` | OK (delta-based) |
| Weapon fire rate | `currentTime - lastShotTime` | Uses wall time |
| Weapon reload | `currentTime - reloadStartTime` | Uses wall time |
| Wave spawning | `currentTime - levelStartTime` | Uses wall time |
| Spawn delays | `SKAction.wait(forDuration:)` | Wall time! |
| Damage cooldown | `currentTime - lastDamageTime` | Uses wall time |

### GameClock Design

```swift
/// Virtualized game clock for time warping and deterministic stepping
class GameClock {
    // === STATE ===
    private(set) var gameTime: TimeInterval = 0      // Virtual game time
    private var lastWallTime: TimeInterval = 0       // Last SpriteKit time

    // === CONFIGURATION ===
    var timeScale: Float = 1.0                       // Multiplier (1.0 = normal)
    var stepMode: Bool = false                       // True = manual stepping only
    var fixedDeltaTime: TimeInterval = 1.0 / 60.0    // Step size (16.67ms)

    // === METHODS ===

    /// Called from SpriteKit update() - advances game time based on wall time
    /// Returns the scaled delta time for this frame
    func tick(wallTime: TimeInterval) -> TimeInterval {
        // In step mode, don't auto-advance
        if stepMode { return 0 }

        // Calculate wall delta
        let wallDelta: TimeInterval
        if lastWallTime > 0 {
            wallDelta = wallTime - lastWallTime
        } else {
            wallDelta = 0
        }
        lastWallTime = wallTime

        // Apply time scale
        let gameDelta = wallDelta * TimeInterval(timeScale)
        gameTime += gameDelta

        return gameDelta
    }

    /// Manual step for ML training - advances exactly one fixed timestep
    /// Returns the fixed delta time
    func step() -> TimeInterval {
        gameTime += fixedDeltaTime
        return fixedDeltaTime
    }

    /// Reset clock to zero
    func reset() {
        gameTime = 0
        lastWallTime = 0
    }
}
```

### Operating Modes

| Mode | timeScale | stepMode | Use Case |
|------|-----------|----------|----------|
| Normal Play | 1.0 | false | Human gameplay |
| Slow Motion | 0.25-0.5 | false | Debug, replay |
| Fast Forward | 2.0-4.0 | false | Skip, visualization |
| ML Training | N/A | true | Agent-controlled steps |
| Paused | 0.0 | false | Menu, UI |

### Refactoring Requirements

#### Replace SKAction.wait for spawning

**Before** (`GameScene+Monsters.swift:107-123`):
```swift
for i in 0..<wave.monsterCount {
    let delay = TimeInterval(i) * wave.spawnInterval
    let spawnAction = SKAction.sequence([
        SKAction.wait(forDuration: delay),  // WALL TIME!
        SKAction.run { self.spawnMonster() }
    ])
    run(spawnAction)
}
```

**After**:
```swift
// Pending spawn queue
struct PendingSpawn {
    let triggerGameTime: TimeInterval
    let monsterTypeID: Int
}
var pendingSpawns: [PendingSpawn] = []

// Queue spawns when wave triggers
private func queueWaveSpawns(_ wave: SpawnWave, waveIndex: Int) {
    let baseTime = gameClock.gameTime
    for i in 0..<wave.monsterCount {
        let delay = TimeInterval(i) * wave.spawnInterval
        let typeID = wave.monsterTypeIDs.randomElement()!
        pendingSpawns.append(PendingSpawn(
            triggerGameTime: baseTime + delay,
            monsterTypeID: typeID
        ))
    }
    // Sort by trigger time
    pendingSpawns.sort { $0.triggerGameTime < $1.triggerGameTime }
}

// Process in update loop
func processPendingSpawns() {
    while let spawn = pendingSpawns.first,
          spawn.triggerGameTime <= gameClock.gameTime {
        spawnMonster(monsterTypeID: spawn.monsterTypeID)
        pendingSpawns.removeFirst()
    }
}
```

#### Convert absolute time checks to game time

All `currentTime` references must become `gameClock.gameTime`:

```swift
// Weapon.swift
func fire(at gameTime: TimeInterval, ...) { ... }
func update(gameTime: TimeInterval) { ... }

// GameScene+Monsters.swift
func updateMonsterDamage(gameTime: TimeInterval) { ... }

// GameScene+Update.swift
let gameTime = gameClock.gameTime
processWaveSpawning(gameTime: gameTime)
updateMonsterDamage(gameTime: gameTime)
```

### Determinism for Reproducible Training

| Requirement | Current | Fix |
|-------------|---------|-----|
| Fixed timestep | Variable fps | Use `fixedDeltaTime = 1/60` |
| Seeded RNG | `Int.random()` | Inject `SeededRandomGenerator` |
| No wall-time | Multiple places | Use `gameClock.gameTime` |
| No SKAction timing | Wave spawning | Use pending queue |

```swift
// Seeded random for determinism
class SeededRandom {
    private var state: UInt64

    init(seed: UInt64) {
        self.state = seed
    }

    func next() -> UInt64 {
        // xorshift64
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }

    func nextFloat() -> Float {
        return Float(next() & 0xFFFFFF) / Float(0xFFFFFF)
    }

    func nextInt(in range: Range<Int>) -> Int {
        let span = UInt64(range.upperBound - range.lowerBound)
        return range.lowerBound + Int(next() % span)
    }
}
```

---

## 7. Containerization Strategy

### Option A: Swift-Native Training (Recommended for macOS)

```
┌─────────────────────────────────────────────────────────────────┐
│  Swift Training Package                                          │
├─────────────────────────────────────────────────────────────────┤
│  MLEnvironment                                                   │
│    ├── HeadlessGameEngine (no SKView)                           │
│    ├── GameClock (step mode)                                    │
│    ├── MLAgentInput (InputController)                           │
│    ├── ObservationEncoder                                       │
│    └── RewardCalculator                                         │
├─────────────────────────────────────────────────────────────────┤
│  Training Loop                                                   │
│    ├── PPO/SAC implementation (or ONNX Runtime)                 │
│    ├── Vectorized environments (N parallel games)               │
│    └── Checkpointing + logging                                  │
└─────────────────────────────────────────────────────────────────┘
```

**Pros**: Native performance, no IPC, direct memory access
**Cons**: Limited ML ecosystem in Swift

### Option B: Python Bridge via gRPC

```
┌──────────────────┐                    ┌─────────────────────┐
│  Python Client   │      gRPC/TCP      │  Swift Game Server  │
│  (PyTorch, SB3)  │ ←────────────────→ │  (Headless Engine)  │
└──────────────────┘   reset/step/obs   └─────────────────────┘
```

**Protocol**:
```protobuf
service GameEnvironment {
    rpc Reset(ResetRequest) returns (Observation);
    rpc Step(Action) returns (StepResult);
    rpc GetState(Empty) returns (GameState);
    rpc Configure(EnvConfig) returns (Status);
}

message Action {
    float move_x = 1;
    float move_y = 2;
    float aim_angle = 3;
    bool shoot = 4;
}

message StepResult {
    Observation observation = 1;
    float reward = 2;
    bool done = 3;
    bool truncated = 4;
    map<string, string> info = 5;
}
```

**Pros**: Full Python ML ecosystem (stable-baselines3, RLlib, cleanrl)
**Cons**: IPC latency (~1ms per step), serialization overhead

### Option C: Shared Memory + Direct Call

```
┌─────────────────────────────────────────────────────────────────┐
│  Python Process                                                  │
│    ├── Load Swift dylib via ctypes/cffi                         │
│    ├── Shared memory for observations (mmap)                    │
│    └── Direct C function calls for step/reset                   │
└─────────────────────────────────────────────────────────────────┘
```

**Pros**: Near-native speed, full Python ecosystem
**Cons**: Complex FFI, memory management

### Recommended: Option B (gRPC) for Initial Implementation

1. Simpler to implement and debug
2. Clean separation of concerns
3. Can optimize to Option C later if needed
4. ~10k steps/sec achievable (sufficient for training)

### Docker Setup

```dockerfile
# Dockerfile.game-server
FROM swift:5.9-jammy

# Install dependencies
RUN apt-get update && apt-get install -y \
    libgrpc-dev \
    protobuf-compiler-grpc

# Copy game code
WORKDIR /app
COPY monstro_client/ ./monstro_client/
COPY MLTraining/ ./MLTraining/

# Build headless server
RUN swift build -c release --product MLGameServer

EXPOSE 50051
CMD ["./build/release/MLGameServer"]
```

```dockerfile
# Dockerfile.trainer
FROM python:3.11-slim

RUN pip install \
    stable-baselines3 \
    grpcio \
    tensorboard \
    numpy

COPY training/ /app/training/
WORKDIR /app

CMD ["python", "train.py"]
```

```yaml
# docker-compose.yml
version: '3.8'
services:
  game-server:
    build:
      dockerfile: Dockerfile.game-server
    ports:
      - "50051:50051"
    deploy:
      replicas: 8  # 8 parallel environments

  trainer:
    build:
      dockerfile: Dockerfile.trainer
    depends_on:
      - game-server
    environment:
      - GAME_SERVER_ADDR=game-server:50051
      - NUM_ENVS=8
    volumes:
      - ./checkpoints:/app/checkpoints
      - ./logs:/app/logs
```

---

## 8. Implementation Roadmap

### Phase 1: GameClock + Time Warp (Foundation)

**Files to create/modify**:
```
NEW:  monstro_client/Core/GameClock.swift
MOD:  monstro_client/Core/GameScene+Core.swift     (add gameClock property)
MOD:  monstro_client/Core/GameScene+Update.swift   (use gameTime)
MOD:  monstro_client/Core/GameScene+Monsters.swift (pending spawn queue)
MOD:  monstro_client/Entities/Weapon.swift         (use gameTime)
```

**Deliverable**: Game runs with `timeScale` control, step mode works.

### Phase 2: ML Interface Layer

**Files to create**:
```
NEW:  MLTraining/MLAgentInput.swift       (InputController for AI)
NEW:  MLTraining/MLObservation.swift      (State encoder)
NEW:  MLTraining/MLAction.swift           (Action decoder)
NEW:  MLTraining/MLReward.swift           (Reward calculator)
NEW:  MLTraining/MLEnvironment.swift      (Gym-like wrapper)
```

**Deliverable**: Can call `env.reset()` and `env.step(action)` from Swift.

### Phase 3: Headless Engine

**Files to create/modify**:
```
NEW:  MLTraining/HeadlessGameScene.swift  (GameScene without rendering)
MOD:  Remove SKView dependencies where possible
MOD:  Disable audio in training mode
```

**Deliverable**: Game logic runs without GPU/display.

### Phase 4: Training Infrastructure

**Files to create**:
```
NEW:  MLTraining/Server/grpc_server.swift (gRPC endpoint)
NEW:  training/train.py                   (Python training script)
NEW:  training/env_wrapper.py             (Gymnasium wrapper)
NEW:  Dockerfile.game-server
NEW:  Dockerfile.trainer
NEW:  docker-compose.yml
```

**Deliverable**: End-to-end training pipeline.

### Phase 5: CoreML Export (Optional)

Export trained model to CoreML for on-device inference:
```swift
let model = try MLModel(contentsOf: modelURL)
let input = MLAgentInput(observation: obs)
let output = try model.prediction(from: input)
```

---

## 9. File Reference

### Core Game Files

| File | Purpose | ML Relevance |
|------|---------|--------------|
| `Core/GameScene+Core.swift` | Main scene, properties | Add `gameClock`, `externalInput` |
| `Core/GameScene+Update.swift` | Game loop | Convert to `gameTime` |
| `Core/GameScene+Monsters.swift` | Spawning, AI, damage | Remove SKAction timing |
| `Core/GameTypes.swift` | `InputController` protocol | AI implements this |
| `Core/SavedGameState.swift` | State serialization | Reference for observation |

### Entity Files

| File | Purpose | ML Relevance |
|------|---------|--------------|
| `Entities/Player.swift` | Player state/movement | Observation source |
| `Entities/Monster.swift` | Monster AI/state | Observation source |
| `Entities/Bullet.swift` | Projectile tracking | Observation source |
| `Entities/Weapon.swift` | Fire rate, reload | Convert to `gameTime` |
| `Entities/GameLevel.swift` | Wave definitions | Victory condition |

### Input Files

| File | Purpose | ML Relevance |
|------|---------|--------------|
| `Input/KeyboardMouseInput.swift` | macOS input | Reference implementation |
| `Input/TouchInput.swift` | iOS input | Reference implementation |

### Key Constants

| Constant | Value | File |
|----------|-------|------|
| `playerSpeed` | 300 | `GameConstants.swift` |
| `monsterSpeed` | 100 | `GameConstants.swift` |
| `bulletSpeed` | 800 | `WeaponConfig` |
| `mapSize` | 12000x12000 | `GameLevel` |
| `cameraScale` | 0.7 (macOS) | `GameConstants.swift` |
| `damageInterval` | 1.0 sec | `GameScene+Core.swift` |

---

## Appendix: Quick Start Checklist

When implementing ML training:

- [ ] Create `GameClock.swift` with `gameTime`, `timeScale`, `stepMode`
- [ ] Add `var gameClock = GameClock()` to `GameScene`
- [ ] Replace all `currentTime` with `gameClock.gameTime`
- [ ] Replace `SKAction.wait` spawning with pending queue
- [ ] Implement `MLAgentInput: InputController`
- [ ] Implement `MLObservation` extraction
- [ ] Implement `RewardCalculator`
- [ ] Create `MLEnvironment` with `reset()`/`step()` API
- [ ] Add gRPC server for Python interop
- [ ] Create Dockerfiles for training
- [ ] Test determinism with fixed seed

---

*Last updated: Session analyzing game architecture for ML containerization*
