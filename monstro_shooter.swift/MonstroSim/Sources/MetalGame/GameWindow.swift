import Foundation
import Metal
import MetalKit
import AppKit
import simd

// Interactive window: same GPU game (Game), presented to screen via MTKView. WASD to move; the
// player auto-fires at the nearest monster. This is the SAME engine as the headless playthrough —
// only the output target (drawable vs PNG) and the player input (keys vs scripted) differ.

final class GameView: MTKView {
    var pressed = Set<UInt16>()
    override var acceptsFirstResponder: Bool { true }
    override func keyDown(with e: NSEvent) { pressed.insert(e.keyCode) }
    override func keyUp(with e: NSEvent) { pressed.remove(e.keyCode) }
}

final class GameDelegate: NSObject, MTKViewDelegate {
    let game: Game
    weak var view: GameView?
    init(_ game: Game, _ view: GameView) { self.game = game; self.view = view }
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}
    func draw(in mtkView: MTKView) {
        guard let view = view else { return }
        // WASD (codes: W=13, A=0, S=1, D=2)
        var mv = SIMD2<Float>(0, 0)
        if view.pressed.contains(13) { mv.y += 1 }
        if view.pressed.contains(1) { mv.y -= 1 }
        if view.pressed.contains(0) { mv.x -= 1 }
        if view.pressed.contains(2) { mv.x += 1 }
        if game.alive { game.step(dt: 1.0 / 60.0, moveDir: mv) }
        if let rp = view.currentRenderPassDescriptor, let dr = view.currentDrawable {
            game.render(passDescriptor: rp, drawable: dr)
        }
        view.window?.title = game.alive
            ? String(format: "Monstro GPU — hp %.0f   kills %u", max(game.php, 0), game.kills)
            : String(format: "GAME OVER — kills %u", game.kills)
    }
}

func runGameWindow() {
    guard let game = try? Game() else { fputs("no Metal device\n", stderr); exit(1) }
    let app = NSApplication.shared
    app.setActivationPolicy(.regular)
    let view = GameView(frame: NSRect(x: 0, y: 0, width: 1000, height: 1000), device: game.device)
    view.colorPixelFormat = .bgra8Unorm
    view.clearColor = MTLClearColor(red: 0.04, green: 0.05, blue: 0.08, alpha: 1)
    view.preferredFramesPerSecond = 60
    let delegate = GameDelegate(game, view)
    view.delegate = delegate
    let win = NSWindow(contentRect: view.frame, styleMask: [.titled, .closable, .resizable],
                       backing: .buffered, defer: false)
    win.title = "Monstro GPU"
    win.contentView = view
    win.center()
    win.makeKeyAndOrderFront(nil)
    win.makeFirstResponder(view)
    app.activate(ignoringOtherApps: true)
    // keep the delegate alive
    objc_setAssociatedObject(win, "delegate", delegate, .OBJC_ASSOCIATION_RETAIN)
    app.run()
}
