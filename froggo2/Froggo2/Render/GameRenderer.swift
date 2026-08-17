import Foundation
import RealityKit
import Metal
import ReachabilityKit

/// The only boundary between the game and RealityKit.
///
/// `GameSession` never names `Entity`, `ModelEntity` or `MeshResource`. That discipline is what
/// makes the future platforms additions rather than rewrites: a watchOS companion (which has no
/// RealityKit at all) supplies a SpriteKit implementation of this protocol and reuses the entire
/// loop and both Kits unchanged.
@MainActor
protocol GameRenderer: AnyObject {
    /// The entity the host view adds to its `RealityView`. Exposed as an `Entity` rather than the
    /// view taking the renderer's content type, so nothing above this protocol has to name a
    /// RealityKit-and-platform-specific content type.
    var sceneRoot: Entity { get }
    func prepare()
    func build(district: CityBlock, config: WorldConfig)
    func setFrog(position: Vec3, yaw: Double, flightProgress: Double, airborne: Bool)
    func showArc(_ samples: [Vec3], landing: Vec3?, reachable: Bool)
    func hideArc()
    func setCamera(target: Vec3, yaw: Double, dt: Double)
    func setFlies(_ positions: [Vec3])
    func rooftop(for entity: Entity) -> RooftopID?
}

/// The RealityKit implementation. A renderer and nothing else — it runs no physics, owns no rules,
/// and simply draws whatever `GameSession` last computed.
@MainActor
final class RealityKitRenderer: GameRenderer {

    private let root = Entity()
    private let cameraRig = Entity()
    private let cameraBoom = Entity()
    private let camera = PerspectiveCamera()
    private let districtRoot = Entity()
    private let frogRig: FrogRig = ProceduralFrogRig()
    private let shadowBlob = ModelEntity()
    private let arcEntity = ModelEntity()
    private let landingRing = ModelEntity()
    private let flyRoot = Entity()

    private var rooftopEntities: [ObjectIdentifier: RooftopID] = [:]
    private var config: WorldConfig = .shipping
    private var currentDistrict: CityBlock?
    private var smoothedCameraTarget: Vec3 = .zero
    private var smoothedCameraYaw: Double = 0

    private var facadeMaterial: RealityKit.Material?

    // MARK: - Setup

    var sceneRoot: Entity { root }

    func prepare() {
        buildLighting()
        buildCameraRig()
        buildSky()
        buildArcAndRing()
        buildShadow()

        root.addChild(districtRoot)
        root.addChild(frogRig.root)
        root.addChild(shadowBlob)
        root.addChild(arcEntity)
        root.addChild(landingRing)
        root.addChild(flyRoot)
    }

    private func buildCameraRig() {
        camera.camera.fieldOfViewInDegrees = 55
        // Above and behind, pitched down ~36°. The angle is doing real work: shallow enough that the
        // towers still read as tall (the drop is the threat), steep enough that the gaps between
        // rooftops are seen close to plan — and judging those gaps IS the game. The first pass sat
        // at 26° and framed half a screen of empty sky with the city crouched in one corner.
        cameraBoom.position = [0, 6.4, 7.4]
        cameraBoom.orientation = simd_quatf(angle: -0.63, axis: [1, 0, 0])
        cameraBoom.addChild(camera)
        cameraRig.addChild(cameraBoom)
        root.addChild(cameraRig)
    }

    private func buildLighting() {
        // One shadow-casting key light. Shadows are the single strongest depth cue in this game: a
        // frog with no shadow over a 3-D gap is genuinely unjudgeable.
        let key = DirectionalLight()
        key.light.intensity = 6200
        key.light.color = .white
        key.shadow = DirectionalLightComponent.Shadow(maximumDistance: 60, depthBias: 2)
        key.orientation = simd_quatf(angle: -0.9, axis: [1, 0, 0]) * simd_quatf(angle: 0.6, axis: [0, 1, 0])
        root.addChild(key)

        // A cool fill from below-front, tinted with the sky's own blue so nothing goes muddy.
        let fill = DirectionalLight()
        fill.light.intensity = 1400
        fill.light.color = PlatformColor(Palette.skyAccent)
        fill.orientation = simd_quatf(angle: 0.7, axis: [1, 0, 0])
        root.addChild(fill)
    }

