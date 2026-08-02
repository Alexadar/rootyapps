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
        let panelWidth: CGFloat = UIStyleGuide.PauseMenu.panelWidth
        let panelHeight: CGFloat = 400
        panelNode = SKShapeNode(rectOf: CGSize(width: panelWidth, height: panelHeight), cornerRadius: UIStyleGuide.PauseMenu.panelCornerRadius)
        panelNode.fillColor = UIStyleGuide.PauseMenu.panelBackgroundColor.withAlphaComponent(UIStyleGuide.PauseMenu.panelBackgroundOpacity)
        panelNode.strokeColor = UIStyleGuide.PauseMenu.panelBorderColor
        panelNode.lineWidth = UIStyleGuide.PauseMenu.panelBorderWidth
        panelNode.zPosition = 2
        containerNode.addChild(panelNode)

        // Title
        titleLabel = SKLabelNode(text: "PAUSED")
        titleLabel.fontName = UIStyleGuide.PauseMenu.titleFontName
        titleLabel.fontSize = UIStyleGuide.PauseMenu.titleFontSize
        titleLabel.fontColor = UIStyleGuide.PauseMenu.titleColor
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
        resumeLabel.fontName = UIStyleGuide.PauseMenu.buttonFontName
        resumeLabel.fontSize = UIStyleGuide.PauseMenu.buttonFontSize
        resumeLabel.fontColor = UIStyleGuide.PauseMenu.buttonTextColor
        resumeLabel.verticalAlignmentMode = .center
        resumeLabel.zPosition = 4
        resumeButton.addChild(resumeLabel)

        // Main Menu / Back button
        menuButton = createButton(size: CGSize(width: buttonWidth, height: buttonHeight))
        menuButton.position = CGPoint(x: 0, y: -40)
        menuButton.zPosition = 3
        containerNode.addChild(menuButton)

        menuLabel = SKLabelNode(text: isDebugMode ? "BACK" : "MAIN MENU")
        menuLabel.fontName = UIStyleGuide.PauseMenu.buttonFontName
        menuLabel.fontSize = UIStyleGuide.PauseMenu.buttonFontSize
        menuLabel.fontColor = UIStyleGuide.PauseMenu.buttonTextColor
        menuLabel.verticalAlignmentMode = .center
        menuLabel.zPosition = 4
        menuButton.addChild(menuLabel)

        // Exit button
        exitButton = createButton(size: CGSize(width: buttonWidth, height: buttonHeight))
        exitButton.position = CGPoint(x: 0, y: -120)
        exitButton.zPosition = 3
        containerNode.addChild(exitButton)

        exitLabel = SKLabelNode(text: "EXIT")
        exitLabel.fontName = UIStyleGuide.PauseMenu.buttonFontName
        exitLabel.fontSize = UIStyleGuide.PauseMenu.buttonFontSize
        exitLabel.fontColor = UIStyleGuide.PauseMenu.buttonTextColor
        exitLabel.verticalAlignmentMode = .center
        exitLabel.zPosition = 4
        exitButton.addChild(exitLabel)

        parentNode.addChild(containerNode)
        containerNode.isHidden = true
    }

    private func createButton(size: CGSize) -> SKShapeNode {
        let button = SKShapeNode(rectOf: size, cornerRadius: UIStyleGuide.PauseMenu.buttonCornerRadius)
        button.fillColor = UIStyleGuide.PauseMenu.buttonHighlightColor.withAlphaComponent(UIStyleGuide.PauseMenu.buttonBackgroundOpacity)
        button.strokeColor = UIStyleGuide.PauseMenu.buttonHighlightColor
        button.lineWidth = UIStyleGuide.PauseMenu.buttonBorderWidth
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
