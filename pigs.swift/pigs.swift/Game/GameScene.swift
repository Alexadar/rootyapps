import SpriteKit
import SwiftUI

class GameScene: SKScene {
    weak var gameEngine: GameEngine?
    weak var inputHandler: InputHandler?

    private var playerNode: SKLabelNode!
    private var enemyNodes: [SKLabelNode] = []
    private var treasureNodes: [SKLabelNode] = []
    private var wallNodes: [SKShapeNode] = []
    private var exitNode: SKLabelNode!

    private var maze: [[MazeCell]] = []
    private var cellSize: CGFloat = 40
    private var mazeOffsetX: CGFloat = 0
    private var mazeOffsetY: CGFloat = 0

    private var lastUpdateTime: TimeInterval = 0
    private var enemyMoveTimer: TimeInterval = 0

    override func didMove(to view: SKView) {
        setupScene()
        generateMaze()
        setupPlayer()
        setupTreasures()
        setupEnemies()
        setupExit()
    }

    func setupScene() {
        backgroundColor = SKColor(red: 0.1, green: 0.1, blue: 0.15, alpha: 1.0)
        physicsWorld.gravity = .zero

        let gridSize = GameConstants.gridSize(for: size)
        cellSize = min(size.width / CGFloat(gridSize.width),
                      size.height / CGFloat(gridSize.height))

        mazeOffsetX = (size.width - CGFloat(gridSize.width) * cellSize) / 2
        mazeOffsetY = (size.height - CGFloat(gridSize.height) * cellSize) / 2
    }

    func generateMaze() {
        guard let gameEngine = gameEngine else { return }

        let gridSize = GameConstants.gridSize(for: size)
        maze = MazeGenerator.generateMaze(width: gridSize.width, height: gridSize.height)

        for y in 0..<gridSize.height {
            for x in 0..<gridSize.width {
                if maze[y][x].isWall {
                    let wall = SKShapeNode(rectOf: CGSize(width: cellSize - 2, height: cellSize - 2))
                    wall.fillColor = SKColor(red: 0.3, green: 0.2, blue: 0.1, alpha: 1.0)
                    wall.strokeColor = SKColor(red: 0.4, green: 0.3, blue: 0.2, alpha: 1.0)
                    wall.lineWidth = 1
                    wall.position = gridToScene(x: x, y: y)
                    wall.name = "wall_\(x)_\(y)"
                    addChild(wall)
                    wallNodes.append(wall)
                }
            }
        }

        gameEngine.maze = maze
    }

    func setupPlayer() {
        guard let gameEngine = gameEngine else { return }

        playerNode = SKLabelNode(text: GameConstants.playerEmoji)
        playerNode.fontSize = cellSize * 0.8
        playerNode.verticalAlignmentMode = .center
        playerNode.horizontalAlignmentMode = .center

        let startPos = findEmptyPosition()
        gameEngine.player.position = startPos
        playerNode.position = gridToScene(point: startPos)
        playerNode.name = "player"

        addChild(playerNode)
    }

    func setupTreasures() {
        guard let gameEngine = gameEngine else { return }

        let treasureCount = GameConstants.treasureCount(for: gameEngine.currentLevel)
        gameEngine.treasures.removeAll()

        for i in 0..<treasureCount {
            let position = findEmptyPosition()
            let emoji = GameConstants.treasureEmojis.randomElement() ?? "💎"
            let value = GameConstants.treasureValue(for: emoji)

            let treasure = Treasure(id: UUID(), position: position, emoji: emoji, value: value, collected: false)
            gameEngine.treasures.append(treasure)

            let node = SKLabelNode(text: emoji)
            node.fontSize = cellSize * 0.6
            node.verticalAlignmentMode = .center
            node.horizontalAlignmentMode = .center
            node.position = gridToScene(point: position)
            node.name = "treasure_\(i)"

            let scaleAction = SKAction.sequence([
                SKAction.scale(to: 1.2, duration: 0.5),
                SKAction.scale(to: 1.0, duration: 0.5)
            ])
            node.run(SKAction.repeatForever(scaleAction))

            addChild(node)
            treasureNodes.append(node)
        }
    }

