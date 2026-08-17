import SwiftUI
#if os(macOS)
import AppKit
#endif

/// The whole screen: the Metal view, two thumb areas, one button, and a readout.
///
/// The control layout is the mobile one on every platform — the Mac gets the keyboard *as well*,
/// never instead. A trackpad drag on the left half walks and on the right half looks, which is what
/// makes "check it on the Mac" mean the same thing as "check it on a phone".
struct GameScreen: View {

    @StateObject private var game = Game()
    #if os(macOS)
    @State private var keyboard = KeyboardMonitor()
    #endif

    var body: some View {
        ZStack {
            MetalGameView(game: game)
                .ignoresSafeArea()

            // Two thumb areas, split down the middle. They are invisible until touched.
            HStack(spacing: 0) {
                ThumbPad(onChange: { game.stick = $0 }, tint: .white,
                         deadZone: 0.05,
                         ghost: Game.demoMode ? game.demo.stick : nil)
                // The pad already reports right-positive and up-positive; `Game` owns the convention
                // from here, so there is exactly one place a sign can be wrong. The look pad gets a
                // real dead zone: a thumb resting on the glass otherwise drifts the camera forever.
                ThumbPad(onChange: { game.look = $0 }, tint: .yellow,
                         deadZone: 0.2,
                         ghost: Game.demoMode ? game.demo.look : nil)
            }
            .ignoresSafeArea(.container, edges: .bottom)

            VStack {
                readout
                // Under the readout rather than over the action: at the bottom the caption landed on
                // the pig and on both thumb sticks, which is the one thing a demo caption must not do.
                if Game.demoMode, !game.demo.caption.isEmpty {
                    Text(game.demo.caption)
                        .font(.system(size: 24, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.6), radius: 8, y: 2)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 10)
                        .background(Capsule().fill(.black.opacity(0.34)))
                        .padding(.top, 10)
                        .transition(.opacity)
                        .id(game.demo.caption)
                }
                Spacer()
                HStack {
                    Spacer()
                    CooldownButton(title: "Drop",
                                   systemImage: "arrow.down.circle.fill",
                                   readiness: game.hud.dropReadiness,
                                   enabled: game.hud.canDrop,
                                   ghostPressed: Game.demoMode ? game.demo.drop : nil) {
                        game.dropHeld = $0
                    }
                        .padding(.trailing, 34)
                        .padding(.bottom, 34)
                }
            }
        }
        #if os(macOS)
        .onAppear {
            // `.defaultSize` is only a *default*: macOS restores whatever frame the window had last
            // time, so a capture launched with `PIG_DEMO_SIZE` came out at the previous session's
            // size instead. Setting the frame directly is the only thing that actually pins it.
            //
            // The printed `DEMOFRAME` line is for a capture script that wants the rect without
            // hunting for it — the same courtesy `CITYPIGEON_DEMO_SIZE` prints.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                guard let window = NSApplication.shared.windows.first else { return }
                let size = PigApp.windowSize
                // Borderless while filming: `recordwindow` captures the whole window, so a title bar
                // would be baked into the middle of a store-sized frame with no way to crop it back
                // out without losing the exact 1920×1080.
                if Game.demoMode { window.styleMask = [.borderless] }
                window.setContentSize(size)
                window.center()
                let f = window.frame
                let line = "DEMOFRAME \(Int(f.minX)) \(Int(f.minY)) "
                    + "\(Int(size.width)) \(Int(size.height))\n"
                FileHandle.standardError.write(Data(line.utf8))
            }

            keyboard.start { move, look, drop in
                game.stick = move
                game.look = look
                game.dropHeld = drop
            }
        }
        #endif
        #if !os(macOS)
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        #endif
    }

    /// Fatness, carrots, and whether something is chasing you. Everything else on screen is the pig.
    private var readout: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Fatness")
                    .font(.system(size: 11, weight: .bold)).textCase(.uppercase)
                    .foregroundStyle(.white.opacity(0.8))
                ZStack(alignment: .leading) {
                    Capsule().fill(.black.opacity(0.3)).frame(width: 190, height: 14)
                    Capsule()
                        .fill(LinearGradient(colors: [.pink.opacity(0.9), .orange],
                                             startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(8, 190 * CGFloat(game.hud.fat)), height: 14)
                    Capsule().strokeBorder(.white.opacity(0.5), lineWidth: 1.5)
                        .frame(width: 190, height: 14)
                }
            }

            Label("\(game.hud.eaten)", systemImage: "carrot.fill")
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundStyle(.orange)

            if game.hud.dogActive {
                Label(game.hud.dogClose ? "Run!" : "Dog", systemImage: "pawprint.fill")
                    .font(.system(size: 16, weight: .heavy, design: .rounded))
                    .foregroundStyle(game.hud.dogClose ? .red : .yellow)
            } else if game.hud.eating {
                Label("Nom", systemImage: "mouth.fill")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(.green)
            }

            Spacer()
        }
        .padding(.horizontal, 22)
        .padding(.top, 18)
        .shadow(color: .black.opacity(0.35), radius: 4, y: 1)
    }
}

/// A round button that shows how much of its cooldown is left.
///
/// The ring is the whole point: the drop is expensive and rare, so the player has to be able to plan
/// around it from across the field, not discover it is unavailable at the moment the dog arrives.
struct CooldownButton: View {
    let title: String
    let systemImage: String
    /// 0 just used, 1 ready.
    let readiness: Float
    let enabled: Bool
    /// Demo only: draw the button as pressed without anything having touched it.
    var ghostPressed: Bool?
    let onHold: (Bool) -> Void

    @State private var down = false

    private var pressed: Bool { ghostPressed ?? down }

    var body: some View {
        VStack(spacing: 3) {
            Image(systemName: systemImage).font(.system(size: 26, weight: .semibold))
            Text(title).font(.system(size: 11, weight: .semibold)).textCase(.uppercase)
        }
        .foregroundStyle(pressed ? Color.black.opacity(0.75) : (enabled ? .white : .white.opacity(0.45)))
        .frame(width: 88, height: 88)
        .background {
            Circle().fill(pressed ? Color.white.opacity(0.85) : Color.black.opacity(0.28))
            Circle().strokeBorder(.white.opacity(enabled ? 0.55 : 0.2), lineWidth: 2)
            Circle()
                .trim(from: 0, to: CGFloat(readiness))
                .stroke(enabled ? Color.green : Color.orange,
                        style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .padding(3)
        }
        .contentShape(Circle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in if !down { down = true; onHold(true) } }
                .onEnded { _ in down = false; onHold(false) }
        )
    }
}
