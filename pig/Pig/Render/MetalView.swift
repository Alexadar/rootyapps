import SwiftUI
import MetalKit

/// The `MTKView` host, and the only file that knows both SwiftUI and Metal.
///
/// One implementation for both platforms, differing in nothing but the representable protocol —
/// `MTKView` is `NSView` on the Mac and `UIView` on iOS and behaves identically otherwise.
#if os(macOS)
typealias PlatformViewRepresentable = NSViewRepresentable
#else
typealias PlatformViewRepresentable = UIViewRepresentable
#endif

struct MetalGameView: PlatformViewRepresentable {

    let game: Game

    func makeCoordinator() -> Coordinator { Coordinator(game: game) }

    private func makeView(context: Context) -> MTKView {
        let view = MTKView(frame: .zero, device: MTLCreateSystemDefaultDevice())
        view.isPaused = false
        view.enableSetNeedsDisplay = false
        guard let renderer = Renderer(view: view, config: game.config) else { return view }
        context.coordinator.renderer = renderer
        view.delegate = context.coordinator
        game.renderer = renderer
        return view
    }

    #if os(macOS)
    func makeNSView(context: Context) -> MTKView { makeView(context: context) }
    func updateNSView(_ view: MTKView, context: Context) {}
    #else
    func makeUIView(context: Context) -> MTKView { makeView(context: context) }
    func updateUIView(_ view: MTKView, context: Context) {}
    #endif

    /// Drives the fixed-timestep simulation from the display's callback.
    ///
    /// The renderer's `draw` is the clock, but the *simulation* is not: it advances in whole `dt`
    /// steps from an accumulator, so the engine never sees a frame delta. A 60 Hz phone and a 120 Hz
    /// one produce identical motion, which is what makes replay and the tests mean anything.
    @MainActor
    final class Coordinator: NSObject, MTKViewDelegate {
        let game: Game
        var renderer: Renderer?
        /// The wall-clock contract, in a type that can be tested without a window.
        private var clock: FixedStep

        init(game: Game) {
            self.game = game
            self.clock = FixedStep(dt: game.config.dt)
        }

        nonisolated func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
            MainActor.assumeIsolated { renderer?.mtkView(view, drawableSizeWillChange: size) }
        }

        nonisolated func draw(in view: MTKView) {
            MainActor.assumeIsolated {
                let steps = clock.steps(now: CACurrentMediaTime())
                for _ in 0..<steps { game.tick() }

                renderer?.snapshot = game.snapshot
                renderer?.draw(in: view)
            }
        }
    }
}
