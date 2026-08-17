import Foundation
import Metal
import RealityKit
import TarotKit
import CardMotionKit

/// A renderer and nothing else — it runs no physics, owns no rules, and simply draws whatever
/// the motion kernel last computed (froggo2's contract, verbatim).
@MainActor
final class RealityCardRenderer: CardRenderer {

    // 1 table unit = 1 metre in scene space. The conversion lives HERE and in `tablePoint` —
    // nowhere else — so the convention question never leaves this file.
    private let scale: Float = 1.0
    private let cardThickness: Float = 0.004

    /// The live layout: slot geometry AND card size come from the same config the kernel
    /// reads (the ten-card cross ships smaller cards). Set via `setLayout`, defaulting to
    /// the shipping three-card layout so `prepare()` alone still builds today's table.
    private var layout = MotionConfig.standard
    private var currentSpread = Spread.threeCard
    private var cardWidth: Float { Float(layout.cardWidth) }
    private var cardHeight: Float { Float(layout.cardLength) }

    /// Viewport aspect (width/height) for the computed camera fit — updated by the SwiftUI
    /// layer on every size change; the camera lerps to each new answer, never cuts.
    private var viewAspect = CameraFit.referenceAspect
    /// Pools + engraved labels, tracked so a method change can strike the old set.
    private var spreadFurniture: [Entity] = []

    let sceneRoot = Entity()
    /// Everything that IS the game — table, pools, deck, cards, shadow, motes — lives under
    /// this one node. The virtual stage keeps it at identity; AR mode reparents it onto a
    /// real-table anchor at real-tarot scale. (The future visionOS scene mounts the same
    /// node into a volume — that is the whole port surface for the world.)
    private let tableWorld = Entity()

    private var cameraRig = Entity()
    private var camera = PerspectiveCamera()
    private var keyLight = DirectionalLight()
    private var fillLight = DirectionalLight()
    private var lampLight = SpotLight()
    private var tableEntity = ModelEntity()

    // The séance props (2026-08-17): candles left, crystal ball right — pure decor, no
    // collision/input, alive on the same clock and light uniform as the cards.
    private var atmosphereProps: [Entity] = []
    /// Every prop model carrying a CustomMaterial. They animate off RealityKit's own
    /// clock inside the shaders, so this list is touched only when the light vector
    /// moves — a dozen candles cost nothing per frame.
    private var propModels: [ModelEntity] = []
    /// The one prop whose shader actually reads the tilt light.
    private var crystalBallModel: ModelEntity?
    /// Per-lane cull state, so the deck's hidden cards are toggled on change, not per frame.
    private var laneIsCulled: [Bool] = []
    private var flameEntities: [Entity] = []             // yaw-billboarded toward the camera
    private var candleLights: [(light: PointLight, phase: Float)] = []

    private var cards: [Entity] = []                  // lane → pose entity
    private var bodies: [Entity] = []                 // lane → body (reversal + stack jitter)
    private var faceModels: [Int: ModelEntity] = [:]  // lanes with a face (drawn cards)
    private var backModels: [Int: ModelEntity] = [:]
    private var laneByEntity: [ObjectIdentifier: Int] = [:]
    /// Pooled contact shadows, one per playable card (never per deck lane).
    private var blobShadows: [ModelEntity] = []
    private var burstEmitters: [Entity] = []

    private var foilLibrary: (any MTLLibrary)?
    private var lastLight = SIMD2<Float>(0, 0)
    private var presentationTime: Double = 0
    // Dimmed 5200 → 3400 in the lamp redesign: the spot owns the scene, the key shapes.
    private var keyBaseIntensity: Float = 3400
    private let lampBaseIntensity: Float = 22000
    private let candleBaseIntensity: Float = 2200

    // Camera easing targets (presentation state only — the kernel knows nothing of cameras).
    private var cameraTarget = SIMD3<Float>(0, 2.75, 1.72)
    private var lookTarget = SIMD3<Float>(0, 0, 0.05)
    private var heroDim: Float = 0        // 0 = table lit, 1 = hero interrupt

    private let homeLook = SIMD3<Float>(0, 0, 0.05)
    /// The computed home boom for the current layout × viewport (CameraFit) — what the
    /// three-card layout calls "home" is exactly the original shipping pose.
    private var fitCamera: SIMD3<Float> {
        SIMD3<Float>(CameraFit.cameraPosition(config: layout, aspect: viewAspect))
    }

    // MARK: AR state (iPhone/iPad; the same seams serve a future visionOS volume)

    private(set) var arModeActive = false
    /// Real-tarot scale: 0.55 TU card length × 0.22 ≈ a 12 cm card on the real table.
    private let arScale: Float = 0.22
    private var arPlacementFixed = false
    #if os(iOS)
    private var arWorldAnchor: AnchorEntity?
    private var arCameraAnchor: AnchorEntity?
    /// Follow-preview offset: level, about 0.75 m ahead and 0.3 m below eye line.
    private let arPreviewOffset = SIMD3<Float>(0, -0.30, -0.80)
    #endif

    // MARK: - Scene

