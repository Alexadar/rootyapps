//
//  GameView.swift
//  froggo.swift
//
//  Created by Oleksandr Koreniuk on 19.09.2025.
//

import SwiftUI
import SpriteKit

// Helper class to hold and persist the GameScene
class GameSceneHolder {
    let scene: GameScene

    init(gameStateBinding: Binding<GameState>, finalScoreBinding: Binding<Int>) {
        let scene = GameScene()
        scene.size = CGSize(width: 800, height: 600)
        scene.scaleMode = .aspectFill
        scene.gameStateBinding = gameStateBinding
        scene.finalScoreBinding = finalScoreBinding
        self.scene = scene
    }
}

struct GameView: View {
    @Binding var gameState: GameState
    @Binding var finalScore: Int
    @State private var score: Int = 0
    @State private var tutorialText: String = "Slide down and sideways to help Freddy jump"
    @State private var sceneHolder: GameSceneHolder

    init(gameState: Binding<GameState>, finalScore: Binding<Int>) {
        _gameState = gameState
        _finalScore = finalScore
        _sceneHolder = State(wrappedValue: GameSceneHolder(gameStateBinding: gameState, finalScoreBinding: finalScore))
    }

    var body: some View {
        ZStack {
            SpriteView(scene: sceneHolder.scene)
                .ignoresSafeArea()

            // SwiftUI overlay for score and tutorial (like MainMenuView title)
            VStack {
                HStack(alignment: .top, spacing: 20) {
                    // Tutorial text - left side with padding
                    Text(tutorialText)
                        .font(.system(size: 18, weight: .regular, design: .default))
                        .foregroundColor(.white)
                        .shadow(color: .black.opacity(0.8), radius: 3, x: 2, y: 2)
                        .multilineTextAlignment(.center)
                        .padding(.leading, 20)
                        .frame(maxWidth: .infinity)

                    // Score - right aligned
                    Text("\(score)")
                        .font(.system(size: 28, weight: .bold, design: .default))
                        .foregroundColor(.white)
                        .shadow(color: .black.opacity(0.8), radius: 3, x: 2, y: 2)
                        .padding(.trailing, 20)
                }
                .padding(.top, 50)

                Spacer()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("UpdateScore"))) { notification in
            if let newScore = notification.object as? Int {
                score = newScore
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("UpdateTutorial"))) { notification in
            if let text = notification.object as? String {
                tutorialText = text
            }
        }
        .onAppear {
            // Initialize tutorial text
            tutorialText = "Slide down and sideways to help Freddy jump"
        }
    }
}

class GameScene: SKScene {
    // Game entities
    var frog: Frog!
    var fly: Fly!
    var gameManager: GameManager!
    var skyscrapers: [Skyscraper] = []
    
    // Game state
    var isGameOver = false
    var score = 0 {
        didSet {
            // Post notification to update SwiftUI overlay
            NotificationCenter.default.post(name: NSNotification.Name("UpdateScore"), object: score)
        }
    }
    var gameCamera: SKCameraNode!

    // Tutorial text property
    var tutorialText: String = "" {
        didSet {
            // Post notification to update SwiftUI overlay
            NotificationCenter.default.post(name: NSNotification.Name("UpdateTutorial"), object: tutorialText)
        }
    }
    private var bgNodes: [SKSpriteNode] = []
    
    // Bindings for SwiftUI integration
    var gameStateBinding: Binding<GameState>?
    var finalScoreBinding: Binding<Int>?
    
    // Constants (matched to Unity)
    let pitHeight: CGFloat = 600 // Unity uses -10
    let initialSkyscrapers = 20
    private let bgTileWidth: CGFloat = 512 // approximate; will be set from texture size
    private let bgZ: CGFloat = -10
    private let cameraSmoothing: CGFloat = 0.15 // Lower = smoother, higher = more responsive (0.1-0.3 range)
    
    override func didMove(to view: SKView) {
        setupScene()
        setupCamera()
        setupBackground()
        setupGame()
    }
    
    private func setupScene() {
        backgroundColor = SKColor.black
        // Physics world gravity will be set after gameManager is initialized
        physicsWorld.contactDelegate = self
    }
    
    private func setupCamera() {
        gameCamera = SKCameraNode()
        addChild(gameCamera)
        self.camera = gameCamera
    }
    

    private func setupBackground() {
        // Create horizontally tiling background similar to Unity scene
        let texture = SKTexture(imageNamed: "NightSky")
        guard texture.size() != .zero else { return }

        // Determine number of tiles to cover view width x2
        let worldHeight = size.height
        let scale = worldHeight / texture.size().height
        let tileWidth = texture.size().width * scale

        let tilesNeeded = Int(ceil((size.width * 2) / tileWidth)) + 2
        var totalWidth: CGFloat = 0

        for i in 0..<tilesNeeded {
            let node = SKSpriteNode(texture: texture)
            node.setScale(scale)
            node.anchorPoint = CGPoint(x: 0.5, y: 0.5)
            node.zPosition = bgZ
            addChild(node)
            bgNodes.append(node)
            node.position = CGPoint(x: CGFloat(i) * tileWidth - size.width, y: 0)
            totalWidth += tileWidth
        }
    }
    
    private func setupGame() {
        gameManager = GameManager(scene: self)

        // Set physics world gravity from GameManager
        physicsWorld.gravity = CGVector(dx: 0, dy: gameManager.gravitation)

        // Create frog and pass gameManager reference
        frog = Frog(gameManager: gameManager)
        frog.position = CGPoint(x: 0, y: 100)
        addChild(frog)

        // Add trajectory line to scene above everything
        if let trajectoryLine = frog.trajectoryLine, trajectoryLine.parent == nil {
            addChild(trajectoryLine)
        }

        // Create fly
        fly = Fly()
        fly.gameScene = self
        addChild(fly)

        gameManager.generateInitialCity()
        focusOnFrog()

        // Play background music and spawn sound (like Unity's Game.cs Awake)
        SoundManager.shared.playBackgroundMusic()
        SoundManager.shared.playSpawnSound()
    }
    
