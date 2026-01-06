import Foundation
import CoreGraphics
#if !os(macOS)
import UIKit
import SpriteKit

/// Touch-based input for mobile (iOS/tvOS)
/*
Design:
- Landscape layout assumed.
- Two 4x4cm physical-sized control zones in bottom corners.
- Left zone: virtual joystick for movement
- Right zone: virtual joystick for aiming (auto-fires while touching)
- Physical sizing ensures comfortable controls on all screen sizes.
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
    private var rightOrigin: CGPoint?

    // Cached physical dimensions (calculated once per scene setup)
    private var controlZoneSize: CGFloat = 150  // Will be recalculated
    private var joystickRadius: CGFloat = 60    // Will be recalculated

    // Debug visual nodes
    private var debugLeftRegion: SKSpriteNode?
    private var debugRightRegion: SKSpriteNode?
    private var debugJoystickKnob: SKNode?
    private var debugAimMarker: SKNode?
    private var debugLine: SKShapeNode?

    init(scene: SKScene? = nil) {
        self.scene = scene
        calculatePhysicalDimensions()
    }

    // MARK: - Physical Size Calculation

    /// Convert centimeters to points based on screen PPI
    private static func cmToPoints(_ cm: CGFloat) -> CGFloat {
        let inches = cm / 2.54
        let ppi = estimateScreenPPI()
        let pixels = inches * ppi
        // Convert pixels to points using screen scale
        return pixels / UIScreen.main.scale
    }

    /// Estimate screen PPI based on device type
    private static func estimateScreenPPI() -> CGFloat {
        let screenWidth = UIScreen.main.nativeBounds.width
        let screenHeight = UIScreen.main.nativeBounds.height
        let screenDiagonalPixels = sqrt(screenWidth * screenWidth + screenHeight * screenHeight)

        // Detect device type by screen characteristics
        let isIPad = UIDevice.current.userInterfaceIdiom == .pad

        if isIPad {
            // iPads: 264 PPI (standard), 264 PPI (Pro with ProMotion)
            return 264
        } else {
            // iPhones vary more:
            // - Standard Retina: 326 PPI
            // - Plus/Max models: 401-458 PPI
            // - Pro models: 460 PPI
            // Use screen diagonal to estimate
            if screenDiagonalPixels > 2500 {
                // Larger Pro/Max phones
                return 460
            } else {
                // Standard iPhones
                return 326
            }
        }
    }

    /// Calculate control dimensions based on physical size constants
    private func calculatePhysicalDimensions() {
        controlZoneSize = Self.cmToPoints(GameConstants.touchControlSizeCm)
        joystickRadius = controlZoneSize * GameConstants.touchJoystickRadiusRatio
    }

    // MARK: - Control Zone Geometry

    /// Get left control zone rect (camera space) - bottom-left corner, no margin
    private func leftZoneRect(in scene: SKScene) -> CGRect {
        let x = -scene.size.width / 2
        let y = -scene.size.height / 2
        return CGRect(x: x, y: y, width: controlZoneSize, height: controlZoneSize)
    }

    /// Get right control zone rect (camera space) - bottom-right corner, no margin
    private func rightZoneRect(in scene: SKScene) -> CGRect {
        let x = scene.size.width / 2 - controlZoneSize
        let y = -scene.size.height / 2
        return CGRect(x: x, y: y, width: controlZoneSize, height: controlZoneSize)
    }

    /// Get left zone center (camera space)
    private func leftZoneCenter(in scene: SKScene) -> CGPoint {
        let rect = leftZoneRect(in: scene)
        return CGPoint(x: rect.midX, y: rect.midY)
    }

    /// Get right zone center (camera space)
    private func rightZoneCenter(in scene: SKScene) -> CGPoint {
        let rect = rightZoneRect(in: scene)
        return CGPoint(x: rect.midX, y: rect.midY)
    }

    // Helper: classify a touch as in left or right control zone.
    // Touch controls are in CAMERA space (viewport), not world space.
    // Takes world position, converts to camera space for zone check.
    private func isInLeftZone(_ worldPos: CGPoint, in scene: SKScene) -> Bool {
        guard let camera = scene.camera else { return false }
        let cameraPos = camera.convert(worldPos, from: scene)
        return leftZoneRect(in: scene).contains(cameraPos)
    }

    private func isInRightZone(_ worldPos: CGPoint, in scene: SKScene) -> Bool {
        guard let camera = scene.camera else { return false }
        let cameraPos = camera.convert(worldPos, from: scene)
        return rightZoneRect(in: scene).contains(cameraPos)
    }

    // Forward touch events from the scene. Scene should call these from its touch handlers.
    func touchesBegan(_ touches: Set<UITouch>, in scene: SKScene) {
        self.scene = scene
        calculatePhysicalDimensions()  // Recalculate in case orientation changed
        guard let camera = scene.camera, let view = scene.view else { return }

        for t in touches {
            // Get touch in view coordinates, then convert properly to scene coordinates
            let viewPos = t.location(in: view)
            let worldPos = scene.convertPoint(fromView: viewPos)
            // Use SpriteKit's proper coordinate conversion to camera space
            let cameraPos = camera.convert(worldPos, from: scene)

            if isInLeftZone(worldPos, in: scene) {
                // Left zone — movement joystick (floating origin at touch point)
                if leftTouch == nil {
                    leftTouch = t
                    // Anchor joystick origin to where finger touches (CAMERA SPACE)
                    leftOrigin = cameraPos
                    leftCurrent = cameraPos
                }
            } else if isInRightZone(worldPos, in: scene) {
                // Right zone — aim / shoot (floating origin at touch point)
                if rightTouch == nil {
                    rightTouch = t
                    // Anchor origin to where finger touches (CAMERA SPACE)
                    rightOrigin = cameraPos
                    rightRawPosition = cameraPos
                }
            }
            // Touches outside control zones are ignored (prevents accidental dragging)
        }
    }

    func touchesMoved(_ touches: Set<UITouch>, in scene: SKScene) {
        guard let camera = scene.camera, let view = scene.view else { return }

        for t in touches {
            // Get touch in view coordinates, then convert properly to scene coordinates
            let viewPos = t.location(in: view)
            let worldPos = scene.convertPoint(fromView: viewPos)
            // Use SpriteKit's proper coordinate conversion to camera space
            let cameraPos = camera.convert(worldPos, from: scene)

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
        calculatePhysicalDimensions()

        // Remove existing debug visuals if any
        debugLeftRegion?.removeFromParent()
        debugRightRegion?.removeFromParent()
        debugJoystickKnob?.removeFromParent()
        debugAimMarker?.removeFromParent()
        debugLine?.removeFromParent()

        // Get camera - all touch controls must be added to camera so they follow viewport
        guard let camera = scene.camera else {
            print("[TouchInput] ERROR: No camera found, cannot setup debug visuals")
            return
        }

        // Get zone rects for positioning
        let leftRect = leftZoneRect(in: scene)
        let rightRect = rightZoneRect(in: scene)

        // Left control region (movement joystick) - only show rectangle when debug enabled
        if GameConstants.showDebugControls {
            let leftRegion = SKSpriteNode(color: .clear, size: CGSize(width: controlZoneSize, height: controlZoneSize))
            leftRegion.anchorPoint = CGPoint(x: 0, y: 0)
            leftRegion.position = CGPoint(x: leftRect.minX, y: leftRect.minY)
            leftRegion.zPosition = 250

            let leftStroke = SKShapeNode(rect: CGRect(origin: .zero, size: leftRegion.size), cornerRadius: 8)
            leftStroke.strokeColor = .white
            leftStroke.lineWidth = 2
            leftStroke.fillColor = .clear
            leftStroke.position = .zero
            leftStroke.zPosition = 1
            leftRegion.addChild(leftStroke)
            camera.addChild(leftRegion)
            debugLeftRegion = leftRegion
        }

        // Right control region (aim/shoot) - only show rectangle when debug enabled
        if GameConstants.showDebugControls {
            let rightRegion = SKSpriteNode(color: .clear, size: CGSize(width: controlZoneSize, height: controlZoneSize))
            rightRegion.anchorPoint = CGPoint(x: 0, y: 0)
            rightRegion.position = CGPoint(x: rightRect.minX, y: rightRect.minY)
            rightRegion.zPosition = 250

            let rightStroke = SKShapeNode(rect: CGRect(origin: .zero, size: rightRegion.size), cornerRadius: 8)
            rightStroke.strokeColor = .white
            rightStroke.lineWidth = 2
            rightStroke.fillColor = .clear
            rightStroke.position = .zero
            rightStroke.zPosition = 1
            rightRegion.addChild(rightStroke)
            camera.addChild(rightRegion)
            debugRightRegion = rightRegion
        }

        // Joystick knob (shows movement direction) - ALWAYS show
        let knobShape = SKShapeNode(circleOfRadius: GameConstants.touchIndicatorRadius)
        knobShape.strokeColor = UIColor.white.withAlphaComponent(0.9)
        knobShape.lineWidth = 2
        knobShape.fillColor = UIColor.white.withAlphaComponent(0.06)
        knobShape.zPosition = 251
        // Initial position at left zone center
        knobShape.position = leftZoneCenter(in: scene)
        camera.addChild(knobShape)
        debugJoystickKnob = knobShape

        // Aim marker (shows aim direction) - ALWAYS show
        let aimCircle = SKShapeNode(circleOfRadius: GameConstants.touchAimIndicatorRadius)
        aimCircle.strokeColor = .red
        aimCircle.lineWidth = 2
        aimCircle.fillColor = UIColor.red.withAlphaComponent(0.12)
        aimCircle.zPosition = 251
        // Initial position at right zone center
        aimCircle.position = rightZoneCenter(in: scene)
        camera.addChild(aimCircle)
        debugAimMarker = aimCircle

        // Debug line removed - no longer using full-width regions
    }

    func updateDebugVisuals(movementVector: CGVector, aimPoint: CGPoint?) {
        guard let scene = scene, let camera = scene.camera else { return }

        // Update joystick knob position - under finger when active, zone center when idle
        if let knob = debugJoystickKnob {
            if let fingerPos = leftCurrent {
                // Active: put circle under finger
                knob.position = fingerPos
            } else {
                // Idle: show at zone center
                knob.position = leftZoneCenter(in: scene)
            }
        }

        // Update aim marker position (convert world aim point to camera space)
        if let aimMarker = debugAimMarker {
            if let worldAim = aimPoint {
                // Use proper SpriteKit coordinate conversion
                let cameraRelativeAim = camera.convert(worldAim, from: scene)
                aimMarker.position = cameraRelativeAim
            } else {
                // Default to right zone center when not aiming (camera space)
                aimMarker.position = rightZoneCenter(in: scene)
            }
        }
    }

    func hideDebugVisuals() {
        // Only hide rectangles and debug line, keep circles visible
        debugLeftRegion?.isHidden = true
        debugRightRegion?.isHidden = true
        debugLine?.isHidden = true
    }

    func showDebugVisuals() {
        // Only show rectangles and debug line, circles always visible
        debugLeftRegion?.isHidden = false
        debugRightRegion?.isHidden = false
        debugLine?.isHidden = false
    }
}
#endif
