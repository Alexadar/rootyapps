import SpriteKit

class PauseMenuUI {
    private var containerNode: SKNode!
    private var backgroundOverlay: SKShapeNode!
    private var panelNode: SKShapeNode!
    private var resumeButton: SKShapeNode!
    private var menuButton: SKShapeNode!
    private var exitButton: SKShapeNode!
    private var resumeLabel: SKLabelNode!
    private var menuLabel: SKLabelNode!
    private var exitLabel: SKLabelNode!
    private var titleLabel: SKLabelNode!

    private weak var scene: GameScene?
    private weak var parentNode: SKNode?
    private let isDebugMode: Bool

    var onResume: (() -> Void)?
    var onMainMenu: (() -> Void)?
    var onExit: (() -> Void)?

    init(scene: GameScene, parentNode: SKNode, isDebugMode: Bool) {
        self.scene = scene
        self.parentNode = parentNode
        self.isDebugMode = isDebugMode
        setupUI()
    }

    private func setupUI() {
        guard let parentNode = parentNode else { return }

        containerNode = SKNode()
        containerNode.zPosition = 10000

        // Semi-transparent dark background
        backgroundOverlay = SKShapeNode(rectOf: CGSize(width: 10000, height: 10000))
        backgroundOverlay.fillColor = .black
        backgroundOverlay.strokeColor = .clear
        backgroundOverlay.alpha = 0.7
        backgroundOverlay.zPosition = 1
        containerNode.addChild(backgroundOverlay)

        // Panel
        let panelWidth: CGFloat = 400
        let panelHeight: CGFloat = 400
        panelNode = SKShapeNode(rectOf: CGSize(width: panelWidth, height: panelHeight), cornerRadius: 20)
        panelNode.fillColor = NSColor(red: 0.04, green: 0.08, blue: 0.16, alpha: 0.95)
        panelNode.strokeColor = NSColor(red: 0.0, green: 0.85, blue: 1.0, alpha: 1.0)
        panelNode.lineWidth = 3
        panelNode.zPosition = 2
        containerNode.addChild(panelNode)

        // Title
        titleLabel = SKLabelNode(text: "PAUSED")
        titleLabel.fontName = "Helvetica-Bold"
        titleLabel.fontSize = 48
        titleLabel.fontColor = .white
        titleLabel.position = CGPoint(x: 0, y: 120)
        titleLabel.zPosition = 3
        containerNode.addChild(titleLabel)

        // Resume button
        let buttonWidth: CGFloat = 300
        let buttonHeight: CGFloat = 60
        resumeButton = createButton(size: CGSize(width: buttonWidth, height: buttonHeight))
        resumeButton.position = CGPoint(x: 0, y: 40)
        resumeButton.zPosition = 3
        containerNode.addChild(resumeButton)

        resumeLabel = SKLabelNode(text: "RESUME")
        resumeLabel.fontName = "Helvetica-Bold"
        resumeLabel.fontSize = 24
        resumeLabel.fontColor = .white
        resumeLabel.verticalAlignmentMode = .center
        resumeLabel.zPosition = 4
        resumeButton.addChild(resumeLabel)

        // Main Menu / Back button
        menuButton = createButton(size: CGSize(width: buttonWidth, height: buttonHeight))
        menuButton.position = CGPoint(x: 0, y: -40)
        menuButton.zPosition = 3
        containerNode.addChild(menuButton)

        menuLabel = SKLabelNode(text: isDebugMode ? "BACK" : "MAIN MENU")
        menuLabel.fontName = "Helvetica-Bold"
        menuLabel.fontSize = 24
        menuLabel.fontColor = .white
        menuLabel.verticalAlignmentMode = .center
        menuLabel.zPosition = 4
        menuButton.addChild(menuLabel)

        // Exit button
        exitButton = createButton(size: CGSize(width: buttonWidth, height: buttonHeight))
        exitButton.position = CGPoint(x: 0, y: -120)
        exitButton.zPosition = 3
        containerNode.addChild(exitButton)

        exitLabel = SKLabelNode(text: "EXIT")
        exitLabel.fontName = "Helvetica-Bold"
        exitLabel.fontSize = 24
        exitLabel.fontColor = .white
        exitLabel.verticalAlignmentMode = .center
        exitLabel.zPosition = 4
        exitButton.addChild(exitLabel)

        parentNode.addChild(containerNode)
        containerNode.isHidden = true
    }

    private func createButton(size: CGSize) -> SKShapeNode {
        let button = SKShapeNode(rectOf: size, cornerRadius: 10)
        button.fillColor = NSColor(red: 0.0, green: 1.0, blue: 0.6, alpha: 0.3)
        button.strokeColor = NSColor(red: 0.0, green: 1.0, blue: 0.6, alpha: 1.0)
        button.lineWidth = 2
        return button
    }

    func show() {
        containerNode.isHidden = false
    }

    func hide() {
        containerNode.isHidden = true
    }

    func handleTouch(at location: CGPoint) -> Bool {
        guard let scene = scene else { return false }

        // Convert scene location to containerNode's local coordinate space
        let localPoint = containerNode.convert(location, from: scene)

        // Check Resume button
        if resumeButton.contains(localPoint) {
            onResume?()
            return true
        }

        // Check Main Menu / Back button
        if menuButton.contains(localPoint) {
            onMainMenu?()
            return true
        }

        // Check Exit button
        if exitButton.contains(localPoint) {
            onExit?()
            return true
        }

        return false
    }
}
