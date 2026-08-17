import SwiftUI
import ReachabilityKit

/// The state machine, keeping froggo 1's shape: a switch on the phase with a half-second cross-fade.
struct ContentView: View {
    @State private var session = GameSession()

    var body: some View {
        ZStack {
            Palette.sky.ignoresSafeArea()

            switch session.phase {
            case .menu:
                MainMenuView(session: session)
                    .transition(.opacity)
            case .loading:
                LoadingView()
                    .transition(.opacity)
            case .aiming, .flying, .landed:
                if session.hasDistrict {
                    GameView(session: session)
                        .transition(.opacity)
                } else {
                    LoadingView()
                }
            case .gameOver:
                GameOverView(session: session)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.5), value: session.phase)
        #if os(macOS)
        .frame(minWidth: 720, minHeight: 460)
        #endif
        .task {
            // FROGGO2_AUTOSTART=1 drops straight into a run. Capture tooling needs a way to reach
            // gameplay without driving the menu, and it is the same hook a scripted aim controller
            // will use for reel recording.
            if LaunchOverride.flag("FROGGO2_AUTOSTART"), session.phase == .menu {
                session.start()
            }
            // FROGGO2_DEMO=1 plays the game by itself along the solver's shortest route — the
            // capture path for reels and store screenshots.
            if LaunchOverride.flag("FROGGO2_DEMO") {
                try? await Task.sleep(for: .milliseconds(600))
                session.enableAutoPlay()
            }
        }
    }
}

struct MainMenuView: View {
    @Bindable var session: GameSession

    var body: some View {
        ZStack {
            LinearGradient(colors: [Palette.sky, Palette.sky.darkened(0.45)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            VStack(spacing: 26) {
                Spacer()
                Text("FROGGO 2")
                    .font(.system(size: 56, weight: .black, design: .rounded))
                    .foregroundStyle(Palette.frogBody)
                    .shadow(color: .black.opacity(0.5), radius: 4, x: 2, y: 3)
                Text("Frog Jump")
                    .font(.system(size: 21, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.9))

                Text("Drag back to aim. Let go to jump.\nCross the district to the beacon.")
                    .multilineTextAlignment(.center)
                    .font(.system(size: 15, design: .rounded))
                    .foregroundStyle(.white.opacity(0.75))
                    .padding(.top, 6)

                Button {
                    session.start()
                } label: {
                    Text("Start")
                        .font(.system(size: 19, weight: .bold, design: .rounded))
                        .frame(width: 190, height: 52)
                }
                .buttonStyle(FroggoButtonStyle(fill: Palette.frogBody, text: .white))
                .padding(.top, 10)

                if session.best > 0 {
                    Text("best \(session.best)")
                        .font(.system(size: 14, design: .rounded))
                        .foregroundStyle(.white.opacity(0.7))
                }
                Spacer()
            }
        }
    }
}

struct GameOverView: View {
    @Bindable var session: GameSession

    var body: some View {
        ZStack {
            LinearGradient(colors: [Palette.sky.darkened(0.3), Palette.sky.darkened(0.6)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            VStack(spacing: 20) {
                Spacer()
                Text("Splat")
                    .font(.system(size: 52, weight: .black, design: .rounded))
                    .foregroundStyle(Palette.frogBody)
                    .shadow(color: .black.opacity(0.5), radius: 4, x: 2, y: 3)

                // Froggo 1 computed both of these and then displayed neither.
                VStack(spacing: 6) {
                    Text("\(session.score)")
                        .font(.system(size: 44, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text("districts crossed: \(session.districtsCleared)")
                        .font(.system(size: 15, design: .rounded))
                        .foregroundStyle(.white.opacity(0.8))
                    Text("best \(session.best)")
                        .font(.system(size: 14, design: .rounded))
                        .foregroundStyle(.white.opacity(0.65))
                }

                Button {
                    session.restart()
                } label: {
                    Text("Try again")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .frame(width: 190, height: 50)
                }
                .buttonStyle(FroggoButtonStyle(fill: Palette.frogBody, text: .white))

                Button {
                    session.returnToMenu()
                } label: {
                    Text("Menu")
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .frame(width: 190, height: 46)
                }
                .buttonStyle(FroggoButtonStyle(fill: .white, text: .black))
                Spacer()
            }
        }
    }
}

/// froggo 1's `SquaredButtonStyle`, carried over: scale to 0.95 and dim slightly while pressed.
struct FroggoButtonStyle: ButtonStyle {
    let fill: Color
    let text: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(text)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(fill)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(.black.opacity(0.3), lineWidth: 2))
            )
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .brightness(configuration.isPressed ? -0.1 : 0)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

/// Shown while a district is being built and verified.
///
/// Generation is real work — a pool of candidates graded on the GPU, then the authoritative solver
/// run on the survivor — so it happens off the main actor and this stands in for it. It is usually
/// gone before the fade finishes; districts after the first are prefetched while the player is still
/// crossing the current one, so it should only ever be seen at the start of a run.
struct LoadingView: View {
    @State private var pulse = false

    var body: some View {
        ZStack {
            LinearGradient(colors: [Palette.sky, Palette.sky.darkened(0.45)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            VStack(spacing: 14) {
                Text("Building the block")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Text("checking every rooftop is reachable")
                    .font(.system(size: 13, design: .rounded))
                    .foregroundStyle(.white.opacity(0.75))
                Capsule()
                    .fill(Palette.frogBody)
                    .frame(width: pulse ? 150 : 40, height: 6)
                    .animation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true), value: pulse)
            }
        }
        .onAppear { pulse = true }
    }
}
