import FormatKit
import RedesignKit
import SwiftUI

/// Generating — the screen this whole product is really about.
///
/// The most complete file in the design handoff, and kept nearly verbatim: the stage list, the
/// milk veil, the leave note, the scoped cancel and every string. What changed:
///
///   • the accent DRAINS here, per the token table — the handoff tinted the bar with the accent,
///     which is the opposite of the stated rule;
///   • the veil is tokenised and steps under Reduce Motion;
///   • `queued` is the real queue rather than `["Variation 2", "Variation 3"]`;
///   • `PauseCard`'s two low-battery buttons do something.
struct GeneratingView: View {

    let progress: GenerationProgress
    let queuedLabels: [String]
    let variationLabel: String
    let styleName: String
    let onCancel: () -> Void
    let onResumeAnyway: () -> Void
    let onWaitForCharge: () -> Void

    @Environment(\.accentDrained) private var drained

    var body: some View {
        VStack(spacing: 0) {
            formingImage
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
            SheetSurface(layout: .sheet) { AnyView(sheet) }
        }
        .background(ARC.canvas)
    }

    // ── the forming image ────────────────────────────────────────────────────────────────────

    private var formingImage: some View {
        Group {
            if let image = progress.intermediate {
                Image(platform: image)
                    .resizable()
                    .scaledToFill()
            } else {
                LinearGradient(colors: [Color(hex: 0xB3A288), Color(hex: 0x75604A)],
                               startPoint: .top, endPoint: .bottom)
            }
        }
        .milkVeil(step: progress.step, totalSteps: progress.totalSteps)
        .accessibilityIdentifier("generating.image")
        .accessibilityLabel("Preview of the redesign forming")
    }

    // ── the sheet ────────────────────────────────────────────────────────────────────────────

    @ViewBuilder private var sheet: some View {
        VStack(alignment: .leading, spacing: ARC.Space.gap) {
            header
            bar
            stageList
            if let pause = progress.pause {
                PauseCard(pause: pause,
                          step: progress.step,
                          totalSteps: progress.totalSteps,
                          onResumeAnyway: onResumeAnyway,
                          onWaitForCharge: onWaitForCharge)
            } else {
                leaveNote
            }
            Button("Cancel this one", action: onCancel)
                .buttonStyle(.glass)
                .frame(maxWidth: .infinity)
                .frame(minHeight: ARC.minimumHitTarget)
                .accessibilityIdentifier("generating.cancel")
                .accessibilityHint("Cancels only this variation. Queued variations continue.")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(styleName) · \(variationLabel)")
                .arcText(.caption)
                .foregroundStyle(ARC.ink.opacity(0.55))
            HStack(alignment: .firstTextBaseline) {
                Text(progress.stage.rawValue)
                    .arcText(.heading)
                    .accessibilityIdentifier("generating.stage")
                Spacer()
                Text(StepText.progress(step: progress.step, of: progress.totalSteps))
                    .arcText(.secondary, tabularNumbers: true)
                    .foregroundStyle(ARC.ink.opacity(0.55))
                    .accessibilityIdentifier("generating.step")
            }
        }
    }

    private var bar: some View {
        ProgressView(value: progress.fraction)
            // The accent drains: terracotta is the colour of CHOICE in this app, and while a
            // render runs there is nothing to choose.
            .tint(ARC.accent(drained: drained))
            .animation(ARCMotion.progressFill, value: progress.fraction)
            .accessibilityIdentifier("generating.bar")
            .accessibilityLabel("\(progress.stage.rawValue), \(StepText.progress(step: progress.step, of: progress.totalSteps))")
    }

    private var stageList: some View {
        VStack(alignment: .leading, spacing: ARC.Space.tight) {
            ForEach(GenerationStage.allCases, id: \.self) { stage in
                StageRow(stage: stage,
                         state: state(of: stage),
                         suffix: stage == progress.stage
                            ? DurationText.stageSuffix(seconds: progress.estimatedRemaining)
                            : nil)
            }
        }
    }

    private func state(of stage: GenerationStage) -> StageRow.State {
        guard let current = GenerationStage.allCases.firstIndex(of: progress.stage),
              let index = GenerationStage.allCases.firstIndex(of: stage) else { return .pending }
        if index < current { return .done }
        if index == current { return .current }
        return .pending
    }

    /// The leave note, verbatim. Its promise is exact: it says the work keeps going and that a
    /// notification arrives — and in this build, where the render is foreground-only, it must not
    /// say more than the app can deliver.
    private var leaveNote: some View {
        Group {
            if !queuedLabels.isEmpty {
                // Markdown inside the literal, not `Text(…) + Text(…).bold()` — concatenating
                // `Text` is deprecated in iOS 26. The interpolated list stays plain; only the
                // literal "Queued next:" is bold, which is what the handoff specifies.
                Text("This keeps going while you watch. **Queued next:** \(queuedLabels.formatted(.list(type: .and)))")
            } else {
                Text("This keeps going while you watch, and you'll get a notification when it's done.")
            }
        }
        .arcText(.caption)
        .foregroundStyle(ARC.ink.opacity(0.6))
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(ARC.Space.gap)
        .background {
            RoundedRectangle(cornerRadius: ARC.Radius.chip, style: .continuous)
                .fill(Color.black.opacity(0.05))
        }
        .accessibilityIdentifier("generating.queue")
    }
}

/// One row of the stage list.
struct StageRow: View {
    enum State { case done, current, pending }

    let stage: GenerationStage
    let state: State
    let suffix: String?

    @Environment(\.accentDrained) private var drained

    var body: some View {
        HStack(spacing: ARC.Space.gap) {
            marker
                .frame(width: 12, height: 12)
            Text(suffix.map { "\(stage.rawValue) \($0)" } ?? stage.rawValue)
                .arcText(state == .current ? .subheading : .secondary)
                .foregroundStyle(colour)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        // `.combine` on macOS destroys the children's identifiers and synthesises a joined one, so
        // the combined element is named explicitly (uitests.md §3, trap 4).
        .accessibilityIdentifier("generating.stageRow.\(stage.rawValue.replacingOccurrences(of: " ", with: "-"))")
    }

    @ViewBuilder private var marker: some View {
        switch state {
        case .done:
            Image(systemName: "checkmark")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(ARC.ink.opacity(0.45))
        case .current:
            Circle().fill(ARC.accent(drained: drained)).frame(width: 8, height: 8)
        case .pending:
            Circle().strokeBorder(ARC.ink.opacity(0.22), lineWidth: 1.5).frame(width: 8, height: 8)
        }
    }

    private var colour: Color {
        switch state {
        case .done: return ARC.ink.opacity(0.55)
        case .current: return ARC.ink
        case .pending: return ARC.ink.opacity(0.32)
        }
    }
}
