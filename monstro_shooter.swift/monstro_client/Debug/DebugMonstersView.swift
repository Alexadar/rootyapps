import SwiftUI
import SpriteKit
import Combine

/// Debug view: Display all monsters in a 5x4 grid with animation controls
struct DebugMonstersView: View {
    let onBack: () -> Void
    @StateObject private var stateMachine = DebugMonstersAnimStateMachine()
    @State private var monsterConfigs: [MonsterConfig] = []

    let columns = 5
    let rows = 4
    let padding: CGFloat = 10

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black.ignoresSafeArea()

                VStack(spacing: 20) {
                    // Back button + Title
                    HStack {
                        DebugBackButton(action: onBack)
                        Spacer()
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 20)

                    Text("DEBUG: MONSTERS")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(.white)

                    // Monster grid
                    if !monsterConfigs.isEmpty {
                        let itemWidth = (geometry.size.width - CGFloat(columns + 1) * padding) / CGFloat(columns) / 2
                        let itemHeight = itemWidth // Square cells

                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: padding), count: columns), spacing: padding) {
                            ForEach(Array(monsterConfigs.prefix(20).enumerated()), id: \.offset) { index, config in
                                MonsterPreviewCell(
                                    config: config,
                                    stateMachine: stateMachine,
                                    size: CGSize(width: itemWidth, height: itemHeight)
                                )
                            }
                        }
                        .padding(.horizontal, padding)
                    } else {
                        Text("No monsters loaded")
                            .foregroundColor(.gray)
                    }

                    Spacer()

                    // Control buttons
                    HStack(spacing: 20) {
                        Button(action: {
                            stateMachine.trigger(.stay)
                        }) {
                            Text("STAY")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundColor(.white)
                                .frame(width: 120, height: 50)
                                .background(stateMachine.currentState == .stay ? Color.green : Color.gray)
                                .cornerRadius(8)
                        }
                        .buttonStyle(.plain)

                        Button(action: {
                            stateMachine.trigger(.go)
                        }) {
                            Text("GO")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundColor(.white)
                                .frame(width: 120, height: 50)
                                .background(stateMachine.currentState == .go ? Color.blue : Color.gray)
                                .cornerRadius(8)
                        }
                        .buttonStyle(.plain)

                        Button(action: {
                            stateMachine.trigger(.death)
                        }) {
                            Text("DEATH ANIM")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundColor(.white)
                                .frame(width: 150, height: 50)
                                .background(stateMachine.currentState == .death ? Color.red : Color.gray)
                                .cornerRadius(8)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.bottom, 40)
                }
            }
        }
        .onAppear {
            loadMonsters()
        }
    }

    private func loadMonsters() {
        let monsterTypes = GameConstants.MonsterType.allCases
        var configs: [MonsterConfig] = []

        for monsterType in monsterTypes {
            if let config = MonsterRegistry.shared.getConfig(forID: monsterType.rawValue) {
                configs.append(config)
            }
        }

        monsterConfigs = configs
    }
}

/// Single monster preview cell with SpriteKit scene
struct MonsterPreviewCell: View {
    let config: MonsterConfig
    @ObservedObject var stateMachine: DebugMonstersAnimStateMachine
    let size: CGSize

    var body: some View {
        ZStack {
            Color.black

            MonsterSpriteView(
                config: config,
                stateMachine: stateMachine,
                size: size
            )
            .frame(width: size.width, height: size.height)

            // Monster type label
            VStack {
                Spacer()
                VStack(spacing: 2) {
                    Text("ID: \(config.monsterTypeID)")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(.white)
                    Text(config.name)
                        .font(.system(size: 8, weight: .regular))
                        .foregroundColor(.gray)
                }
                .padding(4)
                .background(Color.black.opacity(0.7))
                .cornerRadius(4)
                .padding(4)
            }
        }
        .frame(width: size.width, height: size.height)
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.white.opacity(0.3), lineWidth: 1)
        )
    }
}

/// SpriteKit scene wrapper for displaying animated monster
struct MonsterSpriteView: View {
    let config: MonsterConfig
    @ObservedObject var stateMachine: DebugMonstersAnimStateMachine
    let size: CGSize
    @StateObject private var sceneHolder = MonsterSceneHolder()

    var body: some View {
        ZStack {
            Color.black

            if let scene = sceneHolder.scene {
                SpriteView(scene: scene)
                    .frame(width: size.width, height: size.height)
            }
        }
        .onAppear {
            sceneHolder.setup(size: size, config: config, state: stateMachine.currentState)
        }
        .onChange(of: stateMachine.currentState) { _, newState in
            sceneHolder.updateState(newState)
        }
    }
}

// MARK: - Scene Holder
class MonsterSceneHolder: ObservableObject {
    @Published var scene: MonsterPreviewScene?

    func setup(size: CGSize, config: MonsterConfig, state: DebugMonstersAnimStateMachine.State) {
        scene = MonsterPreviewScene(size: size, monster: config, animState: state)
    }

    func updateState(_ newState: DebugMonstersAnimStateMachine.State) {
        scene?.updateAnimationState(newState)
    }
}

