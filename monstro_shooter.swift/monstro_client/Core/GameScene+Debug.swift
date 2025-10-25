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
        label.verticalAlignmentMode = .top
        label.position = CGPoint(x: -size.width/2 + 10, y: size.height/2 - 10)
        label.zPosition = 200
        debugRotationLabel = label
        addChild(label)
        updateDebugLabel()
    }

    func updateDebugLabel() {
        debugRotationLabel?.text = "R: \(debugRotationEnabled ? "ON" : "OFF")  Offset: \(String(format: "%.2f", debugRotationOffset))  (Q/E adjust, R toggle)"
    }
}
