import Foundation
import Metal
import simd
import CoreGraphics
import ImageIO

// Headless playthrough — runs the full GPU game loop (spawn → chase → shoot → die → contact damage)
// with a scripted "kite + auto-fire" player, prints progression, and dumps a mid-game PNG. This is
// how we verify the game actually works without a window. The interactive MTKView build is GameWindow.

func arg(_ k: String, _ d: Int) -> Int {
    CommandLine.arguments.firstIndex(of: "--\(k)").flatMap { Int(CommandLine.arguments[$0 + 1]) } ?? d
}
func argS(_ k: String, _ d: String) -> String {
    CommandLine.arguments.firstIndex(of: "--\(k)").map { CommandLine.arguments[$0 + 1] } ?? d
}

func writePNG(_ tex: MTLTexture, _ path: String) {
    let w = tex.width, h = tex.height
    var px = [UInt8](repeating: 0, count: w * h * 4)
    tex.getBytes(&px, bytesPerRow: w * 4, from: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0)
    let info = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
    let ctx = CGContext(data: &px, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: info.rawValue)!
    let img = ctx.makeImage()!
    let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: path) as CFURL, "public.png" as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, img, nil); CGImageDestinationFinalize(dest)
}

// Parity mode: replay the exported games through the batched sim at N=1 and dump positions
// for the Python parity diff.  `monstro-game --port <dir> [--player x.mlmodel] [--enemy y.mlmodel]`
if CommandLine.arguments.contains("--port") { runPort(); exit(0) }

// Demo capture: the TRAINED player model + monster model play; render real sprites to a PNG sequence.
//   monstro-game --demo [--out /tmp/demo] [--player models/player.mlmodel] [--frames 900]
if CommandLine.arguments.contains("--demo") {
    let dir = argS("out", "/tmp/demo")
    try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    for p in (try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? [] where p.hasSuffix(".png") {
        try? FileManager.default.removeItem(atPath: "\(dir)/\(p)")
    }
    let nframes = arg("frames", 900), size = arg("size", 800)
    let game = try Game(playerPath: argS("player", "models/player.json"))
    let td = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: size, height: size, mipmapped: false)
    td.usage = [.renderTarget, .shaderRead]; td.storageMode = .shared
    let tex = game.device.makeTexture(descriptor: td)!
    var fi = 0
    for f in 0..<nframes {
        game.step(dt: 1.0 / 60.0, moveDir: .zero)
        if f % 2 == 0 { game.render(into: tex); writePNG(tex, String(format: "%@/f%04d.png", dir, fi)); fi += 1 }
        if !game.alive { break }
    }
    print("demo: \(fi) frames -> \(dir)  (kills \(game.kills), hp \(Int(max(game.php, 0))))")
    exit(0)
}

// Grid mode: play the 3x3 (maps x seeds) grid as ONE batched MLX rollout, record a replay script, then
// draw all games with the real Swift sprite renderer: `monstro-game --grid [--out /tmp/grid]`.
if CommandLine.arguments.contains("--grid") { runGrid(); exit(0) }

// Interactive window mode (play it): `monstro-game --window`. Blocks until you quit.
if CommandLine.arguments.contains("--window") { runGameWindow(); exit(0) }

// Otherwise: headless playthrough (verification).
let frames = arg("frames", 900)
let size = arg("size", 1000)
let snapAt = arg("snap", 300)
let out = argS("out", "/tmp/game.png")

let game = try Game()
let td = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: size, height: size, mipmapped: false)
td.usage = [.renderTarget, .shaderRead]; td.storageMode = .shared
let tex = game.device.makeTexture(descriptor: td)!

// Headless smoke: canonical game (GridSim N=1, MLX monster net), player kites the nearest monster.
print("Headless: GridSim N=1 game (MLX monsters), scripted-kite player, \(frames) frames @60fps")
print("  frame   kills   hp")
var snapped = false, gameOverAt = -1
let t0 = DispatchTime.now()
for f in 0..<frames {
    let nv = game.sim.nearestVec()                                       // toward nearest monster
    let mv = simd_length(nv) > 0.001 ? -simd_normalize(nv) : SIMD2<Float>(0, 0)   // kite away
    game.step(dt: 1.0 / 60.0, moveDir: mv)
    if !game.alive && gameOverAt < 0 { gameOverAt = f }
    if (f == snapAt || (gameOverAt == f)) && !snapped { game.render(into: tex); writePNG(tex, out); snapped = true }
    if f % 150 == 0 || f == frames - 1 {
        print(String(format: "  %5d   %5u   %4.0f", f, game.kills, max(game.php, 0)))
    }
    if gameOverAt >= 0 { break }
}
if !snapped { game.render(into: tex); writePNG(tex, out) }
let secs = Double(DispatchTime.now().uptimeNanoseconds - t0.uptimeNanoseconds) / 1e9
let ran = gameOverAt >= 0 ? gameOverAt : frames
print(String(format: "Result: %@ — survived %d frames (%.1fs game time), %u kills, hp %.0f",
             gameOverAt >= 0 ? "GAME OVER" : "survived to end", ran, Double(ran) / 60.0, game.kills, max(game.php, 0)))
print(String(format: "  GPU loop ran %d frames in %.0f ms wall (%.0f sim-fps)", ran, secs * 1000, Double(ran) / secs))
print("  snapshot -> \(out)")
