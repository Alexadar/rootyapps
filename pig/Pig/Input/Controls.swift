import SwiftUI
#if os(macOS)
import AppKit
#endif

/// A thumb area that becomes a stick wherever it is first touched.
///
/// Fixed on-screen sticks are wrong on a phone: the thumb lands where the thumb lands, and a stick
/// drawn somewhere else means the first half-second of every input is spent correcting. This one has
/// no position of its own until it is touched, and it fades out completely when it is not.
///
/// The same view serves both thumbs. The left one's vector is a direction; the right one's is a rate.
struct ThumbPad: View {

    /// −1…1 in each axis, y positive **up the screen**.
    let onChange: (SIMD2<Float>) -> Void
    var tint: Color = .white
    /// Full deflection distance, points.
    var radius: CGFloat = 62
    /// Deflection below which the pad reports nothing, as a fraction of `radius`.
    ///
    /// The look pad needs a real one — a thumb resting on the glass drifts the camera for as long as
    /// it rests there, and a slow drift is worse than a jump because the player corrects it without
    /// noticing they are correcting it. The walk pad wants a much smaller one: there, a dead zone is
    /// just unresponsiveness.
    var deadZone: Float = 0.05

    /// Ghost input for the demo: when set, the pad DRAWS this deflection instead of what the finger
    /// is doing, so a recording shows the stick being worked. It is display only and never reaches
    /// `onChange` — there is no path from here into the game.
    var ghost: SIMD2<Float>?

    @State private var origin: CGPoint?
    @State private var knob: CGPoint?

    var body: some View {
        GeometryReader { geo in
            Rectangle()
                .fill(.clear)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { g in
                            let start = origin ?? g.startLocation
                            if origin == nil { origin = start }
                            let dx = g.location.x - start.x
                            let dy = g.location.y - start.y
                            let len = max(1, (dx * dx + dy * dy).squareRoot())
                            let clamped = min(len, radius)
                            let nx = dx / len * clamped / radius
                            let ny = dy / len * clamped / radius
                            knob = CGPoint(x: start.x + dx / len * clamped,
                                           y: start.y + dy / len * clamped)
                            // Screen y grows downward; the game's does not.
                            onChange(ThumbPad.applyDeadZone(SIMD2(Float(nx), Float(-ny)),
                                                            deadZone))
                        }
                        .onEnded { _ in
                            origin = nil; knob = nil
                            onChange(SIMD2(0, 0))
                        }
                )
                .overlay {
                    // A ghost stick sits where a thumb naturally would — low, and toward the outside
                    // edge of its half — so a recording reads as a hand playing rather than as a
                    // diagram.
                    let ghostHome = CGPoint(x: geo.size.width * 0.5,
                                            y: geo.size.height - radius - 40)
                    if let g = ghost, origin == nil {
                        stick(centre: ghostHome,
                              knob: CGPoint(x: ghostHome.x + CGFloat(g.x) * radius,
                                            y: ghostHome.y - CGFloat(g.y) * radius))
                    } else if let o = origin, let k = knob {
                        stick(centre: o, knob: k)
                    }
                }
        }
    }

    /// The ring and its knob. One drawing, so a ghost stick and a real one cannot look different.
    private func stick(centre: CGPoint, knob: CGPoint) -> some View {
        ZStack {
            Circle()
                .strokeBorder(tint.opacity(0.35), lineWidth: 2)
                .frame(width: radius * 2, height: radius * 2)
                .position(centre)
            Circle()
                .fill(tint.opacity(0.45))
                .frame(width: 46, height: 46)
                .position(knob)
        }
        .allowsHitTesting(false)
    }

    /// Below the dead zone the pad reports nothing; above it, the remaining range is rescaled to the
    /// full 0…1 so the first responsive deflection is not a jump.
    static func applyDeadZone(_ v: SIMD2<Float>, _ dz: Float) -> SIMD2<Float> {
        let len = (v.x * v.x + v.y * v.y).squareRoot()
        guard len > dz else { return SIMD2(0, 0) }
        guard dz < 1 else { return SIMD2(0, 0) }
        return v / len * ((len - dz) / (1 - dz))
    }
}

#if os(macOS)
/// Held-key tracking for the Mac.
///
/// `onKeyPress` reports discrete presses, which is the wrong shape for movement: a game needs to know
/// that W is *currently* down, not that it was pressed. A local event monitor gives that directly.
@MainActor
final class KeyboardMonitor {
    private var held: Set<UInt16> = []
    private var monitor: Any?

    // Virtual key codes, which are layout-independent — `keyDown.characters` on an AZERTY or
    // Cyrillic layout would not spell "wasd".
    private enum Key: UInt16 {
        case w = 13, a = 0, s = 1, d = 2
        case left = 123, right = 124, down = 125, up = 126
        case space = 49, q = 12, e = 14
    }

    func start(_ apply: @escaping (SIMD2<Float>, SIMD2<Float>, Bool) -> Void) {
        // The monitor fires on the main thread, but its signature is `nonisolated` — hence the
        // explicit hop rather than an `await`, which would arrive a frame late.
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] event in
            guard let self else { return event }
            // Let a modified key (⌘Q, ⌘W) through to the menus untouched.
            if event.modifierFlags.contains(.command) { return event }
            return MainActor.assumeIsolated {
                if event.type == .keyDown {
                    self.held.insert(event.keyCode)
                } else {
                    self.held.remove(event.keyCode)
                }

                let keys = self.held
                func down(_ k: Key) -> Float { keys.contains(k.rawValue) ? 1 : 0 }
                let move = SIMD2<Float>(down(.d) - down(.a), down(.w) - down(.s))
                // Same convention as a drag: right turns the view right, up looks up.
                let look = SIMD2<Float>(down(.right) - down(.left) + down(.e) - down(.q),
                                        down(.up) - down(.down))
                apply(move, look, keys.contains(Key.space.rawValue))
                return nil
            }
        }
    }

    /// There is deliberately no `deinit` teardown: the monitor lives exactly as long as the game
    /// screen, which lives as long as the app. Removing it from `deinit` would mean an isolated
    /// call out of a nonisolated context, which Swift 6 rejects for good reason.
    func stop() {
        if let m = monitor { NSEvent.removeMonitor(m) }
        monitor = nil
    }
}
#endif