    /// `NightSky.png` is 1000×500 — a 2:1 strip, which wants a cylinder rather than a sphere.
    ///
    /// Built by hand with reversed winding so it is visible from the inside, and parented to the
    /// camera rig so it yaws with the player and never translates. That is the direct 3-D analogue
    /// of froggo 1's scrolling background tiles.
    private func buildSky() {
        let radius: Float = 260, height: Float = 620, segments = 48

        var positions: [SIMD3<Float>] = []
        var uvs: [SIMD2<Float>] = []
        var indices: [UInt32] = []

        for i in 0...segments {
            let t = Float(i) / Float(segments)
            let angle = t * 2 * .pi
            let x = cos(angle) * radius, z = sin(angle) * radius
            // Tall enough that the rim never enters frame, but the texture is NOT stretched over
            // all of it — the v coordinates run outside 0…1 and the sampler clamps, so the image
            // keeps its proportions in the middle and its top and bottom rows (which are plain sky)
            // extend to fill the rest. Stretching it instead pulled the clouds into vertical streaks.
            positions.append([x, -height * 0.5, z])
            positions.append([x, height * 0.5, z])
            uvs.append([t * 3, 1.9])
            uvs.append([t * 3, -1.4])
        }
        for i in 0..<segments {
            let a = UInt32(i * 2), b = a + 1, c = a + 2, d = a + 3
            // Reversed winding: we are inside the cylinder looking out.
            indices += [a, c, b, b, c, d]
        }

        var descriptor = MeshDescriptor(name: "sky")
        descriptor.positions = MeshBuffers.Positions(positions)
        descriptor.textureCoordinates = MeshBuffers.TextureCoordinates(uvs)
        descriptor.primitives = .triangles(indices)

        guard let mesh = try? MeshResource.generate(from: [descriptor]) else { return }

        var material: RealityKit.Material
        if let texture = try? TextureResource.load(named: "NightSky") {
            let sampler = MTLSamplerDescriptor()
            sampler.sAddressMode = .repeat          // wrap horizontally, around the horizon
            sampler.tAddressMode = .clampToEdge     // clamp vertically, so nothing smears
            sampler.minFilter = .linear
            sampler.magFilter = .linear
            var unlit = UnlitMaterial()
            unlit.color = .init(texture: .init(texture, sampler: .init(sampler)))
            unlit.faceCulling = .none
            material = unlit
        } else {
            var unlit = UnlitMaterial()
            unlit.color = .init(tint: PlatformColor(Palette.sky))
            unlit.faceCulling = .none
            material = unlit
        }

        let sky = ModelEntity(mesh: mesh, materials: [material])
        cameraRig.addChild(sky)
    }

    private func buildArcAndRing() {
        var arcMaterial = UnlitMaterial()
        arcMaterial.color = .init(tint: PlatformColor(Palette.arc))
        arcEntity.model = ModelComponent(mesh: .generateBox(size: 0.001), materials: [arcMaterial])
        arcEntity.isEnabled = false

        var ringMaterial = UnlitMaterial()
        ringMaterial.color = .init(tint: PlatformColor(Palette.ringReachable))
        landingRing.model = ModelComponent(
            mesh: .generatePlane(width: 1.1, depth: 1.1, cornerRadius: 0.55),
            materials: [ringMaterial]
        )
        landingRing.isEnabled = false
    }

    private func buildShadow() {
        // An always-on blob, ray-cast analytically because we own the geometry. It works even if
        // real shadows ever have to be dropped for performance, and it is what tells the player how
        // far below them the roof is.
        var m = UnlitMaterial()
        m.color = .init(tint: PlatformColor(Palette.frogOutline.opacity(0.35)))
        m.blending = .transparent(opacity: .init(floatLiteral: 0.35))
        shadowBlob.model = ModelComponent(
            mesh: .generatePlane(width: 0.55, depth: 0.55, cornerRadius: 0.275),
            materials: [m]
        )
    }

    // MARK: - District

