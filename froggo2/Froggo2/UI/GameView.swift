import SwiftUI
import RealityKit
import Combine
import ReachabilityKit

/// The playable scene: a `RealityView` that draws, a gesture layer that aims, and a HUD on top.
///
/// The simulation is driven from `SceneEvents.Update`, which delivers a real frame delta, rather
/// than from `RealityView`'s `update:` closure — that closure fires on SwiftUI invalidation, not on
/// frames, so driving physics from it would tie the game's speed to how often the UI happens to
/// redraw.
struct GameView: View {
    @Bindable var session: GameSession

    @State private var renderer = RealityKitRenderer()
    @State private var drag = DragAimController()
    @State private var keyboard = KeyboardAimController()
    @State private var subscription: EventSubscription?
    @State private var builtDistrictSeed: UInt64?
    @State private var cameraYaw: Double = 0
    @State private var screenSize: CGSize = .init(width: 1000, height: 640)

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                RealityView { content in
                    renderer.prepare()
                    content.add(renderer.sceneRoot)
                    content.camera = .virtual
                    renderer.build(district: session.district, config: session.config)
                    builtDistrictSeed = session.district.seed
                    subscription = content.subscribe(to: SceneEvents.Update.self) { event in
                        Task { @MainActor in step(event.deltaTime) }
                    }
                }
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            if !drag.isAiming { drag.begin(at: value.startLocation) }
                            drag.update(to: value.location)
                            applyDragIntent()
                        }
                        .onEnded { _ in
                            drag.end()
                            applyDragIntent()
                        }
                )
                .gesture(
                    SpatialTapGesture()
                        .targetedToAnyEntity()
                        .onEnded { value in
                            if let roof = renderer.rooftop(for: value.entity) {
                                session.aimAt(roof)
                            }
                        }
                )
                .ignoresSafeArea()

                HUDView(session: session)
            }
            .onAppear { screenSize = proxy.size }
            .onChange(of: proxy.size) { _, new in screenSize = new }
        }
        .background(Palette.sky)
    }

    // MARK: - Frame

    @MainActor
    private func step(_ delta: Double) {
        // Rebuild the scene when the player crosses into a new district.
        if builtDistrictSeed != session.district.seed {
            renderer.build(district: session.district, config: session.config)
            renderer.setFlies(session.district.flyRoofs.map { session.district[$0].standingPosition() })
            builtDistrictSeed = session.district.seed
        }

        session.tick(delta)

        // The camera follows the frog and trails the aim. Keeping camera yaw separate from aim yaw
        // is what lets the player look around a district before committing to a route.
        cameraYaw = session.aimYaw
        // Aim the camera slightly ahead of the frog rather than straight at it. It fills the frame
        // with the city the player is about to cross instead of the sky behind them, and it is the
        // difference between "here is a frog" and "here is where you are going".
        let lookAhead = Vec2.direction(yaw: session.aimYaw) * 3.2
        let target = Vec3(session.frogPosition.x + lookAhead.x,
                          session.frogPosition.y,
                          session.frogPosition.z + lookAhead.z)
        renderer.setCamera(target: target, yaw: cameraYaw, dt: delta)
        renderer.setFrog(position: session.frogPosition,
                         yaw: session.aimYaw,
                         flightProgress: session.flightProgress,
                         airborne: session.phase == .flying)
        renderer.billboardFlies()

        if session.phase == .aiming, !session.previewArc.isEmpty {
            renderer.showArc(session.previewArc,
                             landing: session.previewLanding,
                             reachable: session.previewIsReachable)
        } else {
            renderer.hideArc()
        }
    }

    private func applyDragIntent() {
        guard let intent = drag.intent(cameraYaw: cameraYaw, screenSize: screenSize) else { return }
        session.setAim(yaw: intent.yaw, power: intent.power)
        if intent.committed { session.launch() }
    }
}

/// The HUD reads `session` directly.
///
/// Froggo 1 pushed score and tutorial text through `NotificationCenter` with stringly-typed names
/// (`"UpdateScore"`, `"UpdateTutorial"`), posted from `didSet`. That coupling is gone: the session
/// is observable, so the HUD simply depends on it.
struct HUDView: View {
    @Bindable var session: GameSession

    var body: some View {
        VStack {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("District \(session.districtsCleared + 1)")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                    if session.par > 0 {
                        // Par exists only because there is a solver: it is the district's own
                        // minimum jump count, measured rather than authored.
                        Text("par \(session.par) · you \(session.jumpsThisDistrict)")
                            .font(.system(size: 13, design: .rounded))
                            .foregroundStyle(.white.opacity(0.75))
                    }
                    if session.flyBanked {
                        Text("FLY BANKED — next jump goes further")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundStyle(Palette.windowLit)
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text("\(session.score)")
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                    Text("best \(session.best)")
                        .font(.system(size: 12, design: .rounded))
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
            .padding(.horizontal, 22)
            .padding(.top, 18)
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.55), radius: 3, x: 1, y: 1)

            Spacer()

            PowerMeter(power: session.power,
                       ceiling: session.config.powerCeiling,
                       reachable: session.previewIsReachable)
                .padding(.bottom, 26)
                .opacity(session.phase == .aiming && session.power > 0.01 ? 1 : 0)
                .animation(.easeOut(duration: 0.15), value: session.power)
        }
        .allowsHitTesting(false)
    }
}

/// The direct descendant of froggo 1's trajectory line, whose *length* was the power meter.
struct PowerMeter: View {
    let power: Double
    let ceiling: Double
    let reachable: Bool

    var body: some View {
        ZStack(alignment: .leading) {
            Capsule()
                .fill(.black.opacity(0.35))
                .frame(width: 190, height: 8)
            Capsule()
                .fill(reachable ? Palette.ringReachable : Palette.ringUnreachable)
                .frame(width: 190 * min(power / ceiling, 1), height: 8)
        }
        .overlay(alignment: .trailing) {
            Capsule()
                .stroke(.white.opacity(0.5), lineWidth: 1)
                .frame(width: 190, height: 8)
        }
    }
}
