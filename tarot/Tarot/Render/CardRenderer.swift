import Foundation
import RealityKit
import TarotKit
import CardMotionKit

/// The ONLY boundary between the game and RealityKit (froggo2's `GameRenderer` discipline):
/// imperative setters, no getters but `sceneRoot`, and nothing above this protocol names an
/// `Entity`, `ModelEntity` or `MeshResource`. A future platform without RealityKit supplies a
/// different conformer; the session never changes.
///
/// `sceneRoot` and `lane(for:)` are the two deliberate `Entity` leaks — the SwiftUI layer has
/// to add the scene to a `RealityView` and resolve gesture targets, and typing them as
/// `Entity` here keeps every *content* type private to the implementation.
@MainActor
protocol CardRenderer: AnyObject {
    var sceneRoot: Entity { get }

    /// Build the static scene: table, camera, lights, atmosphere.
    func prepare()

    /// The selected method changed: re-lay the table (pools, labels, card sizing) for this
    /// layout and glide the camera to its computed fit. Config and spread must agree on
    /// slot count — the same pair the kernel and the prompt are given.
    func setLayout(config: MotionConfig, spread: Spread)

    /// Viewport size, on every change — feeds the computed camera fit (aspect-aware).
    func setViewSize(_ size: CGSize)

    /// Build the 78 card entities. `faces` maps the lanes that will be drawn this session to
    /// their face art (only drawn cards ever show a face); every other lane shows the back.
    /// `reversedLanes` land rotated half a turn in plane.
    func build(deck: Deck, faces: [Int: CardArt], back: CardArt, reversedLanes: Set<Int>)

    /// Apply one frame of kernel poses. The renderer is a reader — it runs no motion math.
    func apply(frame: PoseFrame)

    /// Presentation-only time: camera easing, candle flicker. dt comes from the frame loop —
    /// the renderer reads no clock either.
    func tick(dt: Double)

    /// AR placement (iPhone/iPad): true previews the card world floating level in front of
    /// the camera at real-tarot scale (hiding the virtual table); false restores the
    /// virtual stage. A no-op where AR doesn't exist (macOS). The same seam is the future
    /// visionOS mount point — a volume/immersive scene reparents `tableWorld` the same way.
    func setARMode(_ on: Bool)

    /// Freeze the previewing world exactly where it is (a world-space anchor) — the
    /// user's explicit "place it here". `unfixARPlacement` returns to the follow-preview
    /// so it can be placed again.
    func fixateARPlacement()
    func unfixARPlacement()

    /// One-line AR diagnostic for Debug chrome ("previewing/PLACED" + camera/table
    /// positions); empty when AR is off or unsupported.
    func arDebugStatus() -> String

    /// The reveal burst at a card's position; `hero` is the third card's bigger moment.
    func playRevealBurst(lane: Int, hero: Bool)

    /// Dim the table and push the camera in for a major-arcana reveal (the hero interrupt),
    /// or restore it.
    func setHeroFocus(_ on: Bool)

    /// The immersive viewer: dolly the camera to one landed card, or back to the table.
    func setViewerFocus(lane: Int?)

    /// Resolve a hit-test entity back to a card lane.
    func lane(for entity: Entity) -> Int?

    /// The table-plane point (in table units) under a view-space touch — the render
    /// boundary's one coordinate conversion (screen ray → y = 0 plane), done here so the
    /// convention question never leaves this file. The renderer owns the camera, so it is
    /// the only layer that CAN unproject.
    func tablePoint(fromView point: CGPoint, viewSize: CGSize) -> (x: Double, z: Double)
}
