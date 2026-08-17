import Foundation
import CoreGraphics
import ReachabilityKit

/// What the player is currently asking for. Every input path produces one of these and nothing else,
/// which is what keeps the game loop ignorant of whether it is being driven by a thumb, a mouse, a
/// keyboard, or a script.
struct AimIntent: Equatable {
    var yaw: Double
    var power: Double
    var committed: Bool = false
}

/// The input seam.
///
/// Shipping today: drag (touch and mouse) and keyboard. Later, without touching the game loop:
/// a focus-based controller for tvOS, gaze-and-pinch for visionOS, the Digital Crown for a watch
/// companion. `ScriptedAim` already earns the abstraction on its own — reel capture needs a way to
/// drive the game deterministically regardless of what else ever ships.
@MainActor
protocol AimController: AnyObject {
    var isAiming: Bool { get }
    func intent(cameraYaw: Double, screenSize: CGSize) -> AimIntent?
}

/// Froggo 1's slingshot, kept intact: drag *away* from where you want to go.
///
/// The gesture is unchanged from the original — what changes is what the two components mean. In
/// froggo 1 the drag encoded direction-in-the-vertical-plane and power, with rightward drag clamped
/// away entirely (`if direction.x > 0 { direction.x = 0 }`) because a side-on corridor has a
/// forbidden direction. Here the drag encodes **yaw and power**: a 360° field has no forbidden
/// direction, so the clamp is deleted rather than replaced, and the degree of freedom it used to
/// spend on elevation now buys the whole second dimension.
@MainActor
final class DragAimController: AimController {
    private(set) var isAiming = false
    private var start: CGPoint = .zero
    private var current: CGPoint = .zero
    private var committedThisFrame = false

    /// Drag length at which power saturates, as a fraction of the smaller screen dimension.
    ///
    /// Froggo 1 used a flat 150 points (`jumperLength`), which is a sensible thumb-throw on an
    /// iPhone and far too short on an iPad. Screen-relative keeps the *gesture* identical across
    /// devices even though the pixel count is not.
    private let saturationFraction: Double = 0.22
    private let deadZone: Double = 12

    func begin(at point: CGPoint) {
        start = point
        current = point
        isAiming = true
    }

    func update(to point: CGPoint) {
        current = point
    }

    func end() {
        isAiming = false
        committedThisFrame = true
    }

    func cancel() {
        isAiming = false
        committedThisFrame = false
    }

    func intent(cameraYaw: Double, screenSize: CGSize) -> AimIntent? {
        let dx = Double(current.x - start.x)
        let dy = Double(current.y - start.y)
        let length = (dx * dx + dy * dy).squareRoot()

        guard length > deadZone else {
            committedThisFrame = false
            return nil
        }

        let saturation = max(120.0, min(260.0, Double(min(screenSize.width, screenSize.height)) * saturationFraction))
        let power = min(1.0, length / saturation)

        // Screen-space drag, projected onto the ground plane through the camera's yaw, then
        // reversed — the slingshot. Screen +y is downward, which is why the z term is negated back.
        let screenYaw = atan2(-dx, dy)
        let yaw = screenYaw + cameraYaw

        let intent = AimIntent(yaw: yaw, power: power, committed: committedThisFrame)
        committedThisFrame = false
        return intent
    }
}

/// Keyboard aiming for the Mac. Additive, not a replacement — the mouse still works.
@MainActor
final class KeyboardAimController: AimController {
    private(set) var isAiming = false
    private var yaw: Double = 0
    private var power: Double = 0.5
    private var pendingCommit = false

    var currentYaw: Double { yaw }
    var currentPower: Double { power }

    func turn(by delta: Double) {
        yaw += delta
        isAiming = true
    }

    func adjustPower(by delta: Double) {
        power = min(1.0, max(0.05, power + delta))
        isAiming = true
    }

    func commit() { pendingCommit = true }

    func sync(yaw: Double, power: Double) {
        self.yaw = yaw
        self.power = power
    }

    func intent(cameraYaw: Double, screenSize: CGSize) -> AimIntent? {
        guard isAiming else { return nil }
        let intent = AimIntent(yaw: yaw, power: power, committed: pendingCommit)
        pendingCommit = false
        return intent
    }
}