    func prepare() {
        sceneRoot.children.forEach { $0.removeFromParent() }
        tableWorld.children.forEach { $0.removeFromParent() }
        tableWorld.scale = .one
        tableWorld.position = .zero
        tableWorld.orientation = simd_quatf(angle: 0, axis: [0, 1, 0])
        sceneRoot.addChild(tableWorld)

        // A fresh stage owns no AR state (the view was just recreated); setARMode(true)
        // re-establishes it when the mode calls for it.
        arModeActive = false
        arPlacementFixed = false
        #if os(iOS)
        arWorldAnchor = nil
        arCameraAnchor = nil
        #endif

        // Camera on a boom, portrait-framed: the deck at the bottom, three slots above.
        camera = PerspectiveCamera()
        camera.camera.fieldOfViewInDegrees = 55
        cameraRig = Entity()
        cameraRig.addChild(camera)
        sceneRoot.addChild(cameraRig)
        camera.look(at: homeLook, from: fitCamera, relativeTo: nil)
        cameraTarget = fitCamera

        // The staging (2026-08-17 redesign): a hanging lamp OWNS the scene — a spotlight
        // straight above the table whose cone edge lands on the outer engraved ring,
        // matching the shader's lit plateau, with real shadows so cards sit IN the pool
        // of light. The old key becomes a dim shaping fill (its shadow off — one light
        // casts shadows, or the table doubles them), the cool fill dims further.
        lampLight = SpotLight()
        lampLight.light.intensity = 22000
        lampLight.light.color = .init(red: 1.0, green: 0.92, blue: 0.80, alpha: 1)
        lampLight.light.innerAngleInDegrees = 22
        lampLight.light.outerAngleInDegrees = 34
        lampLight.light.attenuationRadius = 6
        // NO shadow map (2026-08-17 perf pass). A shadow-casting spot re-submits every
        // one of the scene's ~250 meshes into a second pass each frame, and what it buys
        // is a sliver of shadow hidden under a card lying flat on a table. The visible
        // part — the soft darkening under a LIFTED card — is drawn by blob quads for a
        // fraction of the cost. Measured cause of the M1 iPad's thermal throttle.
        lampLight.look(at: .zero, from: [0, 2.6, 0.001], relativeTo: nil)
        sceneRoot.addChild(lampLight)

        keyLight = DirectionalLight()
        keyLight.light.intensity = keyBaseIntensity
        keyLight.light.color = .init(red: 1.0, green: 0.93, blue: 0.82, alpha: 1)
        keyLight.look(at: .zero, from: [0.7, 2.4, 0.9], relativeTo: nil)
        sceneRoot.addChild(keyLight)

        fillLight = DirectionalLight()
        fillLight.light.intensity = 600
        fillLight.light.color = .init(red: 0.55, green: 0.62, blue: 0.85, alpha: 1)
        fillLight.look(at: .zero, from: [-1.2, 1.4, -0.8], relativeTo: nil)
        sceneRoot.addChild(fillLight)

        // THE TABLE IS A SOLID (owner, 2026-08-17: "fully 3d volumetric, like in witch
        // houses"). It was a 6 × 6 plane wearing a wood shader, which reads as painted
        // floor the moment the camera pulls back. This is a turned pedestal altar table —
        // the archetype the reference photographs all share: a round slab with a chamfered
        // rim, an apron, a column and a splayed foot. The top face sits at y = 0, which is
        // the plane every other system already calls the table.
        // The shader library is loaded HERE, before anything asks for a CustomMaterial:
        // it lived inside the old table block, and removing that block took it with it —
        // every custom shader in the scene silently fell back at once (brown dome, white
        // cards, no candles). A one-line omission with a whole-scene blast radius.
        foilLibrary = try? MTLCreateSystemDefaultDevice()?.makeDefaultLibrary()

        var woodBase = PhysicallyBasedMaterial()
        woodBase.baseColor = .init(tint: PlatformColor(red: 0.10, green: 0.06, blue: 0.03, alpha: 1))
        woodBase.roughness = 0.45
        woodBase.metallic = 0.0
        var wood: RealityKit.Material = woodBase
        if let library = foilLibrary,
           var magic = try? CustomMaterial(surfaceShader: .init(named: "tableSurface", in: library),
                                           lightingModel: .unlit) {
            // UNLIT, with the room's light baked into a texture. The cloth's shading was
            // always painted by its own shader; being `.lit` on top of that made every
            // one of four million pixels evaluate nine dynamic lights and sample a shadow
            // map to re-light a surface we had already lit. One fetch replaces all of it.
            // No mipmaps: the top is seen at a grazing angle, and a high mip averages a
            // mostly-dark lightmap into mush (measured: the pool arrived at a sixth of
            // its painted value).
            if let map = makeClothLightmap(),
               let texture = try? TextureResource(image: map, withName: "clothLightmap",
                                                  options: .init(semantic: .color,
                                                                 mipmapsMode: .none)) {
                magic.custom.texture = .init(texture)
            }
            wood = magic
        }

        func woodPart(height: Float, radius: Float, centreY: Float) -> ModelEntity {
            let part = ModelEntity(mesh: .generateCylinder(height: height, radius: radius),
                                   materials: [wood])
            part.position.y = centreY
            tableWorld.addChild(part)
            return part
        }

        // Slab first: its top face is the playing surface, and it owns the drag input.
        tableEntity = woodPart(height: 0.09, radius: 1.92, centreY: -0.045)
        tableEntity.collision = CollisionComponent(shapes: [.generateBox(width: 6, height: 0.01, depth: 6)])
        tableEntity.components.set(InputTargetComponent())
        // Chamfer, apron, column, foot — the turned profile, stepped so the silhouette
        // reads from the low camera without a lathe's worth of triangles.
        _ = woodPart(height: 0.055, radius: 1.845, centreY: -0.117)
        _ = woodPart(height: 0.11, radius: 1.28, centreY: -0.200)
        _ = woodPart(height: 0.52, radius: 0.27, centreY: -0.515)
        _ = woodPart(height: 0.13, radius: 0.44, centreY: -0.840)
        _ = woodPart(height: 0.085, radius: 0.98, centreY: -0.948)

        buildAtmosphere()
        rebuildSpreadFurniture()

        // Dust motes drifting through the key light — permanence and idle life.
        var motes = ParticleEmitterComponent()
        motes.emitterShape = .box
        motes.emitterShapeSize = [1.6, 0.8, 1.2]
        motes.mainEmitter.birthRate = 14
        motes.mainEmitter.lifeSpan = 9
        motes.mainEmitter.size = 0.0035
        motes.mainEmitter.color = .constant(.single(PlatformColor(red: 1.0, green: 0.92, blue: 0.75, alpha: 0.35)))
        motes.speed = 0.015
        let moteEntity = Entity()
        moteEntity.position = [0, 0.5, 0]
        moteEntity.components.set(motes)
        tableWorld.addChild(moteEntity)

        presentationTime = 0
    }

    // MARK: - The séance props (2026-08-17 redesign)

