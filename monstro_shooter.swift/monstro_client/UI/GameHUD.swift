import SpriteKit
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Game HUD overlay with simple rectangular panels
class GameHUD {
    // Container nodes
    private var hudLayer: SKNode

    // HUD labels
    private var timeLabel: SKLabelNode?
    private var killsLabel: SKLabelNode?
    private var ammoLabel: SKLabelNode?
    private var healthLabel: SKLabelNode?

    init(scene: SKScene) {
        hudLayer = SKNode()
        hudLayer.zPosition = GameConstants.hudZPosition
        scene.addChild(hudLayer)
    }

    /// Setup HUD elements (called after scene size is known)
    func setup(viewportSize: CGSize) {
        // Clear existing HUD
        hudLayer.removeAllChildren()

        // Panel dimensions (same as menu buttons)
        let panelWidth: CGFloat = 140
        let panelHeight: CGFloat = 40
        let cornerRadius: CGFloat = 8

        // Top-left corner position
        let leftX = -viewportSize.width / 2 + GameConstants.hudHorizontalMargin
        let topY = viewportSize.height / 2 - GameConstants.hudTopMargin

        // Top-right corner position
        let rightX = viewportSize.width / 2 - GameConstants.hudHorizontalMargin - panelWidth

        // Create top-left panels (time, kills)
        createPanel(
            x: leftX,
            y: topY,
            width: panelWidth,
            height: panelHeight,
            cornerRadius: cornerRadius,
            text: "0:00",
            label: &timeLabel
        )

        createPanel(
            x: leftX,
            y: topY - GameConstants.hudRowSpacing,
            width: panelWidth,
            height: panelHeight,
            cornerRadius: cornerRadius,
            text: "0",
            label: &killsLabel
        )

        // Create top-right panels (ammo, health)
        createPanel(
            x: rightX,
            y: topY,
            width: panelWidth,
            height: panelHeight,
            cornerRadius: cornerRadius,
            text: "20/160",
            label: &ammoLabel
        )

        createPanel(
            x: rightX,
            y: topY - GameConstants.hudRowSpacing,
            width: panelWidth,
            height: panelHeight,
            cornerRadius: cornerRadius,
            text: "100",
            label: &healthLabel
        )
    }

    /// Create a simple panel with text
    private func createPanel(
        x: CGFloat,
        y: CGFloat,
        width: CGFloat,
        height: CGFloat,
        cornerRadius: CGFloat,
        text: String,
        label: inout SKLabelNode?
    ) {
        // Background panel
        let background = SKShapeNode(
            rectOf: CGSize(width: width, height: height),
            cornerRadius: cornerRadius
        )
        background.fillColor = UIStyleGuide.Colors.deepSpaceBlue.withAlphaComponent(0.7)
        background.strokeColor = UIStyleGuide.Colors.white
        background.lineWidth = 2
        background.position = CGPoint(x: x + width/2, y: y - height/2)
        hudLayer.addChild(background)

        // Text label (centered)
        let textLabel = SKLabelNode(fontNamed: "System-Bold")
        textLabel.fontSize = 18
        textLabel.fontColor = UIStyleGuide.Colors.white
        textLabel.text = text
        textLabel.horizontalAlignmentMode = .center
        textLabel.verticalAlignmentMode = .center
        textLabel.position = CGPoint(x: x + width/2, y: y - height/2)
        hudLayer.addChild(textLabel)
        label = textLabel
    }

    /// Update time display
    func updateTime(seconds: Int) {
        let minutes = seconds / 60
        let secs = seconds % 60
        timeLabel?.text = String(format: "%d:%02d", minutes, secs)
    }

    /// Update kills counter
    func updateKills(count: Int) {
        killsLabel?.text = "\(count)"
    }

    /// Update ammo display
    func updateAmmo(current: Int, total: Int) {
        ammoLabel?.text = "\(current)/\(total)"
    }

    /// Update health display
    func updateHealth(value: Int) {
        healthLabel?.text = "\(value)"
    }

    /// Update HUD position to follow camera
    func updatePosition(cameraPosition: CGPoint) {
        hudLayer.position = cameraPosition
    }

    /// Reposition HUD when viewport changes
    func repositionForViewport(_ viewportSize: CGSize) {
        setup(viewportSize: viewportSize)
    }
}
