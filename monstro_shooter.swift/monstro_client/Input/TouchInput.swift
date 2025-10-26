import Foundation
import CoreGraphics
#if !os(macOS)
import UIKit
import SpriteKit

/// Touch-based input for mobile (iOS/tvOS)
/*
Design:
- Landscape layout assumed.
- Left half of the screen acts as a virtual joystick for movement:
  * On touch begin within left half, it'll become "leftTouch" and set a joystick origin.
  * Dragging updates movement vector in range -1..1 based on joystick radius.
- Right half of the screen is for aiming and shooting:
  * Touching the right half becomes "rightTouch". While held, aimPoint() returns that location
    and isShooting() returns true (continuous firing while holding).
  * Moving the right touch updates aim position.
This class is only compiled for non-macOS platforms.
*/
class TouchInput: InputController {
    private weak var scene: SKScene?

    // Track two touches: left (movement) and right (aim/shoot)
    private var leftTouch: UITouch?
    private var rightTouch: UITouch?

    // Joystick state for the left touch (CAMERA SPACE - viewport coordinates)
    private var leftOrigin: CGPoint = .zero
    private var leftCurrent: CGPoint?

    // Last raw touch position for right touch (CAMERA SPACE - viewport coordinates)
    private var rightRawPosition: CGPoint?

    // Virtual origin for right-side aiming area (CAMERA SPACE - viewport coordinates)
    // When a right touch begins we anchor the aim joystick origin to this center so the
    // finger->origin vector defines the aim direction that's then mapped relative to the player.
    private var rightOrigin: CGPoint?

    // Joystick sensitivity / radius for both virtual sticks
    private let joystickRadius: CGFloat = 60.0

    // Debug visual nodes
    private var debugLeftRegion: SKSpriteNode?
    private var debugRightRegion: SKSpriteNode?
    private var debugJoystickKnob: SKNode?
    private var debugAimMarker: SKNode?
    private var debugLine: SKShapeNode?

    init(scene: SKScene? = nil) {
        self.scene = scene
    }

    // Helper: classify a touch as bottom-left or bottom-right control rectangles.
    // Touch controls are in CAMERA space (viewport), not world space.
    // We need to convert touch position from world coords to camera coords.
    private func isBottomLeft(_ pos: CGPoint, in scene: SKScene) -> Bool {
        // Convert world position to camera-relative position
        guard let camera = scene.camera else { return false }
        let cameraPos = CGPoint(x: pos.x - camera.position.x, y: pos.y - camera.position.y)

        let regionHeight = scene.size.height * 0.25
        // Bottom region is from -size.height/2 to -size.height/2 + regionHeight
        let bottomThreshold = -scene.size.height / 2 + regionHeight
        // Left half is from -size.width/2 to 0
        return cameraPos.x < 0 && cameraPos.y < bottomThreshold
    }
    private func isBottomRight(_ pos: CGPoint, in scene: SKScene) -> Bool {
        // Convert world position to camera-relative position
        guard let camera = scene.camera else { return false }
        let cameraPos = CGPoint(x: pos.x - camera.position.x, y: pos.y - camera.position.y)

        let regionHeight = scene.size.height * 0.25
        // Bottom region is from -size.height/2 to -size.height/2 + regionHeight
        let bottomThreshold = -scene.size.height / 2 + regionHeight
        // Right half is from 0 to size.width/2
        return cameraPos.x >= 0 && cameraPos.y < bottomThreshold
    }

    // Forward touch events from the scene. Scene should call these from its touch handlers.
    func touchesBegan(_ touches: Set<UITouch>, in scene: SKScene) {
        self.scene = scene
        guard let camera = scene.camera else { return }

        for t in touches {
            let worldPos = t.location(in: scene)
            // Convert to camera-relative coordinates (same system as debug UI)
            let cameraPos = CGPoint(x: worldPos.x - camera.position.x, y: worldPos.y - camera.position.y)

            if isBottomLeft(worldPos, in: scene) {
                // Bottom-left — movement joystick
                if leftTouch == nil {
                    leftTouch = t
                    // Anchor left joystick origin to the center of the left control rectangle (CAMERA SPACE)
                    let regionHeight = scene.size.height * 0.25
                    leftOrigin = CGPoint(
                        x: -scene.size.width / 4,
                        y: -scene.size.height / 2 + regionHeight / 2
                    )
                    // Store current position in CAMERA SPACE
                    leftCurrent = cameraPos
                }
            } else if isBottomRight(worldPos, in: scene) {
                // Bottom-right — aim / shoot (virtual stick anchored to right-area center)
                if rightTouch == nil {
                    rightTouch = t
                    // Store position in CAMERA SPACE
                    rightRawPosition = cameraPos
                    // Anchor origin to the center of the right control rectangle (CAMERA SPACE)
                    let regionHeight = scene.size.height * 0.25
                    rightOrigin = CGPoint(
                        x: scene.size.width / 4,
                        y: -scene.size.height / 2 + regionHeight / 2
                    )
                }
            } else {
                // Touches outside control areas are ignored (prevents accidental dragging)
            }
        }
    }

