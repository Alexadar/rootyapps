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
        } else {
            #if os(macOS)
            inputController = KeyboardMouseInput()
            #else
            inputController = TouchInput(scene: self)
            #endif
        }

        // Setup debug visuals via input controller
        inputController?.setupDebugVisuals(in: self)
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
