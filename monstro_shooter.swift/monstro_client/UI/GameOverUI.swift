import SpriteKit
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// End game modes
enum EndGameMode {
    case death
    case victory

    var title: String {
        switch self {
        case .death: return "GAME OVER"
        case .victory: return "VICTORY!"
        }
    }
}

/// Game over overlay with Try Again and Menu buttons
class GameOverUI {
    private let containerNode: SKNode
    private weak var scene: SKScene?
    private var onTryAgain: (() -> Void)?
    private var onGoToMenu: (() -> Void)?

    init(scene: SKScene) {
        self.scene = scene
        self.containerNode = SKNode()
        self.containerNode.zPosition = 2000  // Above HUD
    }

    func show(mode: EndGameMode = .death, onTryAgain: @escaping () -> Void, onGoToMenu: @escaping () -> Void) {
        guard let scene = scene, let camera = scene.camera else { return }

        self.onTryAgain = onTryAgain
        self.onGoToMenu = onGoToMenu

        // Clear any existing UI
        containerNode.removeAllChildren()

        let viewportSize = scene.size

        // Semi-transparent background overlay
        let overlay = SKSpriteNode(color: .black, size: CGSize(width: viewportSize.width * 2, height: viewportSize.height * 2))
        overlay.alpha = 0.7
        overlay.position = CGPoint.zero
        overlay.zPosition = 0
        containerNode.addChild(overlay)

        // Title based on mode
        let titleLabel = SKLabelNode(fontNamed: "System-Bold")
        titleLabel.text = mode.title
        titleLabel.fontSize = 64
        titleLabel.fontColor = UIStyleGuide.Colors.white
        titleLabel.position = CGPoint(x: 0, y: 100)
        titleLabel.zPosition = 1
        containerNode.addChild(titleLabel)

        // Try Again button (Primary style)
        let tryAgainButton = createPrimaryButton(
            text: "TRY AGAIN",
            position: CGPoint(x: 0, y: 0),
            name: "tryAgainButton"
        )
        containerNode.addChild(tryAgainButton)

        // Go to Menu button (Secondary style)
        let menuButton = createSecondaryButton(
            text: "MENU",
            position: CGPoint(x: 0, y: -80),
            name: "menuButton"
        )
        containerNode.addChild(menuButton)

        // Add container to camera (not scene) so it follows viewport
        camera.addChild(containerNode)

        print("Game over UI shown with \(containerNode.children.count) children")
    }

    private func createPrimaryButton(text: String, position: CGPoint, name: String) -> SKNode {
        let buttonContainer = SKNode()
        buttonContainer.position = position
        buttonContainer.name = name

        let width: CGFloat = 300
        let height: CGFloat = 60

        // Button background with Primary style
        let background = SKShapeNode(
            rectOf: CGSize(width: width, height: height),
            cornerRadius: UIStyleGuide.Button.Primary.cornerRadius
        )
        background.fillColor = UIStyleGuide.Button.Primary.backgroundColor.withAlphaComponent(UIStyleGuide.Button.Primary.backgroundOpacity)
        background.strokeColor = UIStyleGuide.Button.Primary.borderColor
        background.lineWidth = UIStyleGuide.Button.Primary.borderWidth
        background.zPosition = 0
        buttonContainer.addChild(background)

        // Button label with Primary style
        let label = SKLabelNode(fontNamed: "System-Bold")
        label.text = text
        label.fontSize = UIStyleGuide.Button.Primary.fontSize
        label.fontColor = UIStyleGuide.Button.Primary.textColor
        label.horizontalAlignmentMode = .center
        label.verticalAlignmentMode = .center
        label.zPosition = 1
        buttonContainer.addChild(label)

        return buttonContainer
    }

    private func createSecondaryButton(text: String, position: CGPoint, name: String) -> SKNode {
        let buttonContainer = SKNode()
        buttonContainer.position = position
        buttonContainer.name = name

        let width: CGFloat = 300
        let height: CGFloat = 60

        // Button background with Secondary style (matching main menu SETTINGS button)
        let background = SKShapeNode(
            rectOf: CGSize(width: width, height: height),
            cornerRadius: UIStyleGuide.Button.Secondary.cornerRadius
        )
        background.fillColor = UIStyleGuide.Button.Secondary.backgroundColor.withAlphaComponent(UIStyleGuide.Button.Secondary.backgroundOpacity)
        background.strokeColor = UIStyleGuide.Button.Secondary.borderColor
        background.lineWidth = UIStyleGuide.Button.Secondary.borderWidth
        background.zPosition = 0
        buttonContainer.addChild(background)

        // Button label with Secondary style matching main menu
        let label = SKLabelNode(fontNamed: "System-Bold")
        label.text = text
        label.fontSize = UIStyleGuide.Button.Secondary.fontSize
        label.fontColor = UIStyleGuide.Button.Secondary.textColor
        label.horizontalAlignmentMode = .center
        label.verticalAlignmentMode = .center
        label.zPosition = 1
        buttonContainer.addChild(label)

        return buttonContainer
    }

    func handleTouch(at location: CGPoint) {
        let nodes = scene?.nodes(at: location) ?? []

        for node in nodes {
            if node.name == "tryAgainButton" || node.parent?.name == "tryAgainButton" {
                onTryAgain?()
                return
            }
            if node.name == "menuButton" || node.parent?.name == "menuButton" {
                onGoToMenu?()
                return
            }
        }
    }

    func hide() {
        containerNode.removeFromParent()
    }
}
