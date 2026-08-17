import SwiftUI

#if os(iOS)

/// Twin-thumb, exactly as PROMPT §2 describes: left half positions, right half charges.
///
/// The joystick is **relative** — it appears wherever the thumb lands rather than at a fixed spot.
/// A fixed stick forces the player to look at their own hand; a relative one lets them keep their
/// eyes on the traffic, which in this game is the whole job.
struct TouchControls: View {
    @ObservedObject var game: Game
    @State private var stickOrigin: CGPoint?
    @State private var stickPoint: CGPoint = .zero

    private let radius: CGFloat = 62

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 0) {
                stickArea
                    .frame(width: geo.size.width * 0.45)
                chargeArea
            }
        }
        .ignoresSafeArea()
    }

    private var stickArea: some View {
        Color.clear
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { v in
                        if stickOrigin == nil { stickOrigin = v.startLocation }
                        stickPoint = v.location
                        let d = CGSize(width: v.location.x - (stickOrigin?.x ?? 0),
                                       height: v.location.y - (stickOrigin?.y ?? 0))
                        game.inputMove = SIMD2(Float(max(-1, min(1, d.width / radius))),
                                               // Screen y grows downward; climbing is negative there.
                                               Float(max(-1, min(1, -d.height / radius))))
                    }
                    .onEnded { _ in
                        stickOrigin = nil
                        game.inputMove = .zero
                    }
            )
            .overlay {
                if let o = stickOrigin {
                    ZStack {
                        Circle().strokeBorder(.white.opacity(0.35), lineWidth: 2)
                            .frame(width: radius * 2, height: radius * 2)
                            .position(o)
                        Circle().fill(.white.opacity(0.55))
                            .frame(width: 44, height: 44)
                            .position(clamped(stickPoint, around: o))
                    }
                    .allowsHitTesting(false)
                }
            }
    }

    private var chargeArea: some View {
        Color.clear
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in game.inputHold = true }
                    .onEnded { _ in game.inputHold = false }
            )
    }

    private func clamped(_ p: CGPoint, around o: CGPoint) -> CGPoint {
        let dx = p.x - o.x, dy = p.y - o.y
        let len = max(1, (dx * dx + dy * dy).squareRoot())
        let k = min(1, radius / len)
        return CGPoint(x: o.x + dx * k, y: o.y + dy * k)
    }
}

#endif

#if os(macOS)
import AppKit

/// Keyboard on the Mac, and nothing pretending to be a thumbstick.
///
/// PROMPT §6 is explicit that a twin-stick layout in a window is wrong, so the Mac gets the mapping a
/// Mac actually has: arrows or WASD to fly, **hold Space** to charge. Space is the right key because
/// the action is a hold-and-release and Space is the only key with that affordance built in.
struct KeyboardControls: NSViewRepresentable {

    let game: Game

    func makeNSView(context: Context) -> NSView {
        let v = KeyView()
        v.game = game
        DispatchQueue.main.async { v.window?.makeFirstResponder(v) }
        return v
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    final class KeyView: NSView {
        weak var game: Game?
        private var pressed = Set<UInt16>()

        override var acceptsFirstResponder: Bool { true }
        override func viewDidMoveToWindow() { window?.makeFirstResponder(self) }

        // Virtual key codes. Spelled out because `NSEvent.characters` depends on the keyboard
        // layout, and a French or Cyrillic layout would silently lose WASD.
        private enum Key {
            static let w: UInt16 = 13, a: UInt16 = 0, s: UInt16 = 1, d: UInt16 = 2
            static let left: UInt16 = 123, right: UInt16 = 124
            static let down: UInt16 = 125, up: UInt16 = 126
            static let space: UInt16 = 49
        }

        override func keyDown(with event: NSEvent) {
            guard !event.isARepeat else { return }
            pressed.insert(event.keyCode)
            apply()
        }

        override func keyUp(with event: NSEvent) {
            pressed.remove(event.keyCode)
            apply()
        }

        /// Modifier changes can swallow a key-up, leaving a key stuck down. Clearing on a modifier
        /// change is cruder than tracking it properly and it never strands the pigeon mid-climb.
        override func flagsChanged(with event: NSEvent) {
            if !event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty {
                pressed.removeAll()
                apply()
            }
        }

        private func apply() {
            var x: Float = 0, y: Float = 0
            if pressed.contains(Key.a) || pressed.contains(Key.left) { x -= 1 }
            if pressed.contains(Key.d) || pressed.contains(Key.right) { x += 1 }
            if pressed.contains(Key.s) || pressed.contains(Key.down) { y -= 1 }
            if pressed.contains(Key.w) || pressed.contains(Key.up) { y += 1 }
            let hold = pressed.contains(Key.space)
            Task { @MainActor [game] in
                game?.inputMove = SIMD2(x, y)
                game?.inputHold = hold
            }
        }
    }
}
#endif
