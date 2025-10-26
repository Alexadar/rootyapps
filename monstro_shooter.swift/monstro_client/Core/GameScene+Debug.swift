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
        // Add debug label to HUD layer (follows camera)
        renderer?.hudCamera.hudLayer.addChild(label)
        updateDebugLabel()
    }

    func updateDebugLabel() {
        let monsterInfo = "Monsters: \(monsters.count)"
        let rotationInfo = "R: \(debugRotationEnabled ? "ON" : "OFF")  Offset: \(String(format: "%.2f", debugRotationOffset))"
        debugRotationLabel?.text = "\(monsterInfo)  |  \(rotationInfo)"

        // Position is already set in setupDebugLabel, no need to update
        // (it moves with HUD layer automatically)
    }
}