    func build(district: CityBlock, config: WorldConfig) {
        self.config = config
        self.currentDistrict = district

        districtRoot.children.removeAll()
        rooftopEntities.removeAll()

        let facade = facadeMaterial ?? makeFacadeMaterial()
        facadeMaterial = facade

        var roofMaterial = PhysicallyBasedMaterial()
        roofMaterial.baseColor = .init(tint: PlatformColor(Palette.roof))
        roofMaterial.roughness = .init(floatLiteral: 0.9)
        roofMaterial.metallic = .init(floatLiteral: 0)

        var beaconMaterial = UnlitMaterial()
        beaconMaterial.color = .init(tint: PlatformColor(Palette.windowLit))

        for roof in district.rooftops {
            let width = Float(roof.footprint.halfX * 2)
            let depth = Float(roof.footprint.halfZ * 2)
            let height = Float(roof.height)

            let tower = ModelEntity(mesh: towerMesh(width: width, depth: depth, height: height),
                                    materials: [facade])
            tower.position = [Float(roof.footprint.center.x), height / 2, Float(roof.footprint.center.z)]

            // The roof cap: a distinct surface is what makes the landing pad read from behind.
            let cap = ModelEntity(mesh: .generateBox(width: width, height: 0.12, depth: depth,
                                                     cornerRadius: 0.03),
                                  materials: [roofMaterial])
            cap.position = [Float(roof.footprint.center.x), height + 0.06, Float(roof.footprint.center.z)]

            // Tap-to-aim comes free from a collision shape plus a gesture.
            cap.components.set(CollisionComponent(shapes: [.generateBox(size: [width, 0.4, depth])]))
            cap.components.set(InputTargetComponent())
            rooftopEntities[ObjectIdentifier(cap)] = roof.id

            districtRoot.addChild(tower)
            districtRoot.addChild(cap)

            if roof.id == district.goal {
                let beacon = ModelEntity(
                    mesh: .generateBox(width: 0.18, height: 3.2, depth: 0.18, cornerRadius: 0.09),
                    materials: [beaconMaterial]
                )
                beacon.position = [Float(roof.footprint.center.x), height + 1.7,
                                   Float(roof.footprint.center.z)]
                districtRoot.addChild(beacon)
            }
        }
    }

    /// `scraper.png` tiled across the facade.
    ///
    /// RealityKit has no `SKShader`, and `generateBox` emits 0…1 UVs per face, so the tiling has to
    /// come from the mesh's own texture coordinates plus a repeating sampler. That is the direct
    /// analogue of froggo 1's `fract(v_tex_coord * u_textureScale)` shader.
    private func makeFacadeMaterial() -> RealityKit.Material {
        guard let texture = try? TextureResource.load(named: "scraper") else {
            var fallback = PhysicallyBasedMaterial()
            fallback.baseColor = .init(tint: PlatformColor(Palette.facade))
            fallback.roughness = .init(floatLiteral: 0.85)
            return fallback
        }
        let sampler = MTLSamplerDescriptor()
        sampler.sAddressMode = .repeat
        sampler.tAddressMode = .repeat
        sampler.minFilter = .linear
        sampler.magFilter = .linear

        var material = PhysicallyBasedMaterial()
        material.baseColor = .init(texture: .init(texture, sampler: .init(sampler)))
        material.roughness = .init(floatLiteral: 0.88)
        material.metallic = .init(floatLiteral: 0.0)
        return material
    }