    /// Candles left, crystal ball right — everything Metal, everything alive: flames sway
    /// and lick in a shader, wax glows under its fire, the ball bends an internal sky and
    /// answers the same tilt light as the foil. Decor only: no collision, no input, and
    /// placed outside every layout's reach (widest card edge x ≈ ±0.88) AND outside the
    /// camera-fit box — atmosphere at the margins, never competing with cards.
    private func buildAtmosphere() {
        atmosphereProps.forEach { $0.removeFromParent() }
        atmosphereProps.removeAll()
        propModels.removeAll()
        crystalBallModel = nil
        flameEntities.removeAll()
        candleLights.removeAll()
        guard let library = foilLibrary else { return }

        func material(_ shader: String, phase: Float, transparent: Bool,
                      geometry: String? = nil) -> CustomMaterial? {
            let surface = CustomMaterial.SurfaceShader(named: shader, in: library)
            var custom: CustomMaterial?
            if let geometry {
                custom = try? CustomMaterial(surfaceShader: surface,
                                             geometryModifier: .init(named: geometry, in: library),
                                             lightingModel: .lit)
            } else {
                custom = try? CustomMaterial(surfaceShader: surface, lightingModel: .lit)
            }
            guard var m = custom else { return nil }
            // (lightX, lightZ, flicker phase, spare) — time comes from the shader clock.
            m.custom.value = SIMD4<Float>(0, 0, phase, 0)
            if transparent {
                m.blending = .transparent(opacity: 1.0)
                m.faceCulling = .none
            }
            return m
        }

        for candle in PropPlacement.candles {
            let radius = Float(candle.radius), height = Float(candle.height)
            let phase = Float(candle.phase)
            guard let wax = material("candleWax", phase: phase, transparent: false),
                  let flameMat = material("candleFlame", phase: phase, transparent: true,
                                          geometry: "candleFlameSway") else { continue }
            let root = Entity()
            root.position = [Float(candle.x), 0, Float(candle.z)]

            let body = ModelEntity(mesh: .generateCylinder(height: height, radius: radius),
                                   materials: [wax])
            body.position.y = height / 2
            root.addChild(body)
            propModels.append(body)

            // The melted lip — the silhouette detail that keeps it from reading "cylinder".
            let lip = ModelEntity(mesh: .generateCylinder(height: 0.014, radius: radius * 1.06),
                                  materials: [wax])
            lip.position.y = height - 0.007
            root.addChild(lip)
            propModels.append(lip)

            let wickMat = UnlitMaterial(color: PlatformColor(red: 0.16, green: 0.10, blue: 0.07, alpha: 1))
            let wick = ModelEntity(mesh: .generateCylinder(height: 0.010, radius: 0.0016),
                                   materials: [wickMat])
            wick.position.y = height + 0.004
            root.addChild(wick)

            // The quad is deliberately far larger than the fire: the shader's halo has to
            // die inside it, and a quad that ends where the flame ends shows its own edge
            // (the blocky flames seen on device).
            let flameH = radius * 6.0
            let flame = ModelEntity(mesh: .generatePlane(width: flameH * 0.85, height: flameH),
                                    materials: [flameMat])
            // Fire casts light, never a shadow — a lit quad in the spot's shadow pass
            // would stamp a rectangle on the table.
            flame.components.set(DynamicLightShadowComponent(castsShadow: false))
            // The flame hangs off a holder pivoted AT THE WICK, and the holder turns to
            // face the camera outright — not just in yaw. A yaw-only billboard seen from
            // this camera's steep angle foreshortens into a hard little triangle lying on
            // the wax (seen on device); pivoting at the wick keeps the fire rooted while
            // the quad always presents its full face.
            let holder = Entity()
            holder.position.y = height + 0.008
            flame.position.y = flameH / 2      // quad centre above the pivot
            holder.addChild(flame)
            root.addChild(holder)
            propModels.append(flame)
            flameEntities.append(holder)

            if candle.lit {
                let glow = PointLight()
                glow.light.intensity = candleBaseIntensity
                glow.light.color = .init(red: 1.0, green: 0.62, blue: 0.28, alpha: 1)
                glow.light.attenuationRadius = 1.5
                glow.position = [0, height + 0.09, 0]
                root.addChild(glow)
                candleLights.append((glow, phase))
            }

            tableWorld.addChild(root)
            atmosphereProps.append(root)
        }

        // The crystal ball, on a low engraved stand, with its caustic on the cloth.
        if let causticMat = material("crystalCaustic", phase: 0, transparent: true),
           var ballMat = material("crystalBall", phase: 0, transparent: false) {
            // The room, painted as an equirectangular map, is what the glass reflects and
            // refracts. Generated from the ACTUAL scene — this lamp, these gold rings,
            // these candle flames — so the ball shows the room it is standing in.
            if let env = makeRoomEnvironment(),
               let texture = try? TextureResource(image: env, withName: "roomEnv",
                                                  options: .init(semantic: .color)) {
                ballMat.custom.texture = .init(texture)
            }
            let stand = Entity()
            stand.position = [Float(PropPlacement.ballCentre.x), 0,
                              Float(PropPlacement.ballCentre.z)]

            var standMat = PhysicallyBasedMaterial()
            standMat.baseColor = .init(tint: PlatformColor(red: 0.10, green: 0.08, blue: 0.07, alpha: 1))
            standMat.roughness = 0.5
            standMat.metallic = 0.2
            let base = ModelEntity(mesh: .generateCylinder(height: 0.035, radius: 0.085),
                                   materials: [standMat])
            base.position.y = 0.0175
            stand.addChild(base)

            var rimMat = PhysicallyBasedMaterial()
            rimMat.baseColor = .init(tint: PlatformColor(red: 0.88, green: 0.72, blue: 0.40, alpha: 1))
            rimMat.roughness = 0.25
            rimMat.metallic = 1.0
            let rim = ModelEntity(mesh: .generateCylinder(height: 0.006, radius: 0.088),
                                  materials: [rimMat])
            rim.position.y = 0.035
            stand.addChild(rim)

            let ballR = Float(PropPlacement.ballRadius)
            let ball = ModelEntity(mesh: .generateSphere(radius: ballR), materials: [ballMat])
            ball.position.y = 0.035 + ballR
            stand.addChild(ball)
            propModels.append(ball)
            crystalBallModel = ball

            let caustic = ModelEntity(mesh: .generatePlane(width: 0.52, depth: 0.38),
                                      materials: [causticMat])
            caustic.position.y = 0.0013
            caustic.components.set(DynamicLightShadowComponent(castsShadow: false))
            stand.addChild(caustic)
            propModels.append(caustic)

            tableWorld.addChild(stand)
            atmosphereProps.append(stand)
        }
    }