    func focusOnFrog() {
        guard let camera = camera else { return }

        // Smooth camera movement using linear interpolation (lerp)
        // This prevents flickering/jittering at high speeds
        let targetX = frog.position.x
        let targetY = frog.position.y

        // Interpolate camera position for smooth following
        let newX = camera.position.x + (targetX - camera.position.x) * cameraSmoothing
        let newY = camera.position.y + (targetY - camera.position.y) * cameraSmoothing

        camera.position = CGPoint(x: newX, y: newY)

        updateBackground()
    }
    

    private func updateBackground() {
        guard let camera = camera, let first = bgNodes.first, let texture = first.texture else { return }
        let worldHeight = size.height
        let scale = worldHeight / texture.size().height
        let tileWidth = texture.size().width * scale

        // Keep backgrounds centered vertically on camera
        for node in bgNodes { node.position.y = camera.position.y }

        // Reposition nodes when camera moves right
    let leftEdge = camera.position.x - size.width / 2

        // If leftmost tile entirely left of view, move it to the right end
        if let firstNode = bgNodes.first, firstNode.position.x + tileWidth / 2 < leftEdge {
            if let lastNode = bgNodes.last {
                firstNode.position.x = lastNode.position.x + tileWidth
                bgNodes.removeFirst()
                bgNodes.append(firstNode)
            }
        }
    }
    
    func gameOver() {
        guard !isGameOver else { return }
        isGameOver = true

        // Stop frog physics
        frog.physicsBody?.velocity = CGVector.zero
        frog.physicsBody?.affectedByGravity = false

        // Update final score and transition to game over screen
        finalScoreBinding?.wrappedValue = score
        SoundManager.shared.playGameOverSound()
        SoundManager.shared.stopBackgroundMusic()

        // Show game over after delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            self.gameStateBinding?.wrappedValue = .gameOver
        }
    }
    
    override func update(_ currentTime: TimeInterval) {
        // Check if frog fell below pit height
        if frog.position.y <= pitHeight && !isGameOver {
            gameOver()
        }

        // Update frog (stability check)
        frog.update(gameOver: isGameOver)

        // Update fly
        fly.update()

        // Update game manager (procedural scraper generation)
        gameManager.update()

        // Focus camera on frog
        focusOnFrog()
    }

    // MARK: - Touch/Mouse handling - forward to frog from anywhere

    #if os(macOS)
    override func mouseDown(with event: NSEvent) {
        let location = event.location(in: self)
        frog.handleMouseDown(at: location)
    }

    override func mouseDragged(with event: NSEvent) {
        let location = event.location(in: self)
        frog.handleMouseDragged(to: location)
    }

    override func mouseUp(with event: NSEvent) {
        frog.handleMouseUp()
    }
    #elseif os(tvOS)
    // tvOS uses remote gestures - swipe to aim, click to jump
    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        for press in presses {
            guard let key = press.key else { continue }

            // Handle Siri Remote swipes for direction
            switch key.keyCode {
            case .keyboardLeftArrow, .keyboardA:
                frog.handleRemoteSwipe(direction: .left)
            case .keyboardRightArrow, .keyboardD:
                frog.handleRemoteSwipe(direction: .right)
            case .keyboardUpArrow, .keyboardW:
                frog.handleRemoteSwipe(direction: .up)
            case .keyboardDownArrow, .keyboardS:
                frog.handleRemoteSwipe(direction: .down)
            default:
                break
            }
        }
        super.pressesBegan(presses, with: event)
    }

    override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        for press in presses {
            guard let key = press.key else { continue }

            // Select button triggers jump
            if key.keyCode == .keyboardSpacebar || key.keyCode == .keyboardReturnOrEnter {
                frog.handleRemoteJump()
            }
        }
        super.pressesEnded(presses, with: event)
    }
    #else
    // iOS and visionOS use touch/gesture input
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let location = touch.location(in: self)
        frog.handleTouchBegan(at: location)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let location = touch.location(in: self)
        frog.handleTouchMoved(to: location)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        frog.handleTouchEnded()
    }
    #endif
}

extension GameScene: SKPhysicsContactDelegate {
    func didBegin(_ contact: SKPhysicsContact) {
        let bodyA = contact.bodyA
        let bodyB = contact.bodyB
        
        // Handle frog-skyscraper collision
        if (bodyA.categoryBitMask == PhysicsCategory.frog && bodyB.categoryBitMask == PhysicsCategory.skyscraper) ||
           (bodyA.categoryBitMask == PhysicsCategory.skyscraper && bodyB.categoryBitMask == PhysicsCategory.frog) {
            
            let skyscraper = bodyA.categoryBitMask == PhysicsCategory.skyscraper ? bodyA.node as! Skyscraper : bodyB.node as! Skyscraper
            frog.landOnSkyscraper(skyscraper)
            gameManager.onProgress(skyscraper.index)
        }
        
        // Handle frog-fly collision
        if (bodyA.categoryBitMask == PhysicsCategory.frog && bodyB.categoryBitMask == PhysicsCategory.fly) ||
           (bodyA.categoryBitMask == PhysicsCategory.fly && bodyB.categoryBitMask == PhysicsCategory.frog) {
            
            fly.die()
            frog.eatFly()
        }
    }
}

struct PhysicsCategory {
    static let frog: UInt32 = 1
    static let skyscraper: UInt32 = 2
    static let fly: UInt32 = 4
}
