import Foundation
import SwiftUI
import RealityKit

#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

/// How the frog is built and animated. Procedural today; an authored USDZ can slot in later without
/// touching a line of the animation code, because everything moves by transform.
@MainActor
protocol FrogRig: AnyObject {
    var root: Entity { get }
    /// 0 = relaxed, 1 = fully wound up. Drives the crouch while aiming.
    func setCrouch(_ amount: Float)
    /// Stretch along the direction of travel during flight, squash on landing.
    func setFlight(progress: Float, airborne: Bool)
    func setYaw(_ radians: Float)
}

/// The frog, assembled from rounded primitives.
///
/// PROMPT.md §6a is right that this is the correct answer rather than a compromise. The source
/// sprites are 96×64 and 100×116 — froggo 1 was never detailed art — so a stylised low-poly frog in
/// its two greens reads as *more* faithful than an attempt at realism would, and it costs no art
/// budget, no USDZ pipeline, and no rig.
///
/// Everything animates by transform: a crouch is a squash on Y with the legs folding, a launch is a
/// stretch along the velocity, a landing is a squash that settles. That is also exactly what a
/// hand-authored model would do at this camera distance, which is why swapping one in later changes
/// nothing above this file.
@MainActor
final class ProceduralFrogRig: FrogRig {

    let root = Entity()
    private let body = Entity()
    private let bodyMesh: ModelEntity
    private let head: ModelEntity
    private let eyes: [ModelEntity]
    private let pupils: [ModelEntity]
    private let belly: ModelEntity
    private let frontLegs: [ModelEntity]
    private let backLegs: [ModelEntity]

    /// Metres. The frog is half a metre across, which is the scale everything else is derived from.
    private let scale: Float

    init(bodyWidth: Float = 0.8) {
        scale = bodyWidth

        let green = ProceduralFrogRig.material(Palette.frogBody, roughness: 0.85)
        let greenLight = ProceduralFrogRig.material(Palette.frogAccent, roughness: 0.85)
        let white = ProceduralFrogRig.material(Palette.frogHighlight, roughness: 0.6)
        let dark = ProceduralFrogRig.material(Palette.frogOutline, roughness: 0.4)

        // A rounded box, not a cube: the corner radius is most of what turns nine primitives into
        // something that reads as a creature.
        bodyMesh = ModelEntity(
            mesh: .generateBox(width: bodyWidth, height: bodyWidth * 0.62, depth: bodyWidth * 0.86,
                               cornerRadius: bodyWidth * 0.28),
            materials: [green]
        )

        head = ModelEntity(
            mesh: .generateBox(width: bodyWidth * 0.74, height: bodyWidth * 0.46,
                               depth: bodyWidth * 0.5, cornerRadius: bodyWidth * 0.22),
            materials: [greenLight]
        )
        head.position = [0, bodyWidth * 0.26, -bodyWidth * 0.34]

        // Eyes sit high and proud of the head — the single strongest cue that this is a frog.
        eyes = (0..<2).map { i in
            let e = ModelEntity(mesh: .generateSphere(radius: bodyWidth * 0.16), materials: [white])
            e.position = [Float(i == 0 ? -1 : 1) * bodyWidth * 0.22,
                          bodyWidth * 0.52, -bodyWidth * 0.28]
            return e
        }
        pupils = (0..<2).map { i in
            let p = ModelEntity(mesh: .generateSphere(radius: bodyWidth * 0.075), materials: [dark])
            p.position = [Float(i == 0 ? -1 : 1) * bodyWidth * 0.24,
                          bodyWidth * 0.55, -bodyWidth * 0.40]
            return p
        }

        belly = ModelEntity(
            mesh: .generateBox(width: bodyWidth * 0.6, height: bodyWidth * 0.16,
                               depth: bodyWidth * 0.56, cornerRadius: bodyWidth * 0.08),
            materials: [white]
        )
        belly.position = [0, -bodyWidth * 0.24, 0]

        frontLegs = (0..<2).map { i in
            let l = ModelEntity(
                mesh: .generateBox(width: bodyWidth * 0.14, height: bodyWidth * 0.14,
                                   depth: bodyWidth * 0.34, cornerRadius: bodyWidth * 0.06),
                materials: [green]
            )
            l.position = [Float(i == 0 ? -1 : 1) * bodyWidth * 0.34,
                          -bodyWidth * 0.24, -bodyWidth * 0.22]
            return l
        }
        // The hind legs are longer and folded — the silhouette that says "about to jump".
        backLegs = (0..<2).map { i in
            let l = ModelEntity(
                mesh: .generateBox(width: bodyWidth * 0.18, height: bodyWidth * 0.18,
                                   depth: bodyWidth * 0.5, cornerRadius: bodyWidth * 0.08),
                materials: [greenLight]
            )
            l.position = [Float(i == 0 ? -1 : 1) * bodyWidth * 0.36,
                          -bodyWidth * 0.2, bodyWidth * 0.26]
            return l
        }

        body.addChild(bodyMesh)
        body.addChild(head)
        eyes.forEach { body.addChild($0) }
        pupils.forEach { body.addChild($0) }
        body.addChild(belly)
        frontLegs.forEach { body.addChild($0) }
        backLegs.forEach { body.addChild($0) }
        root.addChild(body)
    }