    func touchesMoved(_ touches: Set<UITouch>, in scene: SKScene) {
        guard let camera = scene.camera else { return }

        for t in touches {
            let worldPos = t.location(in: scene)
            // Convert to camera-relative coordinates
            let cameraPos = CGPoint(x: worldPos.x - camera.position.x, y: worldPos.y - camera.position.y)

            if let lt = leftTouch, t == lt {
                // Store in CAMERA SPACE
                leftCurrent = cameraPos
            } else if let rt = rightTouch, t == rt {
                // Store in CAMERA SPACE
                rightRawPosition = cameraPos
            }
        }
    }

    func touchesEnded(_ touches: Set<UITouch>, in scene: SKScene) {
        for t in touches {
            if let lt = leftTouch, t == lt {
                leftTouch = nil
                leftCurrent = nil
            } else if let rt = rightTouch, t == rt {
                rightTouch = nil
                rightRawPosition = nil
                rightOrigin = nil
            }
        }
    }

    func touchesCancelled(_ touches: Set<UITouch>, in scene: SKScene) {
        // Treat cancelled as ended
        touchesEnded(touches, in: scene)
    }

    // InputController conformance
    func movementVector() -> CGVector {
        guard let current = leftCurrent else { return CGVector(dx: 0, dy: 0) }
        var dx = current.x - leftOrigin.x
        var dy = current.y - leftOrigin.y

        // Normalize by joystick radius to -1..1
        dx = max(-joystickRadius, min(joystickRadius, dx)) / joystickRadius
        dy = max(-joystickRadius, min(joystickRadius, dy)) / joystickRadius

        return CGVector(dx: dx, dy: dy)
    }

    // Aim point is computed relative to the player's position and constrained to a circle of radius `joystickRadius`.
    // This prevents dragging a crosshair anywhere on the screen and gives a fixed-radius aim control around the character.
    func aimPoint() -> CGPoint? {
        // All coordinates are in CAMERA SPACE, need to convert result to WORLD SPACE for gameplay
        guard let scene = scene, scene.camera != nil else { return nil }
        guard let rtPos = rightRawPosition, let origin = rightOrigin else { return nil }

        // Get player position - try to find player sprite by name
        // Player sprite is in world layer with name "player"
        var playerPos = CGPoint.zero
        if let playerNode = scene.childNode(withName: "//player") {
            playerPos = playerNode.position
        }

        // Vector from area center (origin) to raw finger position (CAMERA SPACE).
        // Copy this vector directly to the player's space so the player aims in the
        // same direction as the finger relative to the right-area center.
        let dx = rtPos.x - origin.x
        let dy = rtPos.y - origin.y

        // Direct-copy mapping: player looks toward (playerPos + (finger - areaCenter)).
        // This mirrors the "movement joystick" behavior where vector is taken relative to its origin.
        // Result is in WORLD SPACE for gameplay
        return CGPoint(x: playerPos.x + dx, y: playerPos.y + dy)
    }

    // For mobile we treat holding the right touch as continuous firing (Crimsonland-like feel)
    func isShooting() -> Bool {
        return rightTouch != nil
    }

    // MARK: - Debug Visuals (InputController protocol)