    /// The cloth's light, baked. Everything that lights this table is static — a lamp
    /// bolted overhead and candles that never move — so it is painted once into a 256²
    /// texture (the owner's own suggestion: lightmaps) instead of being recomputed by
    /// nine dynamic lights on four million pixels, sixty times a second. Painted from
    /// PropPlacement, so a moved candle moves its pool with it.
    private func makeClothLightmap() -> CGImage? {
        let n = 256
        let extent: Float = 6.0                    // the table plane is 6 × 6
        let warm = SIMD3<Float>(1.05, 0.99, 0.90)  // lamplight through candle glass
        let candleGlow = SIMD3<Float>(1.00, 0.52, 0.20)
        var pixels = [UInt8](repeating: 0, count: n * n * 4)
        for j in 0..<n {
            let z = ((Float(j) + 0.5) / Float(n) - 0.5) * extent
            for i in 0..<n {
                let x = ((Float(i) + 0.5) / Float(n) - 0.5) * extent
                let r = (x * x + z * z).squareRoot()

                // The hanging lamp: a lit plateau over the play circle, a soft penumbra,
                // then the room falls away. Exactly the curve the shader used to compute.
                let lamp = 1 - Self.smootherstep(1.05, 1.70, r)
                var light = SIMD3<Float>(repeating: 0.06 + 0.94 * lamp)
                light *= SIMD3<Float>(repeating: 1) + (warm - SIMD3<Float>(repeating: 1)) * lamp

                // Each candle pools its own warmth on the cloth around its foot.
                for candle in PropPlacement.candles {
                    let dx = x - Float(candle.x), dz = z - Float(candle.z)
                    let d2 = dx * dx + dz * dz
                    let size = Float(candle.radius) * 7          // taller candles reach further
                    light += candleGlow * (exp(-d2 / (size * size)) * 0.55)
                }

                // Gamma-encode: the texture is sampled with a .color semantic, so Metal
                // sRGB-decodes it on the way in. Storing the raw linear value crushes
                // every mid-tone by ~2.4× — measured against the pre-optimisation frame,
                // which is how this was caught.
                let k = (j * n + i) * 4
                let encoded = SIMD3<Float>(pow(min(max(light.x, 0), 1), 1 / 2.2),
                                           pow(min(max(light.y, 0), 1), 1 / 2.2),
                                           pow(min(max(light.z, 0), 1), 1 / 2.2))
                pixels[k] = UInt8(encoded.x * 255)
                pixels[k + 1] = UInt8(encoded.y * 255)
                pixels[k + 2] = UInt8(encoded.z * 255)
                pixels[k + 3] = 255
            }
        }
        guard let provider = CGDataProvider(data: Data(pixels) as CFData) else { return nil }
        return CGImage(width: n, height: n, bitsPerComponent: 8, bitsPerPixel: 32,
                       bytesPerRow: n * 4, space: CGColorSpaceCreateDeviceRGB(),
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: true,
                       intent: .defaultIntent)
    }

