import SwiftUI

/// The whole interface: the Metal view, the controls, and the HUD over it.
struct GameScreen: View {
    @StateObject private var game = Game()

    var body: some View {
        ZStack {
            MetalGameView(game: game)
                .ignoresSafeArea()

            #if os(iOS)
            TouchControls(game: game)
            #endif

            HUD(game: game)

            switch game.phase {
            case .menu where !Game.demoMode: MenuOverlay(game: game)
            case .menu: EmptyView()
            case .over: GameOverOverlay(game: game)
            case .playing: EmptyView()
            }
        }
        #if os(macOS)
        .background(KeyboardControls(game: game))
        // A locked side view needs width: the game is about how far ahead of the pigeon you can
        // see. A minimum size enforces that; a fixed aspect ratio would not — and would fight the
        // camera, which already frames itself from whatever aspect it is given (see
        // `Renderer.makeUniforms`). An earlier 16:9 lock letterboxed the game inside the window and
        // made an iPad-shaped window render a 16:9 picture.
        .frame(minWidth: 960, idealWidth: 1280, minHeight: 540, idealHeight: 720)
        #endif
        .onAppear { if !Game.demoMode { game.autopilot = true } }
        .persistentSystemOverlays(.hidden)
    }
}

// MARK: - HUD

private struct HUD: View {
    @ObservedObject var game: Game

    var body: some View {
        VStack {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(Int(game.snapshot.score))")
                        .font(.system(size: 40, weight: .heavy, design: .rounded))
                        .monospacedDigit()
                    if game.snapshot.multiplier > 1 {
                        Text("×\(Int(game.snapshot.multiplier))")
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                            .foregroundStyle(Color(Palette.green))
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text("BEST \(Int(game.bestScore))")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .opacity(0.75)
                    AmmoPips(count: game.snapshot.ammo, capacity: Float(game.config.ammoCapacity))
                }
            }
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.35), radius: 3, y: 1)
            .padding(20)

            Spacer()

            if game.phase == .playing {
                ChargeMeter(charge: game.snapshot.charge, holding: game.snapshot.holding)
                    .padding(.bottom, 26)
            }
        }
    }
}

/// The reserve, as discrete pips. Discrete because the decision it informs is discrete: you either
/// have a drop or you do not, and a smoothly draining bar hides exactly the moment that matters.
private struct AmmoPips: View {
    let count: Float
    let capacity: Float

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<Int(capacity), id: \.self) { i in
                let filled = count >= Float(i + 1)
                let partial = count - Float(i)
                Capsule()
                    .fill(filled ? Color(Palette.white) : Color(Palette.white).opacity(0.25))
                    .overlay(alignment: .leading) {
                        if !filled && partial > 0 {
                            GeometryReader { g in
                                Capsule().fill(Color(Palette.white).opacity(0.6))
                                    .frame(width: g.size.width * CGFloat(partial))
                            }
                        }
                    }
                    .frame(width: 20, height: 6)
            }
        }
    }
}

/// The charge meter. Linear in flight time, so its travel is linear in what the player sees the
/// landing ring do — that correspondence is the whole reason charge is parameterised the way it is.
private struct ChargeMeter: View {
    let charge: Float
    let holding: Bool

    var body: some View {
        ZStack(alignment: .leading) {
            Capsule().fill(.black.opacity(0.3)).frame(width: 220, height: 12)
            Capsule()
                .fill(LinearGradient(colors: [Color(Palette.white), Color(Palette.windowLit)],
                                     startPoint: .leading, endPoint: .trailing))
                .frame(width: 220 * CGFloat(min(1, charge)), height: 12)
        }
        .overlay(Capsule().strokeBorder(.white.opacity(0.5), lineWidth: 1).frame(width: 220, height: 12))
        // The track stays at one opacity and only the FILL moves.
        //
        // Fading the whole meter in and out on `holding` made it strobe: the pilot charges about
        // twice a second, so a bar sitting over the middle of the road flashed continuously and read
        // as a rendering fault rather than as a readout.
        .opacity(0.9)
    }
}

// MARK: - Overlays

private struct MenuOverlay: View {
    @ObservedObject var game: Game

    var body: some View {
        VStack(spacing: 18) {
            Spacer()
            Text("CITY PIGEON")
                .font(.system(size: 56, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.4), radius: 6, y: 2)
            Text(hint)
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.85))
            Button("PLAY") { game.autopilot = false; game.start() }
                .buttonStyle(BigButton())
            Spacer()
        }
        .padding(40)
        .background(.black.opacity(0.18))
    }

    private var hint: String {
        #if os(macOS)
        "Arrows or WASD to fly · hold Space to charge · release to drop"
        #else
        "Left thumb to fly · hold right side to charge · release to drop"
        #endif
    }
}

private struct GameOverOverlay: View {
    @ObservedObject var game: Game

    var body: some View {
        VStack(spacing: 16) {
            Text("\(Int(game.snapshot.score))")
                .font(.system(size: 64, weight: .black, design: .rounded))
                .foregroundStyle(.white)
            Button("AGAIN") { game.start() }.buttonStyle(BigButton())
        }
        .padding(40)
        .background(.black.opacity(0.3))
    }
}

private struct BigButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 22, weight: .heavy, design: .rounded))
            .foregroundStyle(.black)
            .padding(.horizontal, 40).padding(.vertical, 14)
            .background(Capsule().fill(Color(Palette.windowLit)))
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
    }
}

extension Color {
    init(_ v: SIMD3<Float>) {
        self.init(.sRGB, red: Double(v.x), green: Double(v.y), blue: Double(v.z), opacity: 1)
    }
}
