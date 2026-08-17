import SwiftUI

// The multi-minute state. The forming image IS the progress bar:
// intermediate latents render under the milk veil (white .22, blur 26 → 0 pt).
// Named stages, real step counts — never a bare spinner, never a fake percent.
// Interruptions are pauses, never errors.
struct GeneratingView: View {
    var progress: GenerationProgress
    var queued: [String] = ["Variation 2", "Variation 3"]
    var onCancel: () -> Void = {}

    private var fraction: CGFloat { CGFloat(progress.step) / CGFloat(progress.totalSteps) }
    private var veilBlur: CGFloat { 26 * (1 - fraction) } // 26 → 0 across steps

    var body: some View {
        VStack(spacing: 0) {
            formingImage
            GlassSheet {
                VStack(alignment: .leading, spacing: 14) {
                    header
                    ProgressView(value: fraction).tint(DS.accent)
                        .accessibilityLabel("\(progress.stage.rawValue), step \(progress.step) of \(progress.totalSteps)")
                    stageList
                    if let pause = progress.pause { PauseCard(pause: pause) } else { leaveNote }
                    Button("Cancel this one", action: onCancel)
                        .buttonStyle(.glass)
                        .frame(maxWidth: .infinity)
                        .accessibilityHint("Cancels only this variation. Queued variations continue.")
                }
            }
            .offset(y: -DS.rSheet + 8)
        }
        .background(DS.canvas)
    }

    private var formingImage: some View {
        ZStack {
            if let img = progress.intermediate {
                Image(decorative: img, scale: 1).resizable().scaledToFill()
                    .blur(radius: veilBlur)
            } else {
                CameraPreviewPlaceholder().blur(radius: veilBlur)
            }
            Color.white.opacity(0.22) // milk veil
        }
        .frame(maxHeight: .infinity)
        .clipped()
        .accessibilityLabel("Preview of the redesign forming")
    }

    private var header: some View {
        HStack {
            Text(progress.stage.rawValue).font(.body.weight(.semibold))
            Spacer()
            Text("step \(progress.step) of \(progress.totalSteps)")
                .font(.footnote).foregroundStyle(.secondary)
        }
    }

    private var stageList: some View {
        VStack(alignment: .leading, spacing: 7) {
            ForEach(GenerationStage.allCases, id: \.rawValue) { stage in
                let state = stageState(stage)
                HStack(spacing: 8) {
                    switch state {
                    case .done: Image(systemName: "checkmark").font(.caption)
                    case .current: Circle().fill(DS.accent).frame(width: 8, height: 8)
                    case .pending: Circle().strokeBorder(.tertiary, lineWidth: 1.5).frame(width: 8, height: 8)
                    }
                    Text(stage.rawValue)
                        .font(.footnote.weight(state == .current ? .semibold : .regular))
                    if state == .current, let eta = progress.estimatedRemaining {
                        Text("· about \(Int(eta / 60).clamped(min: 1)) min left")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
                .foregroundStyle(state == .pending ? .tertiary : state == .done ? .secondary : .primary)
            }
        }
    }

    private var leaveNote: some View {
        (Text("You can leave — it keeps going and you'll get a notification. ")
         + Text("Queued next: ").bold()
         + Text(queued.joined(separator: ", ") + "."))
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 14).fill(Color.black.opacity(0.05)))
    }

    private enum StageState { case done, current, pending }
    private func stageState(_ s: GenerationStage) -> StageState {
        let order = GenerationStage.allCases
        guard let i = order.firstIndex(of: s), let c = order.firstIndex(of: progress.stage) else { return .pending }
        return i < c ? .done : i == c ? .current : .pending
    }
}

// One grammar for every interruption: what happened → what's safe → what resumes it.
struct PauseCard: View {
    let pause: GenerationPause
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.footnote.weight(.bold))
            Text(detail).font(.caption).foregroundStyle(.secondary)
            if case .lowBattery = pause {
                HStack(spacing: 8) {
                    Button("Resume anyway") {}.font(.caption.weight(.semibold))
                        .foregroundStyle(.white).padding(.horizontal, 14).padding(.vertical, 6)
                        .background(Capsule().fill(DS.ink))
                    Button("Wait for charge") {}.font(.caption.weight(.semibold))
                        .padding(.horizontal, 14).padding(.vertical, 6)
                        .background(Capsule().fill(Color.black.opacity(0.07)))
                }
                .padding(.top, 6)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14).fill(DS.canvasAlt))
    }
    private var title: String {
        switch pause {
        case .phoneCall: "Paused during your call."
        case .thermal: "Running slower to keep the phone cool."
        case .lowBattery: "Paused at 10% battery."
        case .backgroundSuspended: "Waiting for you."
        }
    }
    private var detail: String {
        switch pause {
        case .phoneCall: "It resumes by itself when the call ends — nothing is lost."
        case .thermal: "Time remaining updates as it goes. Setting the phone down helps."
        case .lowBattery: "Progress is saved. Resumes on charge — or resume now."
        case .backgroundSuspended: "iPhone set this aside to save power. It picks up exactly where it left off when you open the app."
        }
    }
}

private extension Int { func clamped(min m: Int) -> Int { Swift.max(self, m) } }
