import SpriteKit
#if os(macOS)
import AppKit
#else
import UIKit
#endif

// MARK: - Input Setup & Handling
extension GameScene {

    func setupInput() {
        // Allow external input (AI) to override default platform input.
        if let ext = externalInput {
            inputController = ext
            // still prepare touch debug visuals for completeness (no-op if macOS)
        } else {
            #if os(macOS)
            inputController = KeyboardMouseInput()
            #else
            inputController = TouchInput(scene: self)
            #endif
        }

        // Debug visual regions to verify where touch controls are active (left/right halves).
        debugLeftRegion?.removeFromParent()
        debugRightRegion?.removeFromParent()
        debugJoystickKnob?.removeFromParent()
        debugAimMarker?.removeFromParent()

        // Debug regions: left/right halves but reduced to 25% height at the bottom.
        // Visible debug rectangles are intentionally semi-transparent so you can see the areas.
        let regionHeight = size.height * 0.25

        // Use an invisible container sprite for each control area and add a visible stroked rectangle
        // (3 px stroke, no transparency) so the debug boxes are clearly visible on device.
        let leftRegion = SKSpriteNode(color: SKColor.clear, size: CGSize(width: size.width/2, height: regionHeight))
        leftRegion.anchorPoint = CGPoint(x: 0, y: 0)
        leftRegion.position = CGPoint(x: 0, y: 0)
        leftRegion.zPosition = 250
        // Stroke shape for left region
        let leftStroke = SKShapeNode(rect: CGRect(origin: CGPoint.zero, size: leftRegion.size))
        leftStroke.strokeColor = SKColor.white
        leftStroke.lineWidth = 3
        leftStroke.fillColor = SKColor.clear
        leftStroke.position = CGPoint.zero
        leftStroke.zPosition = 251
        leftRegion.addChild(leftStroke)
        addChild(leftRegion)
        debugLeftRegion = leftRegion

        let rightRegion = SKSpriteNode(color: SKColor.clear, size: CGSize(width: size.width/2, height: regionHeight))
        rightRegion.anchorPoint = CGPoint(x: 0, y: 0)
        rightRegion.position = CGPoint(x: size.width/2, y: 0)
        rightRegion.zPosition = 250
        // Stroke shape for right region
        let rightStroke = SKShapeNode(rect: CGRect(origin: CGPoint.zero, size: rightRegion.size))
        rightStroke.strokeColor = SKColor.white
        rightStroke.lineWidth = 3
        rightStroke.fillColor = SKColor.clear
        rightStroke.position = CGPoint.zero
        rightStroke.zPosition = 251
        rightRegion.addChild(rightStroke)
        addChild(rightRegion)
        debugRightRegion = rightRegion

        // Knob as a circular shape (prevent square sprite artifacts). Always present and centered in its region when no touch.
        let knobShape = SKShapeNode(circleOfRadius: 18)
        knobShape.strokeColor = SKColor.white.withAlphaComponent(0.9)
        knobShape.lineWidth = 2
        knobShape.fillColor = SKColor.white.withAlphaComponent(0.06)
        knobShape.zPosition = 251
        // Place knob initially at left region center
        knobShape.position = CGPoint(x: leftRegion.position.x + leftRegion.size.width * 0.5, y: leftRegion.position.y + leftRegion.size.height * 0.5)
        // Show touch debug visuals only when running with touch input (mobile player actively playing).
        #if !os(macOS)
        let showDebugNow = (inputController is TouchInput)
        #else
        let showDebugNow = false
        #endif

        // Hide all debug visuals on macOS
        leftRegion.isHidden = !showDebugNow
        rightRegion.isHidden = !showDebugNow
        knobShape.isHidden = !showDebugNow
        addChild(knobShape)
        debugJoystickKnob = knobShape

        // Aim marker as a single SKShapeNode to avoid any accidental square sprite artifacts.
        // Initially visible only when touch input is active.
        let aimCircle = SKShapeNode(circleOfRadius: 16)
        aimCircle.strokeColor = .red
        aimCircle.lineWidth = 2
        aimCircle.fillColor = SKColor.red.withAlphaComponent(0.12)
        aimCircle.zPosition = 251
        aimCircle.isHidden = !showDebugNow
        aimCircle.position = CGPoint(x: rightRegion.position.x + rightRegion.size.width * 0.5, y: rightRegion.position.y + rightRegion.size.height * 0.5)
        addChild(aimCircle)
        debugAimMarker = aimCircle
    }

     // MARK: - Input Handling (forward to input controller + debug keys)
#if os(macOS)
    override func keyDown(with event: NSEvent) {
        (inputController as? KeyboardMouseInput)?.keyDown(event)

        // Debug keys:
        switch event.keyCode {
        case 15: // R
            debugRotationEnabled.toggle()
            if debugRotationEnabled {
                for m in monsters { m.rotationOffset = debugRotationOffset }
            }
        case 12: // Q
            debugRotationOffset -= GameConstants.debugRotationStep
            if debugRotationEnabled {
                for m in monsters { m.rotationOffset = debugRotationOffset }
            }
        case 14: // E
            debugRotationOffset += GameConstants.debugRotationStep
            if debugRotationEnabled {
                for m in monsters { m.rotationOffset = debugRotationOffset }
            }
        default:
            break
        }
    }

    override func keyUp(with event: NSEvent) {
        (inputController as? KeyboardMouseInput)?.keyUp(event)
    }

    override func mouseMoved(with event: NSEvent) {
        // Get mouse location in view coordinates (screen space, not world space)
        guard let view = self.view else { return }

        // Convert mouse location from window coordinates to view coordinates
        let locationInWindow = event.locationInWindow
        let locationInView = view.convert(locationInWindow, from: nil)

        // Convert view coords to scene coords (centered anchor system)
        let sceneCoords = CGPoint(
            x: locationInView.x - view.bounds.width / 2,
            y: locationInView.y - view.bounds.height / 2
        )
        (inputController as? KeyboardMouseInput)?.mouseMoved(to: sceneCoords)
    }

    override func mouseDown(with event: NSEvent) {
        // Check if game over UI should handle this
        if isGameOver {
            let location = event.location(in: self)
            gameOverUI?.handleTouch(at: location)
            return
        }

        (inputController as? KeyboardMouseInput)?.requestShoot()
    }

    override func mouseEntered(with event: NSEvent) {
        crosshair?.isHidden = false
    }

    override func mouseExited(with event: NSEvent) {
        NSCursor.unhide()
        NSCursor.arrow.set()
        crosshair?.isHidden = false
    }
#else
    // Touch handling on iOS/tvOS: forward to TouchInput
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        // Check if game over UI should handle this
        if isGameOver, let touch = touches.first {
            let location = touch.location(in: self)
            gameOverUI?.handleTouch(at: location)
            return
        }

        if let tInput = inputController as? TouchInput {
            tInput.touchesBegan(touches, in: self)
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        if let tInput = inputController as? TouchInput {
            tInput.touchesMoved(touches, in: self)
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        if let tInput = inputController as? TouchInput {
            tInput.touchesEnded(touches, in: self)
        }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        if let tInput = inputController as? TouchInput {
            tInput.touchesCancelled(touches, in: self)
        }
    }
#endif
}