// MARK: - Monster Preview Scene with Movement
class MonsterPreviewScene: SKScene {
    var monster: Monster
    var monsterConfig: MonsterConfig
    var animState: DebugMonstersAnimStateMachine.State
    var lastUpdateTime: TimeInterval = 0
    var elapsedTime: TimeInterval = 0
    var startPosition: CGPoint
    var targetPosition: CGPoint

    init(size: CGSize, monster: MonsterConfig, animState: DebugMonstersAnimStateMachine.State) {
        self.animState = animState
        self.monsterConfig = monster
        self.monster = Monster(config: monster)

        // Positions
        let centerPos = CGPoint(x: size.width / 2, y: size.height / 2)
        let bottomPos = CGPoint(x: size.width / 2, y: size.height * 0.2)
        let topPos = CGPoint(x: size.width / 2, y: size.height * 0.8)

        // Choose positions based on state
        if animState == .go {
            self.startPosition = bottomPos
            self.targetPosition = topPos
        } else {
            // stay or death - center
            self.startPosition = centerPos
            self.targetPosition = centerPos
        }

        super.init(size: size)

        backgroundColor = .black
        scaleMode = .aspectFit

        print("[MonsterPreviewScene] Init with state: \(animState), start: \(startPosition), target: \(targetPosition)")

        // Setup monster
        self.monster.setup(at: startPosition, targetPosition: targetPosition)
        self.monster.sprite?.physicsBody = nil

        if let sprite = self.monster.sprite {
            addChild(sprite)
            print("[MonsterPreviewScene] Added sprite at position: \(sprite.position)")
        }

        // Trigger death animation if needed
        if animState == .death {
            print("[MonsterPreviewScene] Triggering death animation")
            self.monster.die()
        }
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) not implemented")
    }

    override func update(_ currentTime: TimeInterval) {
        let deltaTime = lastUpdateTime == 0 ? 0 : currentTime - lastUpdateTime
        lastUpdateTime = currentTime

        guard deltaTime > 0 else { return }

        elapsedTime += deltaTime

        // Update monster movement if in "go" state
        if animState == .go && !monster.isDead {
            // Loop every 5 seconds: reset to start position
            if elapsedTime >= 5.0 {
                print("[MonsterPreviewScene] Resetting position after 5s")
                monster.sprite?.position = startPosition
                elapsedTime = 0
            }

            monster.update(deltaTime: deltaTime, playerPosition: targetPosition, playerHitboxRadius: 10)
        }
    }

    override func didMove(to view: SKView) {
        super.didMove(to: view)
        print("[MonsterPreviewScene] didMove to view, state: \(animState)")
    }

    func updateAnimationState(_ newState: DebugMonstersAnimStateMachine.State) {
        print("[MonsterPreviewScene] updateAnimationState from \(animState) to \(newState)")

        // If coming from death state, need to recreate monster
        if animState == .death && newState != .death {
            monster.sprite?.removeFromParent()
            let newMonster = Monster(config: monsterConfig)

            let centerPos = CGPoint(x: size.width / 2, y: size.height / 2)
            let bottomPos = CGPoint(x: size.width / 2, y: size.height * 0.2)
            let topPos = CGPoint(x: size.width / 2, y: size.height * 0.8)

            if newState == .go {
                startPosition = bottomPos
                targetPosition = topPos
                newMonster.setup(at: startPosition, targetPosition: targetPosition)
            } else {
                startPosition = centerPos
                targetPosition = centerPos
                newMonster.setup(at: centerPos, targetPosition: centerPos)
            }

            newMonster.sprite?.physicsBody = nil
            if let sprite = newMonster.sprite {
                addChild(sprite)
            }

            self.monster = newMonster
            animState = newState
            elapsedTime = 0
            return
        }

        animState = newState
        elapsedTime = 0

        let centerPos = CGPoint(x: size.width / 2, y: size.height / 2)
        let bottomPos = CGPoint(x: size.width / 2, y: size.height * 0.2)
        let topPos = CGPoint(x: size.width / 2, y: size.height * 0.8)

        if newState == .go {
            startPosition = bottomPos
            targetPosition = topPos
            monster.sprite?.position = startPosition
        } else {
            startPosition = centerPos
            targetPosition = centerPos
            monster.sprite?.position = centerPos

            if newState == .death {
                monster.die()
            }
        }
    }
}

// MARK: - Monster Animation State Machine
class DebugMonstersAnimStateMachine: ObservableObject {
    enum State {
        case stay
        case go
        case death
    }

    @Published private(set) var currentState: State = .stay
    @Published private(set) var sceneVersion: Int = 0

    func trigger(_ newState: State) {
        print("[StateMachine] trigger(\(newState)) from current state: \(currentState)")

        // Direct transition
        currentState = newState
        sceneVersion += 1

        print("[StateMachine] State changed to: \(currentState), version: \(sceneVersion)")
    }
}

// MARK: - GameConstants.MonsterType CaseIterable extension
extension GameConstants.MonsterType: CaseIterable {
    static var allCases: [GameConstants.MonsterType] {
        return [
            .bug, .berserker, .bird, .bug2, .bird2, .bug3, .berserker2, .bird3,
            .walker3, .bug4, .bird4, .walker4, .bug5, .bird5, .walker, .berserker4,
            .bug6, .walker6, .walker2, .berserker6, .bird6
        ]
    }
}
