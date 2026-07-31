import SwiftUI

/// Tapes are documents. Nothing device-local, so an iCloud container can be
/// switched on later without a migration.
@main
struct ParApp: App {
    /// A scratch tape used only by the capture scene below — never written to disk.
    @State private var scratch = CaptureMode.sampleTape

    // A DocumentGroup app opens on the system document browser. That is the right first run for a
    // user and useless for a capture, where the frame has to show the calculator working rather than
    // an empty file list.
    //
    // `SceneBuilder` has no conditionals and `defaultLaunchBehavior` is macOS-only, so the choice is
    // made at compile time: the capture scene is present ONLY in a build made with the `Capture`
    // configuration, which the media scripts use and which is never archived. The shipping binary
    // contains no capture path at all — not a suppressed one, none.
    //
    // It is the same `RootView` bound to the same `TapeDocument` either way; only how it is reached
    // differs. `PAR_TOOL` then selects which tool is on screen.
#if PAR_CAPTURE
    var body: some Scene {
        WindowGroup {
            RootView(document: $scratch)
        }
        .commands { toolCommands }
        // Capture only. A store screenshot and an app preview are both fixed-aspect, and a window
        // left at whatever size the system last remembered makes every capture a different shape.
        // 1440x900 is close enough to 16:9 that the preview's centre-crop stays shallow.
        #if os(macOS)
        .defaultSize(width: 1440, height: 900)
        #endif
    }
#else
    var body: some Scene {
        DocumentGroup(newDocument: TapeDocument()) { file in
            RootView(document: file.$document)
        }
        .commands { toolCommands }
    }
#endif

    @CommandsBuilder
    private var toolCommands: some Commands {
        CommandMenu("Solve") {
            AppendCommandButton()
        }
        CommandMenu("Tools") {
            ToolMenuItems()
        }
    }
}

/// ⌘⌥S — put the focused screen's solve on the tape.
///
/// Both menus shipped with eleven empty `{}` closures under a comment claiming "full keyboard
/// navigation on the Mac". They were dead because `.commands` is built outside any view and cannot
/// see `RootView`'s `@State`; the fix is a focused value, which is what `@FocusedValue` reads here.
private struct AppendCommandButton: View {
    @FocusedValue(\.appendToTape) private var append

    var body: some View {
        Button("Add to Tape") { append?.run() }
            .keyboardShortcut("s", modifiers: [.command, .option])
            .disabled(append == nil)
    }
}

private struct ToolMenuItems: View {
    @FocusedBinding(\.toolSelection) private var tool

    var body: some View {
        ForEach(Array(RootView.Tool.allCases.enumerated()), id: \.offset) { index, item in
            Button(item.rawValue) { tool = item }
                .keyboardShortcut(KeyEquivalent(Character("\((index + 1) % 10)")), modifiers: .command)
                .disabled(tool == nil)
        }
    }
}

/// The screenshot and app-preview pipelines' one hook into the app.
enum CaptureMode {
    /// True when `PAR_TOOL` names a tool — set by `marketing/make_sim_shots.sh` and by the UI tests.
    /// Unset in every shipping launch, so the document browser remains the real entry point.
    static var isActive: Bool { RootView.Tool.launchTool != nil }

    /// True when the capture wants the tape on screen (`PAR_TAPE=1`). On iPhone the tape is a second
    /// surface, so a screenshot has to ask for it; on iPad it is always beside the calculator.
    static var showsTape: Bool { LaunchOverride.flag("PAR_TAPE") }

    /// The work a real user would have on their tape by mid-morning: two refinance scenarios and the
    /// bond they are funding it against. Every row stores inputs only, exactly as a saved tape does,
    /// so the results in a screenshot are re-derived by the same code the app ships — not mocked.
    static var sampleTape: TapeDocument {
        // The reel sets PAR_TAPE_SEED=0: its whole point is watching a solve land on an empty tape,
        // and a pre-filled one would bury the new line below the fold.
        guard LaunchOverride.isNotDisabled("PAR_TAPE_SEED") else {
            return TapeDocument(title: "Refi comparison — Alvarez")
        }
        return TapeDocument(title: "Refi comparison — Alvarez", rows: [
            TapeRow(label: "123 Oak St — 30yr", inputs: .tvm(TVMInputs(
                periods: 360, annualRatePct: 6.25, presentValue: 420_000,
                payment: 0, futureValue: 0, solveFor: "payment"))),
            TapeRow(label: "123 Oak St — 15yr", inputs: .tvm(TVMInputs(
                periods: 180, annualRatePct: 5.75, presentValue: 420_000,
                payment: 0, futureValue: 0, solveFor: "payment"))),
            TapeRow(label: "Treasury 4¼ of 2031", inputs: .bond(BondInputs(
                couponPct: 4.25, price: 98.75, fullPeriods: 20,
                daysToNextCoupon: 91, daysInPeriod: 181,
                conventionRawValue: "actualActualICMA"))),
            TapeRow(label: "Escrow — 24 months", inputs: .amortization(AmortInputs(
                principal: 18_400, annualRatePct: 4.9, periods: 24, periodsPerYear: 12))),
        ])
    }
}