    /// A box with UVs scaled so the window texture repeats at a fixed density in metres, matching
    /// froggo 1's window grid rather than stretching one copy over the whole building.
    private func towerMesh(width: Float, depth: Float, height: Float) -> MeshResource {
        let tileMetres: Float = 0.62
        let hw = width / 2, hd = depth / 2, hh = height / 2

        var positions: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        var uvs: [SIMD2<Float>] = []
        var indices: [UInt32] = []

        func face(_ corners: [SIMD3<Float>], normal: SIMD3<Float>, uSpan: Float, vSpan: Float) {
            let base = UInt32(positions.count)
            positions += corners
            normals += Array(repeating: normal, count: 4)
            uvs += [[0, vSpan], [uSpan, vSpan], [uSpan, 0], [0, 0]]
            indices += [base, base + 1, base + 2, base, base + 2, base + 3]
        }

        let uX = width / tileMetres, uZ = depth / tileMetres, v = height / tileMetres

        face([[-hw, -hh, hd], [hw, -hh, hd], [hw, hh, hd], [-hw, hh, hd]], normal: [0, 0, 1], uSpan: uX, vSpan: v)
        face([[hw, -hh, -hd], [-hw, -hh, -hd], [-hw, hh, -hd], [hw, hh, -hd]], normal: [0, 0, -1], uSpan: uX, vSpan: v)
        face([[hw, -hh, hd], [hw, -hh, -hd], [hw, hh, -hd], [hw, hh, hd]], normal: [1, 0, 0], uSpan: uZ, vSpan: v)
        face([[-hw, -hh, -hd], [-hw, -hh, hd], [-hw, hh, hd], [-hw, hh, -hd]], normal: [-1, 0, 0], uSpan: uZ, vSpan: v)
        face([[-hw, hh, hd], [hw, hh, hd], [hw, hh, -hd], [-hw, hh, -hd]], normal: [0, 1, 0], uSpan: uX, vSpan: uZ)

        var descriptor = MeshDescriptor(name: "tower")
        descriptor.positions = MeshBuffers.Positions(positions)
        descriptor.normals = MeshBuffers.Normals(normals)
        descriptor.textureCoordinates = MeshBuffers.TextureCoordinates(uvs)
        descriptor.primitives = .triangles(indices)

        return (try? MeshResource.generate(from: [descriptor]))
            ?? .generateBox(width: width, height: height, depth: depth)
    }

    func rooftop(for entity: Entity) -> RooftopID? {
        rooftopEntities[ObjectIdentifier(entity)]
    }

    // MARK: - Per-frame

    /// Convert a game yaw into a RealityKit Y-rotation.
    ///
    /// The Kit measures yaw as `atan2(x, -z)` — heading 0 faces -Z — so a unit heading is
    /// `(sin θ, -cos θ)`. A RealityKit rotation of θ about +Y maps +Z to `(sin θ, cos θ)`, which
    /// agrees on X and disagrees on Z. Negating reconciles them. Doing it here, once, at the render
    /// boundary keeps the convention question out of the game logic and out of the solver — where
    /// getting it wrong would have been a correctness bug rather than a visual one.
    static func renderYaw(_ gameYaw: Double) -> Double { -gameYaw }

    func setFrog(position: Vec3, yaw: Double, flightProgress: Double, airborne: Bool) {
        frogRig.root.position = [Float(position.x), Float(position.y) + 0.16, Float(position.z)]
        frogRig.setYaw(Float(RealityKitRenderer.renderYaw(yaw)))
        frogRig.setFlight(progress: Float(flightProgress), airborne: airborne)

        // The shadow lands on the highest rooftop directly below the frog, or on the kill plane.
        var groundY = (currentDistrict?.killPlaneY ?? 0)
        if let district = currentDistrict {
            let ground = Vec2(position.x, position.z)
            for roof in district.rooftops where roof.footprint.contains(ground) {
                if roof.height <= position.y { groundY = max(groundY, roof.height) }
            }
        }
        shadowBlob.position = [Float(position.x), Float(groundY) + 0.14, Float(position.z)]
        let drop = Float(max(0.2, position.y - groundY))
        let shrink = max(0.35, 1.4 - drop * 0.18)
        shadowBlob.transform.scale = [shrink, 1, shrink]
        shadowBlob.orientation = simd_quatf(angle: 0, axis: [0, 1, 0])
    }

    func showArc(_ samples: [Vec3], landing: Vec3?, reachable: Bool) {
        guard samples.count > 1 else {
            hideArc()
            return
        }
        arcEntity.isEnabled = true
        arcEntity.model = ModelComponent(mesh: arcMesh(samples), materials: [arcMaterial(reachable)])

        if let landing {
            landingRing.isEnabled = true
            landingRing.position = [Float(landing.x), Float(landing.y) + 0.14, Float(landing.z)]
            var m = UnlitMaterial()
            m.color = .init(tint: PlatformColor(reachable ? Palette.ringReachable : Palette.ringUnreachable))
            landingRing.model?.materials = [m]
        } else {
            landingRing.isEnabled = false
        }
    }