    /// The room as an equirectangular image, painted from where the crystal ball stands:
    /// the lamp overhead, the cloth and its gold rings below (ray-cast to the table plane,
    /// so the rings land where they really are), and every candle flame at its true
    /// bearing. This is what the glass reflects and refracts — the ball shows THIS room,
    /// which is the whole difference between glass and a painted bauble.
    private func makeRoomEnvironment() -> CGImage? {
        let w = 256, h = 128
        let eye = SIMD3<Float>(Float(PropPlacement.ballCentre.x),
                               0.035 + Float(PropPlacement.ballRadius),
                               Float(PropPlacement.ballCentre.z))
        let flames = PropPlacement.candles.map {
            SIMD3<Float>(Float($0.x), Float($0.height) + 0.04, Float($0.z))
        }
        let toLamp = simd_normalize(SIMD3<Float>(0, 2.6, 0) - eye)

        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        for py in 0..<h {
            let v = (Float(py) + 0.5) / Float(h)
            let theta = v * .pi
            let sinT = sin(theta), cosT = cos(theta)
            for px in 0..<w {
                let u = (Float(px) + 0.5) / Float(w)
                let phi = (u - 0.5) * 2 * .pi
                let dir = SIMD3<Float>(sinT * cos(phi), cosT, sinT * sin(phi))
                var c = SIMD3<Float>(0.010, 0.009, 0.022)          // the dark room

                if dir.y > 0.015 {
                    let d = max(0, simd_dot(dir, toLamp))
                    c += SIMD3<Float>(1.0, 0.88, 0.66) * pow(d, 300) * 2.6     // the bulb
                    c += SIMD3<Float>(0.34, 0.27, 0.20) * pow(d, 7) * 0.30     // its wash
                } else if dir.y < -0.02 {
                    // Ray-cast down to the cloth: the rings appear where they truly are.
                    let t = -eye.y / dir.y
                    let hx = eye.x + dir.x * t, hz = eye.z + dir.z * t
                    let r = (hx * hx + hz * hz).squareRoot()
                    if r < 4 {
                        let d1 = abs(r - 1.05), d2 = abs(r - 0.72)
                        let gold: Float = exp(-d1 * d1 * 700) * 0.9 + exp(-d2 * d2 * 900) * 0.6
                        let lamp: Float = 1 - Self.smootherstep(1.05, 1.70, r)
                        let level: Float = 0.05 + 0.95 * lamp
                        var cloth = SIMD3<Float>(0.038, 0.031, 0.070)
                        cloth += SIMD3<Float>(0.88, 0.72, 0.40) * gold
                        c += cloth * level
                    }
                }

                for flame in flames {
                    let d = max(0, simd_dot(dir, simd_normalize(flame - eye)))
                    c += SIMD3<Float>(1.0, 0.52, 0.18) * pow(d, 1600) * 3.0    // the flame
                    c += SIMD3<Float>(1.0, 0.44, 0.16) * pow(d, 90) * 0.12     // its glow
                }

                let i = (py * w + px) * 4
                pixels[i] = UInt8(min(255, max(0, c.x * 255)))
                pixels[i + 1] = UInt8(min(255, max(0, c.y * 255)))
                pixels[i + 2] = UInt8(min(255, max(0, c.z * 255)))
                pixels[i + 3] = 255
            }
        }
        guard let provider = CGDataProvider(data: Data(pixels) as CFData) else { return nil }
        return CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32,
                       bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: true,
                       intent: .defaultIntent)
    }

    private static func smootherstep(_ a: Float, _ b: Float, _ x: Float) -> Float {
        let t = min(max((x - a) / (b - a), 0), 1)
        return t * t * (3 - 2 * t)
    }

    /// The method changed (or the stage was rebuilt): strike the old pools, labels and
    /// shadow, and lay the table for the selected spread. Geometry comes from the SAME
    /// MotionConfig the kernel reads — one source of truth, so a retune moves the markers
    /// and the physics together. The camera lerps to its recomputed fit; nothing cuts.
    func setLayout(config: MotionConfig, spread: Spread) {
        layout = config
        currentSpread = spread
        rebuildSpreadFurniture()
        cameraTarget = fitCamera
    }

    /// Viewport size (SwiftUI layer, on every change): feeds the computed camera fit.
    func setViewSize(_ size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        viewAspect = Double(size.width / size.height)
        cameraTarget = fitCamera
    }

    private func rebuildSpreadFurniture() {
        spreadFurniture.forEach { $0.removeFromParent() }
        spreadFurniture.removeAll()

        // Contact shadows: one pooled soft blob per playable card (froggo2's analytic
        // shadow, generalised now that the unlit cloth receives no shadow map). The pool
        // is sized to the layout — never to the 78-card deck — so this costs a dozen
        // small transparent quads at most.
        var blobMaterial: RealityKit.Material = UnlitMaterial(color: PlatformColor(white: 0, alpha: 0.4))
        if let library = foilLibrary,
           var soft = try? CustomMaterial(surfaceShader: .init(named: "softBlob", in: library),
                                          lightingModel: .unlit) {
            soft.blending = .transparent(opacity: 1.0)
            soft.faceCulling = .none
            blobMaterial = soft
        }
        blobShadows = (0..<(layout.slotCount + 2)).map { _ in
            let blob = ModelEntity(mesh: .generatePlane(width: cardWidth * 1.7,
                                                        depth: cardHeight * 1.5),
                                   materials: [blobMaterial])
            blob.position = [0, 0.0015, 0]
            blob.scale = .zero
            blob.components.set(DynamicLightShadowComponent(castsShadow: false))
            tableWorld.addChild(blob)
            spreadFurniture.append(blob)
            return blob
        }

        // The lighted positions: faint pools of warm light where cards can land.
        let poolWidth = cardWidth * 1.38
        for s in 0..<layout.slotCount {
            var glow = UnlitMaterial(color: PlatformColor(red: 1.0, green: 0.84, blue: 0.55, alpha: 0.16))
            glow.blending = .transparent(opacity: 0.16)
            let pool = ModelEntity(mesh: .generatePlane(width: poolWidth,
                                                        depth: cardHeight * 1.24,
                                                        cornerRadius: 0.06),
                                   materials: [glow])
            pool.position = [Float(layout.slotX[s]) * scale, 0.0008, Float(layout.slotZ[s]) * scale]
            // A slot co-located with an earlier one (the crossing card) gets its OWN pool,
            // ROTATED to the slot's yaw and raised a hair: the sideways glow peeks out
            // from under whatever lands on the slot beneath, so the player can SEE that a
            // card is meant to lie across here (owner, 2026-08-17: "it's not
            // understandable where to cross").
            let sharesPool = (0..<s).contains {
                abs(layout.slotX[$0] - layout.slotX[s]) < 0.001
                    && abs(layout.slotZ[$0] - layout.slotZ[s]) < 0.001
            }
            // Above the pool, unless a NEIGHBOURING CARD would land on top of the label.
            // In the ten-card cross the crown sits 0.40 from the heart and is 0.33 long,
            // leaving 7 cm of table — less than a label — so the heart's name ended up
            // under the crown card. Where that happens the label moves inside its own
            // pool, which is empty exactly while the reader still needs to read it.
            let labelDepth = cardHeight * 0.62 + 0.02
            let wantZ = Float(layout.slotZ[s]) * scale - labelDepth
            let blocked = (0..<layout.slotCount).contains { other in
                other != s
                    && abs(Float(layout.slotX[other]) - Float(layout.slotX[s])) < poolWidth
                    && abs(Float(layout.slotZ[other]) * scale - wantZ) < cardHeight * 0.62
            }
            if sharesPool {
                pool.orientation = simd_quatf(angle: Float(layout.slotYaw[s]), axis: [0, 1, 0])
                pool.position.y = 0.0011
            }
            tableWorld.addChild(pool)
            spreadFurniture.append(pool)

            // The position's name, engraved flat on the cloth just past its pool — the
            // player knows what each place means BEFORE drawing. Names come from the same
            // Spread the whole app reads.
            let name = currentSpread.positions.indices.contains(s)
                ? L.loc(currentSpread.positions[s].name).uppercased(with: Locale.current) : ""
            // Label type scales with the card so ten small pools get ten small names.
            let fontSize = 0.052 * Double(cardWidth) / 0.32
            let textMesh = MeshResource.generateText(name, extrusionDepth: 0.0008,
                                                     font: .systemFont(ofSize: fontSize, weight: .semibold),
                                                     containerFrame: .zero,
                                                     alignment: .center,
                                                     lineBreakMode: .byClipping)
            var labelMaterial = UnlitMaterial(color: PlatformColor(red: 0.86, green: 0.72, blue: 0.42, alpha: 0.55))
            labelMaterial.blending = .transparent(opacity: 0.55)
            let label = ModelEntity(mesh: textMesh, materials: [labelMaterial])
            // Lie flat on the table, reading upright from the player's seat.
            label.orientation = simd_quatf(angle: -.pi / 2, axis: [1, 0, 0])
            let bounds = textMesh.bounds
            // FIT THE LABEL TO ITS POOL. Position names run from "Focus" to "Hopes and
            // Fears", and the ten-card cross packs its pools tight — at a fixed size the
            // long ones collided with their neighbours and ran off the table edge (seen
            // on device). Pools never overlap, so a label that fits inside its own pool
            // can never touch another; this makes that true by construction rather than
            // by choosing short names.
            // A label that sits INSIDE its pool must be narrower than the CARD, or its
            // ends peek out from behind the card that lands on it.
            let maxLabelWidth = blocked ? cardWidth * 0.92 : poolWidth
            let fit = min(1, maxLabelWidth / max(Float(bounds.extents.x), 0.0001))
            label.scale = SIMD3<Float>(repeating: fit)
            let centreOffset = (bounds.min.x + bounds.extents.x / 2) * fit
            if sharesPool {
                // The crossing slot's label turns WITH its card: engraved vertically
                // beside the rotated pool, so the sideways name reads as "the sideways
                // card goes here" — and it stays clear of the slot-below's far-side label
                // (the first near-side placement collided with it, seen on device).
                label.orientation = simd_quatf(angle: Float(layout.slotYaw[s]), axis: [0, 1, 0])
                    * simd_quatf(angle: -.pi / 2, axis: [1, 0, 0])
                label.position = [Float(layout.slotX[s]) * scale + cardHeight * 0.5 + 0.05,
                                  0.0016,
                                  Float(layout.slotZ[s]) * scale + centreOffset]
            } else if blocked {
                label.position = [Float(layout.slotX[s]) * scale - centreOffset, 0.0016,
                                  Float(layout.slotZ[s]) * scale]
            } else {
                // Far side of the pool: the deck sits below the middle slot and was hiding
                // a below-pool label; above-pool also means a landed card never covers its
                // name.
                label.position = [Float(layout.slotX[s]) * scale - centreOffset, 0.0016, wantZ]
            }
            tableWorld.addChild(label)
            spreadFurniture.append(label)
        }
    }

    // MARK: - Cards

    private func foilMaterial(art: CardArt, tier: Float) -> RealityKit.Material {
        var pbr = PhysicallyBasedMaterial()
        pbr.roughness = 0.6
        pbr.metallic = 0.0
        guard let library = foilLibrary,
              let faceTex = try? TextureResource.generate(from: art.face, options: .init(semantic: .color)),
              let maskTex = try? TextureResource.generate(from: art.foilMask, options: .init(semantic: .raw))
        else { return pbr }
        pbr.baseColor = .init(texture: .init(faceTex))
        do {
            let surface = CustomMaterial.SurfaceShader(named: "cardFoilSurface", in: library)
            var custom = try CustomMaterial(from: pbr, surfaceShader: surface)
            custom.custom.texture = .init(maskTex)
            custom.custom.value = SIMD4<Float>(0, 0, 0, tier)
            return custom
        } catch {
            // No shader (first build, or an exotic GPU): the card still renders, just matte.
            return pbr
        }
    }

    func build(deck: Deck, faces: [Int: CardArt], back: CardArt, reversedLanes: Set<Int>) {
        cards.forEach { $0.removeFromParent() }
        cards = []
        bodies = []
        faceModels = [:]
        backModels = [:]
        laneByEntity = [:]

        let backMaterial = foilMaterial(art: back, tier: 1)
        var edgeMaterial = PhysicallyBasedMaterial()
        edgeMaterial.baseColor = .init(tint: PlatformColor(red: 0.92, green: 0.89, blue: 0.80, alpha: 1))
        edgeMaterial.roughness = 0.8

        let facePlane = MeshResource.generatePlane(width: cardWidth, depth: cardHeight, cornerRadius: 0.018)
        let edgeBox = MeshResource.generateBox(width: cardWidth, height: cardThickness,
                                               depth: cardHeight, cornerRadius: 0.004)

        laneIsCulled = [Bool](repeating: false, count: deck.cards.count)
        for lane in 0..<deck.cards.count {
            let pose = Entity()
            let body = Entity()
            pose.addChild(body)

            // Baked-in body orientation: reversal (half a turn in plane) + a whisper of
            // per-lane yaw so the stack reads as hand-set, not machined.
            let jitter = Float(LaneNoise.uniforms(seed: 5150, tick: 0, stream: 9,
                                                  worlds: 1, lanes: deck.cards.count).data[lane] - 0.5) * 0.05
            let reversal: Float = reversedLanes.contains(lane) ? .pi : 0
            body.orientation = simd_quatf(angle: jitter + reversal, axis: [0, 1, 0])

            let edges = ModelEntity(mesh: edgeBox, materials: [edgeMaterial])
            body.addChild(edges)

            // Back faces up while the card lies face-down in the deck.
            let backModel = ModelEntity(mesh: facePlane, materials: [backMaterial])
            backModel.position = [0, cardThickness / 2 + 0.0004, 0]
            body.addChild(backModel)
            backModels[lane] = backModel

            // The face: mounted looking down, pre-rotated half a turn about Z, so the card's
            // flip (π about Z) presents it upright and unmirrored.
            if let art = faces[lane] {
                let faceModel = ModelEntity(mesh: facePlane,
                                            materials: [foilMaterial(art: art, tier: art.isMajor ? 2 : 1)])
                faceModel.orientation = simd_quatf(angle: .pi, axis: [0, 0, 1])
                faceModel.position = [0, -cardThickness / 2 - 0.0004, 0]
                body.addChild(faceModel)
                faceModels[lane] = faceModel
            } else {
                // Undrawn cards still need an underside; a second back keeps the deck opaque.
                let under = ModelEntity(mesh: facePlane, materials: [backMaterial])
                under.orientation = simd_quatf(angle: .pi, axis: [0, 0, 1])
                under.position = [0, -cardThickness / 2 - 0.0004, 0]
                body.addChild(under)
            }

            // Hit-testing: collision on the pose entity; taps resolve through laneByEntity.
            pose.components.set(CollisionComponent(shapes: [.generateBox(width: cardWidth,
                                                                         height: 0.02,
                                                                         depth: cardHeight)]))
            pose.components.set(InputTargetComponent())
            laneByEntity[ObjectIdentifier(pose)] = lane
            for child in [body, edges] { laneByEntity[ObjectIdentifier(child)] = lane }
            if let f = faceModels[lane] { laneByEntity[ObjectIdentifier(f)] = lane }
            if let b = backModels[lane] { laneByEntity[ObjectIdentifier(b)] = lane }

            cards.append(pose)
            bodies.append(body)
            tableWorld.addChild(pose)
        }
    }

    // MARK: - Per-frame

    func apply(frame: PoseFrame) {
        guard !cards.isEmpty else { return }
        let c = cards.count
        let light = SIMD2<Float>(Float(frame.lightX.data[0]), Float(frame.lightZ.data[0]))

        var highestLifted: (lane: Int, y: Double)? = nil

        for lane in 0..<c {
            let x = Float(frame.x.data[lane]) * scale
            let y = Float(frame.y.data[lane]) * scale
            let z = Float(frame.z.data[lane]) * scale
            let entity = cards[lane]
            entity.position = [x, y + cardThickness / 2, z]

            let tiltX = Float(frame.tiltX.data[lane])
            let zAngle = Float(frame.tiltZ.data[lane] + frame.flipAngle.data[lane])
            let yaw = Float(frame.yaw.data[lane])
            // Yaw outermost: the crossing card turns about the table normal as a whole,
            // tilt and flip riding inside that turn. Zero for every other layout's slots.
            entity.orientation = simd_quatf(angle: yaw, axis: [0, 1, 0])
                * simd_quatf(angle: tiltX, axis: [1, 0, 0])
                * simd_quatf(angle: zAngle, axis: [0, 0, 1])

            let s = Float(frame.scale.data[lane])
            let squash = Float(frame.squash.data[lane])
            entity.scale = [s * squash, s, s]

            let lifted = frame.y.data[lane]
            if lifted > 0.01, lifted > (highestLifted?.y ?? 0) { highestLifted = (lane, lifted) }
        }

        _ = highestLifted
        // Contact shadows for every card that is out of the deck, growing with height.
        var blobIndex = 0
        for lane in 0..<c where frame.phase.data[lane] != MotionWorld.Phase.inDeck {
            guard blobIndex < blobShadows.count else { break }
            let blob = blobShadows[blobIndex]
            blobIndex += 1
            let grow = 1 + Float(frame.y.data[lane]) * 2.4
            blob.position = [Float(frame.x.data[lane]) * scale, 0.0015,
                             Float(frame.z.data[lane]) * scale]
            blob.scale = [grow, 1, grow]
        }
        for i in blobIndex..<blobShadows.count { blobShadows[i].scale = .zero }

        // Culling the buried deck was tried here and REVERTED (2026-08-17). Two reasons,
        // both worth keeping written down: the cards carry a per-lane jitter, so hiding a
        // buried card's back plane exposes the cream top face of its edge box and the
        // whole stack turns into a white slab; and on Apple's tile-based GPUs the win was
        // never large anyway — occluded OPAQUE geometry is rejected by hidden-surface
        // removal before it is ever shaded. The costs worth cutting were the shadow pass
        // and the fullscreen lit shader, and those are gone.
        _ = laneIsCulled

        // Foil uniforms: only the lanes that can catch the eye — everything not buried in
        // the stack. Updating a CustomMaterial means reassigning it (materials are values),
        // so the update set is kept small.
        if simd_length(light - lastLight) > 0.0005 {
            lastLight = light
            for lane in 0..<c {
                let buried = frame.phase.data[lane] == MotionWorld.Phase.inDeck
                    && frame.deckDepth.data[lane] > 2.5
                guard !buried else { continue }
                updateFoil(on: faceModels[lane], light: light)
                updateFoil(on: backModels[lane], light: light)
            }
            // Only the glass reads the tilt light (its glint and Fresnel); wax and flame
            // shaders never used it, so rewriting their materials every frame was pure
            // driver churn — 44 material writes a frame for nothing.
            if let glass = crystalBallModel { updatePropLight(glass, light: light) }
        }
    }

    private func updatePropLight(_ model: ModelEntity, light: SIMD2<Float>) {
        guard var material = model.model?.materials.first as? CustomMaterial else { return }
        var v = material.custom.value
        v.x = light.x
        v.y = light.y          // z holds the flicker phase; the clock lives in the shader
        material.custom.value = v
        model.model?.materials = [material]
    }

    private func updateFoil(on model: ModelEntity?, light: SIMD2<Float>) {
        guard let model, var material = model.model?.materials.first as? CustomMaterial else { return }
        var v = material.custom.value
        v.x = light.x
        v.y = light.y
        v.z = Float(presentationTime)
        material.custom.value = v
        model.model?.materials = [material]
    }

    /// Presentation-only easing: camera dolly, hero dim, candle flicker. dt-driven, no clock.
    func tick(dt: Double) {
        presentationTime += dt

        #if os(iOS)
        // AR follow-preview: keep the floating table LEVEL (world-up) and yaw-facing the
        // camera while the user aims, so fixating freezes a table, not a tilted tray.
        if arModeActive, !arPlacementFixed, let cam = arCameraAnchor {
            let m = cam.transformMatrix(relativeTo: nil)
            let forward = -SIMD3<Float>(m.columns.2.x, m.columns.2.y, m.columns.2.z)
            if abs(forward.x) + abs(forward.z) > 0.05 {
                let yaw = atan2(-forward.x, -forward.z)
                tableWorld.setOrientation(simd_quatf(angle: yaw, axis: [0, 1, 0]), relativeTo: nil)
            }
        }
        #endif
        let ease = 1 - Float(exp(-4.5 * dt))

        let current = camera.position(relativeTo: nil)
        let next = current + (cameraTarget - current) * ease
        camera.look(at: lookTarget, from: next, relativeTo: nil)

        // Candle flicker: two incommensurate sines ±3%, plus the hero dim. The lamp and
        // the key breathe together; each candle's point light flickers harder, on its
        // OWN phase — the same phase its flame and wax shaders run on, so every fire
        // reads as one thing.
        let flicker = 1 + 0.018 * sin(Float(presentationTime) * 7.3)
                        + 0.012 * sin(Float(presentationTime) * 11.9 + 1.3)
        let dim = 1 - heroDim * 0.55
        keyLight.light.intensity = keyBaseIntensity * flicker * dim
        lampLight.light.intensity = lampBaseIntensity * flicker * dim
        for (light, phase) in candleLights {
            let f = 1 + 0.14 * sin(Float(presentationTime) * 7.3 + phase)
                      + 0.09 * sin(Float(presentationTime) * 11.9 + 1.3 + phase)
            light.light.intensity = candleBaseIntensity * f * dim
        }

        // Flames face the camera outright, turning about their wick pivots, so a steep
        // boom never flattens one into a shape pasted on the candle.
        let camPos = camera.position(relativeTo: tableWorld)
        for holder in flameEntities {
            let p = holder.position(relativeTo: tableWorld)
            holder.look(at: camPos, from: p, relativeTo: tableWorld)
        }
        fillLight.light.intensity = 900 * (1 - heroDim * 0.7)
    }

    // MARK: - Beats

    func playRevealBurst(lane: Int, hero: Bool) {
        guard cards.indices.contains(lane) else { return }
        let position = cards[lane].position

        var emitter = ParticleEmitterComponent()
        emitter.emitterShape = .sphere
        emitter.emitterShapeSize = [0.05, 0.05, 0.05]
        emitter.mainEmitter.birthRate = 0
        emitter.mainEmitter.lifeSpan = hero ? 2.6 : 1.6      // embers linger (permanence)
        emitter.mainEmitter.size = hero ? 0.006 : 0.004
        emitter.mainEmitter.color = .evolving(
            start: .single(PlatformColor(red: 1.0, green: 0.85, blue: 0.5, alpha: 0.9)),
            end: .single(PlatformColor(red: 0.6, green: 0.3, blue: 0.5, alpha: 0)))
        emitter.speed = hero ? 0.5 : 0.3
        emitter.burstCount = hero ? 260 : 90
        emitter.mainEmitter.acceleration = [0, 0.08, 0]      // drift up, don't vacuum away

        let entity = Entity()
        entity.position = position + [0, 0.02, 0]
        entity.components.set(emitter)
        tableWorld.addChild(entity)
        entity.components[ParticleEmitterComponent.self]?.burst()
        burstEmitters.append(entity)
        // Retire old emitters so a long session doesn't accumulate entities.
        if burstEmitters.count > 6 {
            burstEmitters.removeFirst().removeFromParent()
        }
    }

    func setHeroFocus(_ on: Bool) {
        heroDim = on ? 1 : 0
        cameraTarget = on ? fitCamera * 0.82 : fitCamera
        lookTarget = homeLook
    }

    func setViewerFocus(lane: Int?) {
        if let lane, cards.indices.contains(lane) {
            let p = cards[lane].position
            // Dolly down and in: the card fills the frame, foil live under tilt.
            cameraTarget = [p.x, 0.62, p.z + 0.4]
            lookTarget = [p.x, 0.05, p.z]
            heroDim = 0.6
        } else {
            cameraTarget = fitCamera
            lookTarget = homeLook
            heroDim = 0
        }
    }

    // MARK: - Hit-testing & conversion

    func lane(for entity: Entity) -> Int? {
        var probe: Entity? = entity
        while let current = probe {
            if let lane = laneByEntity[ObjectIdentifier(current)] { return lane }
            probe = current.parent
        }
        return nil
    }

    func arDebugStatus() -> String {
        #if os(iOS)
        guard arModeActive else { return "" }
        let cam = arCameraAnchor?.position(relativeTo: nil) ?? .zero
        let world = tableWorld.position(relativeTo: nil)
        return String(format: "AR %@ cam(%.2f %.2f %.2f) table(%.2f %.2f %.2f)",
                      arPlacementFixed ? "PLACED" : "previewing",
                      cam.x, cam.y, cam.z, world.x, world.y, world.z)
        #else
        return ""
        #endif
    }

    func tablePoint(fromView point: CGPoint, viewSize: CGSize) -> (x: Double, z: Double) {
        guard viewSize.width > 0, viewSize.height > 0 else { return (0, 0) }
        // One unprojection for both stages: build the pixel ray in CAMERA-local space
        // (-Z forward), convert it into tableWorld's local space — the convert handles the
        // AR anchor's transform and the 0.22 scale for free — and intersect the y = 0 table
        // plane there. Local units ARE table units.
        var eye: Entity = camera
        var fovDegrees: Float = 55
        #if os(iOS)
        if arModeActive, let arCameraAnchor {
            eye = arCameraAnchor
            // ARKit doesn't expose the camera FOV through RealityView; ~58° vertical is a
            // fair iPhone estimate and the kernel's grab/snap radii absorb the error.
            fovDegrees = 58
        }
        #endif

        let halfH = tan(fovDegrees * .pi / 180 / 2)
        let aspect = Float(viewSize.width / viewSize.height)
        let ndcX = Float(point.x / viewSize.width) * 2 - 1
        let ndcY = 1 - Float(point.y / viewSize.height) * 2
        let localDir = SIMD3<Float>(ndcX * halfH * aspect, ndcY * halfH, -1)

        let origin = eye.convert(position: .zero, to: tableWorld)
        let dir = simd_normalize(eye.convert(direction: localDir, to: tableWorld))
        let t = dir.y < -1e-5 ? -origin.y / dir.y : 100
        let hit = origin + dir * min(t, 100)
        return (Double(hit.x / scale), Double(hit.z / scale))
    }

    // MARK: - AR placement

    func setARMode(_ on: Bool) {
        #if os(iOS)
        guard on != arModeActive else { return }
        arModeActive = on
        arPlacementFixed = false
        if on {
            // NO explicit SpatialTrackingSession, deliberately: on iOS, running none gives
            // the full default session (camera + world + plane tracking, scene
            // understanding) — an explicit narrow config is how the first device build
            // KILLED world anchoring. The default session also triggers the camera
            // permission prompt. (Apple docs, SpatialTrackingSession.)
            //
            // The virtual camera must LEAVE the tree: a PerspectiveCamera anywhere in the
            // scene breaks the AR camera (documented pitfall).
            cameraRig.removeFromParent()

            let cameraAnchor = AnchorEntity(.camera)
            sceneRoot.addChild(cameraAnchor)
            arCameraAnchor = cameraAnchor

            // Follow-preview: the whole table floats level in front of the camera until
            // the user fixates it (tick() keeps it level and yaw-facing).
            tableWorld.setParent(cameraAnchor)
            tableWorld.position = arPreviewOffset
            tableWorld.scale = SIMD3<Float>(repeating: arScale)

            // The real table replaces the virtual one; the pools/deck/cards stay.
            tableEntity.isEnabled = false
        } else {
            tableWorld.setParent(sceneRoot)
            tableWorld.position = .zero
            tableWorld.orientation = simd_quatf(angle: 0, axis: [0, 1, 0])
            tableWorld.scale = .one
            tableEntity.isEnabled = true
            if cameraRig.parent == nil { sceneRoot.addChild(cameraRig) }
            arWorldAnchor?.removeFromParent()
            arCameraAnchor?.removeFromParent()
            arWorldAnchor = nil
            arCameraAnchor = nil
        }
        #endif
    }

    func fixateARPlacement() {
        #if os(iOS)
        guard arModeActive, !arPlacementFixed else { return }
        // Freeze exactly the leveled pose the preview shows — translation + yaw only.
        // Built clean rather than from transformMatrix, whose 3×3 carries the 0.22 scale
        // (anchoring with it and re-applying local scale would square the scale).
        let translation = tableWorld.position(relativeTo: nil)
        let yaw = tableWorld.orientation(relativeTo: nil)
        let anchor = AnchorEntity(world: Transform(scale: .one, rotation: yaw,
                                                   translation: translation).matrix)
        sceneRoot.addChild(anchor)
        tableWorld.setParent(anchor)
        tableWorld.transform = Transform(scale: SIMD3<Float>(repeating: arScale),
                                         rotation: simd_quatf(angle: 0, axis: [0, 1, 0]),
                                         translation: .zero)
        arWorldAnchor = anchor
        arPlacementFixed = true
        #endif
    }

    func unfixARPlacement() {
        #if os(iOS)
        guard arModeActive, arPlacementFixed, let arCameraAnchor else { return }
        tableWorld.setParent(arCameraAnchor)
        tableWorld.position = arPreviewOffset
        tableWorld.scale = SIMD3<Float>(repeating: arScale)
        arWorldAnchor?.removeFromParent()
        arWorldAnchor = nil
        arPlacementFixed = false
        #endif
    }
}

#if canImport(UIKit)
import UIKit
typealias PlatformColor = UIColor
#else
import AppKit
typealias PlatformColor = NSColor
#endif
