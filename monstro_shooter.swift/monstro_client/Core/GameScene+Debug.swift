import SpriteKit
#if os(macOS)
import AppKit
#else
import UIKit
#endif

// MARK: - Debug Visuals
extension GameScene {

    func setupDebugLabel() {
        let label = SKLabelNode(fontNamed: "Menlo")
        label.fontSize = 12
        label.fontColor = .white
        label.horizontalAlignmentMode = .left
        label.verticalAlignmentMode = .bottom
        // Position at bottom-left (will be updated to follow camera)
        label.position = CGPoint(x: -size.width/2 + 10, y: -size.height/2 + 10)
        label.zPosition = 1000 // Same as HUD
        debugRotationLabel = label
        addChild(label)
        updateDebugLabel()
    }

    func updateDebugLabel() {
        let monsterInfo = "Monsters: \(monsters.count)"
        let rotationInfo = "R: \(debugRotationEnabled ? "ON" : "OFF")  Offset: \(String(format: "%.2f", debugRotationOffset))"
        debugRotationLabel?.text = "\(monsterInfo)  |  \(rotationInfo)"

        // Update position to follow camera (bottom-left corner)
        if let camera = self.camera, let view = view {
            let bottomLeftX = camera.position.x - view.bounds.width/2 + 10
            let bottomLeftY = camera.position.y - view.bounds.height/2 + 10
            debugRotationLabel?.position = CGPoint(x: bottomLeftX, y: bottomLeftY)
        }
    }
}
