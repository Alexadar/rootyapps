import SpriteKit
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Camera dedicated to HUD rendering with isolated layer
/// HUD elements are positioned in their own coordinate space
class HUDCamera {
    let hudLayer: SKNode
    private weak var worldCamera: WorldCamera?

    // HUD labels
    private var timeLabel: SKLabelNode?
    private var killsLabel: SKLabelNode?
    private var ammoLabel: SKLabelNode?
    private var healthLabel: SKLabelNode?

    // Pause button (iOS/iPadOS only)
    #if !os(macOS)
    private var pauseButton: SKShapeNode?
    var onPauseTapped: (() -> Void)?
    #endif

    // Parallax effect settings
    private var currentOffset: CGPoint = .zero
    private var lastCameraPosition: CGPoint = .zero

    init(worldCamera: WorldCamera) {
        self.worldCamera = worldCamera
        self.hudLayer = SKNode()
        self.hudLayer.zPosition = GameConstants.hudZPosition
    }

    /// Setup HUD elements (called after scene size is known)
    func setup(viewportSize: CGSize) {
        // Clear existing HUD
        hudLayer.removeAllChildren()

        // Panel dimensions
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

        // Create pause button (iOS/iPadOS only)
        #if !os(macOS)
        createPauseButton(viewportSize: viewportSize, topY: topY)
        #endif
    }

    #if !os(macOS)
    /// Create pause button for touch devices
    private func createPauseButton(viewportSize: CGSize, topY: CGFloat) {
        let buttonSize: CGFloat = 44  // Touch-friendly size
        let cornerRadius: CGFloat = 8

        // Position at top-center
        let button = SKShapeNode(rectOf: CGSize(width: buttonSize, height: buttonSize), cornerRadius: cornerRadius)
        button.fillColor = UIStyleGuide.Colors.deepSpaceBlue.withAlphaComponent(0.7)
        button.strokeColor = UIStyleGuide.Colors.white
        button.lineWidth = 2
        button.position = CGPoint(x: 0, y: topY - buttonSize / 2)
        button.name = "pauseButton"
        hudLayer.addChild(button)
        pauseButton = button

        // Pause icon (two vertical bars)
        let icon = SKLabelNode(fontNamed: "System-Bold")
        icon.text = "❚❚"
        icon.fontSize = 18
        icon.fontColor = UIStyleGuide.Colors.white
        icon.horizontalAlignmentMode = .center
        icon.verticalAlignmentMode = .center
        icon.position = button.position
        hudLayer.addChild(icon)
    }

    /// Check if a point (in HUD layer coordinates) hits the pause button
    func handleTouch(at point: CGPoint) -> Bool {
        guard let button = pauseButton else { return false }
        // Account for HUD parallax offset
        let adjustedPoint = CGPoint(x: point.x - currentOffset.x, y: point.y - currentOffset.y)
        if button.contains(adjustedPoint) {
            onPauseTapped?()
            return true
        }
        return false
    }
    #endif

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

    /// Update HUD position with parallax effect (opposite direction of camera movement)
    /// HUD moves 5% in opposite direction with smooth lerp, clamped to max offset
    func updatePosition() {
        guard let camera = worldCamera else { return }

        let cameraPos = camera.cameraNode.position

        // Calculate camera velocity (movement delta)
        let deltaX = cameraPos.x - lastCameraPosition.x
        let deltaY = cameraPos.y - lastCameraPosition.y

        // Target offset is 5% of camera velocity in opposite direction
        let targetOffsetX = -deltaX * GameConstants.hudParallaxStrength
        let targetOffsetY = -deltaY * GameConstants.hudParallaxStrength

        // Clamp target offset to max range
        let clampedTargetX = max(-GameConstants.hudMaxParallaxOffset, min(GameConstants.hudMaxParallaxOffset, targetOffsetX))
        let clampedTargetY = max(-GameConstants.hudMaxParallaxOffset, min(GameConstants.hudMaxParallaxOffset, targetOffsetY))

        // Smooth lerp to target offset (moves when camera moves)
        currentOffset.x += (clampedTargetX - currentOffset.x) * GameConstants.hudParallaxLerpSpeed
        currentOffset.y += (clampedTargetY - currentOffset.y) * GameConstants.hudParallaxLerpSpeed

        // Gradually return to center when not moving
        currentOffset.x *= (1.0 - GameConstants.hudParallaxReturnSpeed)
        currentOffset.y *= (1.0 - GameConstants.hudParallaxReturnSpeed)

        hudLayer.position = currentOffset
        lastCameraPosition = cameraPos
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

    /// Reposition HUD when viewport changes
    func repositionForViewport(_ viewportSize: CGSize) {
        setup(viewportSize: viewportSize)
    }
}