    func setupEnemies() {
        guard let gameEngine = gameEngine else { return }

        let enemyCount = GameConstants.enemyCount(for: gameEngine.currentLevel)
        gameEngine.enemies.removeAll()

        for i in 0..<enemyCount {
            let position = findEmptyPosition()
            let emoji = GameConstants.enemyEmojis.randomElement() ?? "👻"
            let speed = GameConstants.enemySpeed(for: gameEngine.difficulty)

            let enemy = Enemy(id: UUID(), position: position, emoji: emoji, speed: speed, direction: Direction.random())
            gameEngine.enemies.append(enemy)

            let node = SKLabelNode(text: emoji)
            node.fontSize = cellSize * 0.7
            node.verticalAlignmentMode = .center
            node.horizontalAlignmentMode = .center
            node.position = gridToScene(point: position)
            node.name = "enemy_\(i)"

            addChild(node)
            enemyNodes.append(node)
        }
    }

    func setupExit() {
        guard let gameEngine = gameEngine else { return }

        let exitPosition = findEmptyPosition(preferFarFrom: gameEngine.player.position)
        gameEngine.exitPosition = exitPosition

        exitNode = SKLabelNode(text: "🚪")
        exitNode.fontSize = cellSize * 0.8
        exitNode.verticalAlignmentMode = .center
        exitNode.horizontalAlignmentMode = .center
        exitNode.position = gridToScene(point: exitPosition)
        exitNode.name = "exit"
        exitNode.alpha = 0.3

        addChild(exitNode)
    }

    override func update(_ currentTime: TimeInterval) {
        if lastUpdateTime == 0 {
            lastUpdateTime = currentTime
        }

        let deltaTime = currentTime - lastUpdateTime
        lastUpdateTime = currentTime

        guard let gameEngine = gameEngine,
              gameEngine.gameState == .playing else { return }

        updatePlayerPosition()
        updateEnemies(deltaTime: deltaTime)
        checkCollisions()
        checkWinCondition()
    }

    func updatePlayerPosition() {
        guard let gameEngine = gameEngine,
              let inputHandler = inputHandler else { return }

        if let direction = inputHandler.currentDirection {
            var newPosition = gameEngine.player.position

            switch direction {
            case .up:
                newPosition.y -= 1
            case .down:
                newPosition.y += 1
            case .left:
                newPosition.x -= 1
            case .right:
                newPosition.x += 1
            }

            if isValidPosition(newPosition) {
                gameEngine.player.position = newPosition
                inputHandler.currentDirection = nil

                let moveAction = SKAction.move(to: gridToScene(point: newPosition), duration: 0.15)
                playerNode.run(moveAction)
            }
        }
    }

    func updateEnemies(deltaTime: TimeInterval) {
        guard let gameEngine = gameEngine else { return }

        enemyMoveTimer += deltaTime

        let moveInterval = 1.0 / GameConstants.enemySpeed(for: gameEngine.difficulty)

        if enemyMoveTimer >= moveInterval {
            enemyMoveTimer = 0

            for (index, enemy) in gameEngine.enemies.enumerated() {
                guard index < enemyNodes.count else { continue }

                var newPosition = enemy.position
                var triedDirections = 0
                var moved = false

                while !moved && triedDirections < 4 {
                    switch enemy.direction {
                    case .up:
                        newPosition.y -= 1
                    case .down:
                        newPosition.y += 1
                    case .left:
                        newPosition.x -= 1
                    case .right:
                        newPosition.x += 1
                    }

                    if isValidPosition(newPosition) {
                        gameEngine.enemies[index].position = newPosition
                        moved = true

                        let moveAction = SKAction.move(to: gridToScene(point: newPosition), duration: 0.2)
                        enemyNodes[index].run(moveAction)

                        if Double.random(in: 0...1) < 0.3 {
                            gameEngine.enemies[index].direction = Direction.random()
                        }
                    } else {
                        gameEngine.enemies[index].direction = Direction.random()
                        newPosition = enemy.position
                        triedDirections += 1
                    }
                }
            }
        }
    }