    private func arcMaterial(_ reachable: Bool) -> RealityKit.Material {
        var m = UnlitMaterial()
        m.color = .init(tint: PlatformColor(reachable ? Palette.arc : Palette.ringUnreachable.opacity(0.7)))
        return m
    }

    /// A ribbon through the sampled arc. Cheap, and it reads better than a hairline at distance.
    private func arcMesh(_ samples: [Vec3]) -> MeshResource {
        var positions: [SIMD3<Float>] = []
        var indices: [UInt32] = []
        let halfWidth: Float = 0.045

        for (i, p) in samples.enumerated() {
            let next = i + 1 < samples.count ? samples[i + 1] : samples[max(0, i - 1)]
            var dir = SIMD3<Float>(Float(next.x - p.x), 0, Float(next.z - p.z))
            if simd_length(dir) < 1e-5 { dir = [1, 0, 0] }
            let side = simd_normalize(simd_cross(simd_normalize(dir), SIMD3<Float>(0, 1, 0))) * halfWidth
            positions.append(SIMD3(Float(p.x), Float(p.y), Float(p.z)) - side)
            positions.append(SIMD3(Float(p.x), Float(p.y), Float(p.z)) + side)
        }
        for i in 0..<(samples.count - 1) {
            let a = UInt32(i * 2), b = a + 1, c = a + 2, d = a + 3
            indices += [a, b, c, b, d, c, a, c, b, b, c, d]
        }

        var descriptor = MeshDescriptor(name: "arc")
        descriptor.positions = MeshBuffers.Positions(positions)
        descriptor.primitives = .triangles(indices)
        return (try? MeshResource.generate(from: [descriptor])) ?? .generateBox(size: 0.001)
    }

    func hideArc() {
        arcEntity.isEnabled = false
        landingRing.isEnabled = false
    }

    func setCamera(target: Vec3, yaw: Double, dt: Double) {
        // Exponential smoothing in SECONDS, not a per-frame lerp. Froggo 1's camera used a fixed
        // 0.15 per frame, which made it twice as tight on a 120 Hz device as on a 60 Hz one.
        let k = 1 - exp(-6.0 * dt)
        smoothedCameraTarget = Vec3(
            smoothedCameraTarget.x + (target.x - smoothedCameraTarget.x) * k,
            smoothedCameraTarget.y + (target.y - smoothedCameraTarget.y) * k,
            smoothedCameraTarget.z + (target.z - smoothedCameraTarget.z) * k
        )
        var delta = yaw - smoothedCameraYaw
        while delta > .pi { delta -= 2 * .pi }
        while delta < -.pi { delta += 2 * .pi }
        smoothedCameraYaw += delta * k

        cameraRig.position = [Float(smoothedCameraTarget.x),
                              Float(smoothedCameraTarget.y),
                              Float(smoothedCameraTarget.z)]
        cameraRig.orientation = simd_quatf(angle: Float(RealityKitRenderer.renderYaw(smoothedCameraYaw)),
                                           axis: [0, 1, 0])
    }

    func setFlies(_ positions: [Vec3]) {
        flyRoot.children.removeAll()
        guard let texture = try? TextureResource.load(named: "fly_1") else { return }
        var m = UnlitMaterial(texture: texture)
        m.opacityThreshold = 0.5
        m.faceCulling = .none

        for p in positions {
            let quad = ModelEntity(mesh: .generatePlane(width: 0.3, height: 0.3), materials: [m])
            quad.position = [Float(p.x), Float(p.y) + 0.9, Float(p.z)]
            flyRoot.addChild(quad)
        }
    }

    /// Face every fly at the camera. One quaternion per fly rather than a dependency on
    /// `BillboardComponent` being available and behaving.
    func billboardFlies() {
        let cameraWorld = cameraBoom.position(relativeTo: nil)
        for fly in flyRoot.children {
            let toCamera = cameraWorld - fly.position(relativeTo: nil)
            let yaw = atan2(toCamera.x, toCamera.z)
            fly.orientation = simd_quatf(angle: yaw, axis: [0, 1, 0])
        }
    }
}
