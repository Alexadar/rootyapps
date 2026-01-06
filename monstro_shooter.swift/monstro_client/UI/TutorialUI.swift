import SpriteKit

/// Tutorial hint overlay - shows hints at top center, matching HUD style
class TutorialUI {
    private weak var hudCamera: HUDCamera?
    private var hintContainer: SKNode?
    private var backgroundNode: SKShapeNode?
    private var hintLabel: SKLabelNode?

    // Panel styling (matches HUD)
    private let panelHeight: CGFloat = 40
    private let cornerRadius: CGFloat = 8
    private let minPanelWidth: CGFloat = 200
    private let horizontalPadding: CGFloat = 30

    init(hudCamera: HUDCamera) {
        self.hudCamera = hudCamera
    }

    func showHint(_ text: String, viewportSize: CGSize) {
        // Remove existing hint
        hideHint()

        // Create container
        let container = SKNode()
        container.zPosition = GameConstants.hudZPosition + 10  // Above HUD panels

        // Calculate panel width based on text
        let tempLabel = SKLabelNode(fontNamed: "System-Bold")
        tempLabel.fontSize = 18
        tempLabel.text = text
        let textWidth = tempLabel.frame.width
        let panelWidth = max(minPanelWidth, textWidth + horizontalPadding * 2)

        // Position at top center
        let topY = viewportSize.height / 2 - GameConstants.hudTopMargin

        // Background panel (same style as HUD)
        let background = SKShapeNode(
            rectOf: CGSize(width: panelWidth, height: panelHeight),
            cornerRadius: cornerRadius
        )
        background.fillColor = UIStyleGuide.Colors.deepSpaceBlue.withAlphaComponent(0.7)
        background.strokeColor = UIStyleGuide.Colors.white
        background.lineWidth = 2
        background.position = CGPoint(x: 0, y: topY - panelHeight / 2)
        background.alpha = 0
        container.addChild(background)
        self.backgroundNode = background

        // Text label (same style as HUD)
        let label = SKLabelNode(fontNamed: "System-Bold")
        label.fontSize = 18
        label.fontColor = UIStyleGuide.Colors.white
        label.text = text
        label.horizontalAlignmentMode = .center
        label.verticalAlignmentMode = .center
        label.position = CGPoint(x: 0, y: topY - panelHeight / 2)
        label.alpha = 0
        container.addChild(label)
        self.hintLabel = label

        // Add to HUD layer so it follows HUD parallax
        hudCamera?.hudLayer.addChild(container)
        self.hintContainer = container

        // Animate: fade in, wait, fade out, remove
        let fadeIn = SKAction.fadeIn(withDuration: GameConstants.tutorialHintFadeDuration)
        let wait = SKAction.wait(forDuration: GameConstants.tutorialHintDisplayDuration)
        let fadeOut = SKAction.fadeOut(withDuration: GameConstants.tutorialHintFadeDuration)
        let sequence = SKAction.sequence([fadeIn, wait, fadeOut])

        background.run(sequence)
        label.run(sequence) { [weak self] in
            self?.hideHint()
        }
    }

    func hideHint() {
        hintContainer?.removeFromParent()
        hintContainer = nil
        backgroundNode = nil
        hintLabel = nil
    }

    func remove() {
        hideHint()
    }
}
