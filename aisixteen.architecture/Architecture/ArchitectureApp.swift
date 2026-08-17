import SwiftUI

@main
struct ArchitectureApp: App {

    @State private var router = Router.seeded()
    @State private var library = ProjectLibrary()
    @State private var engine = RedesignEngine()
    @State private var capture = CaptureModel()
    @State private var coordinator: RedesignCoordinator?

    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            Group {
                if let coordinator {
                    RootView(router: router, coordinator: coordinator, capture: capture)
                } else {
                    ZStack { ARC.canvas.ignoresSafeArea(); ProgressView() }
                }
            }
            // Read the real accessibility settings ONCE, here, and publish them as one value.
            // Everything downstream reads `\.arcAccessibility`, which is what makes both settings
            // testable without a simulator.
            .modifier(AccessibilityModeReader())
            .task {
                if coordinator == nil {
                    coordinator = RedesignCoordinator(engine: engine, library: library, router: router)
                }
                await library.start()
                // Rehydrate any render the app was killed during. This NEVER auto-starts — see
                // QueueState.restoredFromDisk.
                engine.restore()
            }
            .onChange(of: scenePhase) { _, phase in
                switch phase {
                case .active:
                    engine.sceneChanged(.active)
                case .inactive:
                    // The short window in which the checkpoint is flushed.
                    engine.sceneChanged(.flushing)
                case .background:
                    engine.sceneChanged(.suspended)
                @unknown default:
                    break
                }
            }
        }
        #if os(macOS)
        .defaultSize(width: 1180, height: 760)
        .windowResizability(.contentMinSize)
        #endif
    }
}
