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

    @ObservedObject var game: Game

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
    /// steps from an accumulator, so the engine never sees a frame delta. Two runs at 60 and 120 Hz
    /// produce identical physics, which is what makes replay and the tests mean anything.
    final class Coordinator: NSObject, MTKViewDelegate {
        let game: Game
        var renderer: Renderer?
        private var lastTime: CFTimeInterval?
        private var accumulator: Double = 0

        init(game: Game) { self.game = game }

        func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
            renderer?.mtkView(view, drawableSizeWillChange: size)
        }

        func draw(in view: MTKView) {
            let now = CACurrentMediaTime()
            let elapsed = min(0.25, now - (lastTime ?? now))     // clamp, or a stall becomes a warp
            lastTime = now
            accumulator += elapsed

            let dt = game.config.dt
            var steps = 0
            while accumulator >= dt && steps < 6 {               // catch-up, bounded
                game.tick()
                accumulator -= dt
                steps += 1
            }
            if steps == 6 { accumulator = 0 }

            renderer?.snapshot = game.snapshot
            renderer?.draw(in: view)
        }
    }
}