    func checkCollisions() {
        guard let gameEngine = gameEngine else { return }

        for (index, treasure) in gameEngine.treasures.enumerated() where !treasure.collected {
            if treasure.position == gameEngine.player.position {
                gameEngine.collectTreasure(at: index)

                if index < treasureNodes.count {
                    let node = treasureNodes[index]
                    let collectAction = SKAction.sequence([
                        SKAction.group([
                            SKAction.scale(to: 1.5, duration: 0.2),
                            SKAction.fadeOut(withDuration: 0.2)
                        ]),
                        SKAction.removeFromParent()
                    ])
                    node.run(collectAction)
                }
            }
        }

        for enemy in gameEngine.enemies {
            if enemy.position == gameEngine.player.position {
                gameEngine.playerHit()

                let flashAction = SKAction.sequence([
                    SKAction.colorize(with: .red, colorBlendFactor: 1.0, duration: 0.1),
                    SKAction.wait(forDuration: 0.1),
                    SKAction.colorize(withColorBlendFactor: 0.0, duration: 0.1)
                ])
                playerNode.run(flashAction)

                if gameEngine.lives <= 0 {
                    gameEngine.gameOver()
                }
                break
            }
        }
    }

    func checkWinCondition() {
        guard let gameEngine = gameEngine else { return }

        let allCollected = gameEngine.treasures.allSatisfy { $0.collected }

        if allCollected {
            exitNode.alpha = 1.0

            if gameEngine.player.position == gameEngine.exitPosition {
                gameEngine.nextLevel()
                resetLevel()
            }
        }
    }

    func resetLevel() {
        removeAllChildren()
        enemyNodes.removeAll()
        treasureNodes.removeAll()
        wallNodes.removeAll()

        setupScene()
        generateMaze()
        setupPlayer()
        setupTreasures()
        setupEnemies()
        setupExit()
    }

    func isValidPosition(_ position: GridPosition) -> Bool {
        let gridSize = GameConstants.gridSize(for: size)

        guard position.x >= 0 && position.x < gridSize.width &&
              position.y >= 0 && position.y < gridSize.height else {
            return false
        }

        return !maze[position.y][position.x].isWall
    }

    func findEmptyPosition(preferFarFrom: GridPosition? = nil) -> GridPosition {
        let gridSize = GameConstants.gridSize(for: size)
        var positions: [GridPosition] = []

        for y in 0..<gridSize.height {
            for x in 0..<gridSize.width {
                if !maze[y][x].isWall {
                    positions.append(GridPosition(x: x, y: y))
                }
            }
        }

        if let farFrom = preferFarFrom {
            positions.sort { pos1, pos2 in
                let dist1 = abs(pos1.x - farFrom.x) + abs(pos1.y - farFrom.y)
                let dist2 = abs(pos2.x - farFrom.x) + abs(pos2.y - farFrom.y)
                return dist1 > dist2
            }
            return positions.first ?? GridPosition(x: 1, y: 1)
        }

        return positions.randomElement() ?? GridPosition(x: 1, y: 1)
    }

    func gridToScene(x: Int, y: Int) -> CGPoint {
        return CGPoint(
            x: mazeOffsetX + CGFloat(x) * cellSize + cellSize / 2,
            y: size.height - (mazeOffsetY + CGFloat(y) * cellSize + cellSize / 2)
        )
    }

    func gridToScene(point: GridPosition) -> CGPoint {
        return gridToScene(x: point.x, y: point.y)
    }
}