    private static func material(_ color: Color, roughness: Float) -> RealityKit.Material {
        var m = PhysicallyBasedMaterial()
        m.baseColor = .init(tint: PlatformColor(color))
        m.roughness = .init(floatLiteral: roughness)
        m.metallic = .init(floatLiteral: 0)
        return m
    }

    // MARK: - Animation, entirely by transform

    func setCrouch(_ amount: Float) {
        let a = min(max(amount, 0), 1)
        // Squash down and widen slightly — volume roughly preserved, which is what makes a squash
        // read as compression rather than as scaling.
        body.transform.scale = [1 + 0.18 * a, 1 - 0.3 * a, 1 + 0.12 * a]
        body.position.y = -scale * 0.12 * a
        for (i, leg) in backLegs.enumerated() {
            let side: Float = i == 0 ? -1 : 1
            leg.position = [side * scale * (0.36 + 0.05 * a),
                            -scale * (0.2 + 0.06 * a),
                            scale * (0.26 - 0.06 * a)]
            leg.orientation = simd_quatf(angle: -0.5 * a, axis: [1, 0, 0])
        }
    }

    func setFlight(progress: Float, airborne: Bool) {
        guard airborne else {
            setCrouch(0)
            return
        }
        // Stretch hardest at launch, ease back to neutral by apex, then brace for landing.
        let launchStretch = max(0, 1 - progress * 3)
        let landingBrace = max(0, (progress - 0.82) * 5.5)
        let stretch = launchStretch * 0.35
        let brace = landingBrace * 0.28

        body.transform.scale = [1 - stretch * 0.5 + brace * 0.4,
                                1 + stretch - brace * 0.5,
                                1 - stretch * 0.5 + brace * 0.4]
        body.position.y = 0

        // Legs trail behind in flight.
        for (i, leg) in backLegs.enumerated() {
            let side: Float = i == 0 ? -1 : 1
            leg.position = [side * scale * 0.3, -scale * 0.1, scale * (0.34 + 0.12 * launchStretch)]
            leg.orientation = simd_quatf(angle: 0.35 * launchStretch, axis: [1, 0, 0])
        }
        for (i, leg) in frontLegs.enumerated() {
            let side: Float = i == 0 ? -1 : 1
            leg.position = [side * scale * 0.3, -scale * 0.18, -scale * (0.28 + 0.1 * launchStretch)]
        }
    }

    func setYaw(_ radians: Float) {
        root.orientation = simd_quatf(angle: radians, axis: [0, 1, 0])
    }
}

#if canImport(UIKit)
typealias PlatformColor = UIColor
#else
typealias PlatformColor = NSColor
#endif