    func setupDebugVisuals(in scene: SKScene) {
        self.scene = scene

        // Remove existing debug visuals if any
        debugLeftRegion?.removeFromParent()
        debugRightRegion?.removeFromParent()
        debugJoystickKnob?.removeFromParent()
        debugAimMarker?.removeFromParent()
        debugLine?.removeFromParent()

        // Don't create debug visuals if disabled
        guard GameConstants.showDebugControls else { return }

        // Get camera - all touch controls must be added to camera so they follow viewport
        guard let camera = scene.camera else {
            print("[TouchInput] ERROR: No camera found, cannot setup debug visuals")
            return
        }

        // Debug regions: left/right halves at bottom 25% of screen
        // Controls are in camera space (viewport coordinates)
        let regionHeight = scene.size.height * 0.25

        // Left control region (movement joystick)
        let leftRegion = SKSpriteNode(color: .clear, size: CGSize(width: scene.size.width/2, height: regionHeight))
        leftRegion.anchorPoint = CGPoint(x: 0, y: 0)
        // Position in camera space (viewport coordinates)
        leftRegion.position = CGPoint(x: -scene.size.width/2, y: -scene.size.height/2)
        leftRegion.zPosition = 250

        let leftStroke = SKShapeNode(rect: CGRect(origin: .zero, size: leftRegion.size))
        leftStroke.strokeColor = .white
        leftStroke.lineWidth = 3
        leftStroke.fillColor = .clear
        leftStroke.position = .zero
        leftStroke.zPosition = 1
        leftRegion.addChild(leftStroke)
        camera.addChild(leftRegion)  // Add to camera, not scene
        debugLeftRegion = leftRegion

        // Right control region (aim/shoot)
        let rightRegion = SKSpriteNode(color: .clear, size: CGSize(width: scene.size.width/2, height: regionHeight))
        rightRegion.anchorPoint = CGPoint(x: 0, y: 0)
        // Position in camera space (viewport coordinates)
        rightRegion.position = CGPoint(x: 0, y: -scene.size.height/2)
        rightRegion.zPosition = 250

        let rightStroke = SKShapeNode(rect: CGRect(origin: .zero, size: rightRegion.size))
        rightStroke.strokeColor = .white
        rightStroke.lineWidth = 3
        rightStroke.fillColor = .clear
        rightStroke.position = .zero
        rightStroke.zPosition = 1
        rightRegion.addChild(rightStroke)
        camera.addChild(rightRegion)  // Add to camera, not scene
        debugRightRegion = rightRegion

        // Joystick knob (shows movement direction)
        let knobShape = SKShapeNode(circleOfRadius: 18)
        knobShape.strokeColor = UIColor.white.withAlphaComponent(0.9)
        knobShape.lineWidth = 2
        knobShape.fillColor = UIColor.white.withAlphaComponent(0.06)
        knobShape.zPosition = 251
        // Initial position at left region center (camera space)
        knobShape.position = CGPoint(
            x: leftRegion.position.x + leftRegion.size.width * 0.5,
            y: leftRegion.position.y + leftRegion.size.height * 0.5
        )
        camera.addChild(knobShape)  // Add to camera, not scene
        debugJoystickKnob = knobShape

        // Aim marker (shows aim direction)
        let aimCircle = SKShapeNode(circleOfRadius: 16)
        aimCircle.strokeColor = .red
        aimCircle.lineWidth = 2
        aimCircle.fillColor = UIColor.red.withAlphaComponent(0.12)
        aimCircle.zPosition = 251
        // Initial position at right region center (camera space)
        aimCircle.position = CGPoint(
            x: rightRegion.position.x + rightRegion.size.width * 0.5,
            y: rightRegion.position.y + rightRegion.size.height * 0.5
        )
        camera.addChild(aimCircle)  // Add to camera, not scene
        debugAimMarker = aimCircle

        // Debug line at bottom of screen if enabled
        if GameConstants.showDebugLine {
            let lineY = -scene.size.height / 2 + regionHeight
            let linePath = CGMutablePath()
            linePath.move(to: CGPoint(x: -scene.size.width / 2, y: lineY))
            linePath.addLine(to: CGPoint(x: scene.size.width / 2, y: lineY))

            let line = SKShapeNode(path: linePath)
            line.strokeColor = .yellow
            line.lineWidth = 2
            line.zPosition = 252
            camera.addChild(line)  // Add to camera, not scene
            debugLine = line
        }
    }

    func updateDebugVisuals(movementVector: CGVector, aimPoint: CGPoint?) {
        guard let leftRegion = debugLeftRegion, let rightRegion = debugRightRegion else { return }
        guard let scene = scene, let camera = scene.camera else { return }

        // Update joystick knob position based on movement vector (camera space)
        if let knob = debugJoystickKnob {
            let center = CGPoint(
                x: leftRegion.position.x + leftRegion.size.width * 0.5,
                y: leftRegion.position.y + leftRegion.size.height * 0.5
            )
            let radius: CGFloat = 60.0
            knob.position = CGPoint(
                x: center.x + movementVector.dx * radius,
                y: center.y + movementVector.dy * radius
            )
        }

        // Update aim marker position (convert world aim point to camera space)
        if let aimMarker = debugAimMarker {
            if let worldAim = aimPoint {
                // Convert world coordinates to camera-relative coordinates
                let cameraRelativeAim = CGPoint(
                    x: worldAim.x - camera.position.x,
                    y: worldAim.y - camera.position.y
                )
                aimMarker.position = cameraRelativeAim
            } else {
                // Default to right region center when not aiming (camera space)
                let rightCenter = CGPoint(
                    x: rightRegion.position.x + rightRegion.size.width * 0.5,
                    y: rightRegion.position.y + rightRegion.size.height * 0.5
                )
                aimMarker.position = rightCenter
            }
        }
    }

    func hideDebugVisuals() {
        debugLeftRegion?.isHidden = true
        debugRightRegion?.isHidden = true
        debugJoystickKnob?.isHidden = true
        debugAimMarker?.isHidden = true
        debugLine?.isHidden = true
    }

    func showDebugVisuals() {
        debugLeftRegion?.isHidden = false
        debugRightRegion?.isHidden = false
        debugJoystickKnob?.isHidden = false
        debugAimMarker?.isHidden = false
        debugLine?.isHidden = false
    }
}
#endif
