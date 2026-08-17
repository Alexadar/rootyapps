import SwiftUI

@main
struct TarotApp: App {
    @State private var model = AppModel(renderer: RealityCardRenderer(),
                                        writer: TarotApp.writer())

    /// A filmed take replays its recorded reading instead of asking the model — same seam,
    /// same streaming, no variance. The only writer-injection point in the app.
    private static func writer() -> any ReadingWriter {
        #if DEBUG
        // `-TAROT_SCENARIO_LIVE` runs a scenario's cards and pacing through the REAL model.
        // It is how a scenario's text gets written in the first place: the words have to be
        // about the forced cards, so the harness must exist before the text can be captured.
        if let scenario = FilmScenario.fromLaunchArguments(),
           !LaunchOverride.present("-TAROT_SCENARIO_LIVE") {
            return ScriptedWriter(scenario: scenario)
        }
        #endif
        return FoundationModelsWriter()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .preferredColorScheme(.dark)
        }
        #if os(macOS)
        .defaultSize(width: 760, height: 1000)
        #endif
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            Tokens.background.ignoresSafeArea()
            GameView()
                .ignoresSafeArea()
            switch model.screen {
            case .menu: MenuOverlay()
            case .draw: DrawOverlay()
            case .reading: ReadingOverlay()
            }
            if !model.curtainGone {
                LaunchCurtain(back: model.artProvider.backArt().face)
                    .opacity(model.sceneReady ? 0 : 1)
                    .animation(.easeOut(duration: AppModel.curtainFade), value: model.sceneReady)
                    // Opaque means opaque: a tap that lands on "Begin a Draw" through the
                    // curtain would start a draw the reader never saw themselves ask for.
                    .allowsHitTesting(!model.sceneReady)
            }
        }
        .onAppear { model.reduceMotion = reduceMotion }
        .onChange(of: reduceMotion) { _, newValue in model.reduceMotion = newValue }
        .onChange(of: scenePhase) { _, newPhase in model.setSceneActive(newPhase == .active) }
    }
}
