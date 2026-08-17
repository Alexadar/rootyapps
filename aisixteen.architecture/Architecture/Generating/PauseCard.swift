import FormatKit
import RedesignKit
import SwiftUI

/// The interruption grammar: one shape for all four causes.
///
/// Every card says the same three things in the same order — what happened, what is safe, what
/// resumes it. That consistency is the point: a person who has seen the thermal card once already
/// knows how to read the low-battery one.
///
/// The copy is the handoff's, verbatim. The only change is that the two low-battery buttons now do
/// something; in the mockup both were `{}`.
struct PauseCard: View {

    let pause: GenerationPause
    let step: Int
    let totalSteps: Int
    let onResumeAnyway: () -> Void
    let onWaitForCharge: () -> Void

    var body: some View {
        SheetCard(radius: ARC.Radius.chip, fill: 1) {
            VStack(alignment: .leading, spacing: ARC.Space.tight) {
                HStack(spacing: ARC.Space.tight) {
                    Image(systemName: symbol)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(tint)
                    Text(pause.title)
                        .arcText(.captionStrong)
                        .foregroundStyle(ARC.ink)
                }

                Text(detail)
                    .arcText(.caption)
                    .foregroundStyle(ARC.ink.opacity(0.6))
                    .fixedSize(horizontal: false, vertical: true)

                if pause.offersResumeChoice {
                    HStack(spacing: ARC.Space.tight) {
                        PillButton(title: "Resume anyway", role: .ink, action: onResumeAnyway)
                            .accessibilityIdentifier("generating.pause.resume")
                        PillButton(title: "Wait for charge", role: .quiet, action: onWaitForCharge)
                            .accessibilityIdentifier("generating.pause.wait")
                    }
                    .padding(.top, 2)
                }
            }
        }
        .background {
            RoundedRectangle(cornerRadius: ARC.Radius.chip, style: .continuous)
                .fill(ARC.canvasAlt)
        }
        .accessibilityIdentifier("generating.pause")
    }

    /// Thermal is the one cause that is still making progress, so its card carries the step
    /// counter — "time remaining updates as it goes" is only credible next to a number that moves.
    private var detail: String {
        guard pause == .thermal else { return pause.detail }
        return "\(StepText.progress(step: step, of: totalSteps)) · \(pause.detail)"
    }

    private var symbol: String {
        switch pause {
        case .phoneCall: return "phone.fill"
        case .thermal: return "thermometer.medium"
        case .lowBattery: return "battery.25"
        case .backgroundSuspended: return "moon.zzz.fill"
        }
    }

    private var tint: Color {
        switch pause {
        // Still progressing, so it is information rather than a warning.
        case .thermal: return ARC.caution
        case .lowBattery: return ARC.caution
        case .phoneCall, .backgroundSuspended: return ARC.ink.opacity(0.5)
        }
    }
}

/// The in-flight queue, for the Mac sidebar's foot and the iPad rail.
struct QueueStrip: View {
    let jobs: [Job]
    let onCancel: (JobID) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: ARC.Space.tight) {
            ForEach(Array(jobs.enumerated()), id: \.element.id) { index, job in
                HStack(spacing: ARC.Space.tight) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(job.request.spaceName)
                            .arcText(.caption)
                            .foregroundStyle(ARC.ink)
                            .lineLimit(1)
                        Text(line(for: job))
                            .arcText(.micro, tabularNumbers: true)
                            .foregroundStyle(ARC.ink.opacity(0.55))
                            .lineLimit(1)
                    }
                    Spacer(minLength: ARC.Space.tight)
                    Button {
                        onCancel(job.id)
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .semibold))
                            .frame(width: ARC.minimumHitTarget, height: ARC.minimumHitTarget)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(ARC.ink.opacity(0.5))
                    .accessibilityIdentifier("queue.cancel.\(index)")
                    .accessibilityLabel("Cancel \(job.request.variationLabel)")
                }
                .padding(.horizontal, ARC.Space.tight)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("queue.row.\(index)")
            }
        }
    }

    /// Real step counts, never a spinner. The queue at the foot of the Mac sidebar is ambient, and
    /// ambient does not mean vague.
    private func line(for job: Job) -> String {
        switch job.phase {
        case .queued:
            return "Queued"
        case .running:
            return "\(job.stage.rawValue) · \(StepText.progress(step: job.step, of: job.totalSteps))"
        case .paused(let cause):
            return cause == .thermal
                ? "\(StepText.progress(step: job.step, of: job.totalSteps)) · running slower"
                : cause.title
        case .complete:
            return "Done"
        case .failed:
            return "Didn't finish"
        case .cancelled:
            return "Cancelled"
        }
    }
}
