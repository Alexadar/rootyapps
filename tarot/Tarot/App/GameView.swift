import SwiftUI
import RealityKit

/// The one RealityView, alive across every screen. The simulation is driven from
/// `SceneEvents.Update` — a real frame delta — never from `RealityView`'s `update:` closure,
/// which fires on SwiftUI invalidation, not on frames (froggo2's lesson, kept).
struct GameView: View {
    @Environment(AppModel.self) private var model
    @State private var subscription: EventSubscription?

    var body: some View {
        GeometryReader { geometry in
            RealityView { content in
                // Camera mode is a per-view-identity decision: runtime switching corrupts
                // the virtual camera (Apple Forums, unfixed), so `.id(model.arMode)` below
                // recreates this whole view on AR toggle and this closure runs again.
                #if os(iOS)
                content.camera = model.arMode ? .spatialTracking : .virtual
                #else
                content.camera = .virtual
                #endif
                model.sceneRemade()
                content.add(model.renderer.sceneRoot)
                subscription = content.subscribe(to: SceneEvents.Update.self) { event in
                    Task { @MainActor in
                        model.step(dt: event.deltaTime)
                    }
                }
            }
            .id(model.arMode)
            .onAppear { model.renderer.setViewSize(geometry.size) }
            .onChange(of: geometry.size) { _, newSize in
                // Rotation, split view, a resized Mac window: the camera fit recomputes
                // and the boom lerps there — never cuts.
                model.renderer.setViewSize(newSize)
            }
            .gesture(dragGesture(in: geometry.size))
            .gesture(tapGesture)
            .onContinuousHover(coordinateSpace: .local) { phase in
                // Pointer-driven foil light (the Mac's only tilt source; also live for iPad
                // trackpads). Normalized to [-1, 1] about the view centre.
                if case .active(let point) = phase {
                    let size = geometry.size
                    guard size.width > 0, size.height > 0 else { return }
                    TiltSource.shared.setPointerLight(
                        x: Double(point.x / size.width) * 2 - 1,
                        z: Double(point.y / size.height) * 2 - 1)
                }
            }
        }
        .accessibilityIdentifier("game.scene")
    }

    /// A plain 2D drag: the kernel owns grab/release semantics, so all the gesture layer
    /// supplies is a pointer on the table plane — which the renderer unprojects, because the
    /// renderer owns the camera. No entity targeting needed for the drag.
    private func dragGesture(in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let point = model.renderer.tablePoint(fromView: value.location, viewSize: size)
                model.pointerX = point.x
                model.pointerZ = point.z
                model.pointerDown = true
            }
            .onEnded { _ in
                model.pointerDown = false
            }
    }

    private var tapGesture: some Gesture {
        SpatialTapGesture()
            .targetedToAnyEntity()
            .onEnded { value in
                if let lane = model.renderer.lane(for: value.entity) {
                    model.tapped(lane: lane)
                }
            }
    }
}
