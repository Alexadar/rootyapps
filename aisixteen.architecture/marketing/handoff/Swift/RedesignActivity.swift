import SwiftUI
// import ActivityKit — Widget extension target

// Live Activity — the queue's public face while backgrounded.
// Real stage + real step counts. If iOS suspends the work, state flips to
// .waiting ("Waiting for you") — it NEVER shows progress it isn't making.
// Completion per variation = local notification; tapping opens that Result.
// macOS: no Live Activity — standard user notification instead.

struct RedesignActivityAttributes /*: ActivityAttributes*/ {
    struct ContentState: Codable, Hashable {
        var spaceName: String        // "Living room"
        var styleName: String        // "Scandinavian"
        var stage: String            // GenerationStage.rawValue
        var step: Int
        var totalSteps: Int
        var queuedCount: Int
        var waiting: Bool            // background-suspended: no fake progress
        // Forming thumbnail: latest decoded latent, downscaled, via App Group container.
    }
    var projectID: String
}

struct RedesignLockScreenView: View {
    var state: RedesignActivityAttributes.ContentState
    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 12) // forming thumbnail
                .fill(LinearGradient(colors: [Color(hex: 0xE7E0D4), Color(hex: 0xC4AC82)],
                                     startPoint: .top, endPoint: .bottom))
                .frame(width: 52, height: 52)
                .overlay(Color.white.opacity(0.25).clipShape(RoundedRectangle(cornerRadius: 12)))
            VStack(alignment: .leading, spacing: 3) {
                Text("\(state.spaceName) · \(state.styleName)")
                    .font(.subheadline.weight(.semibold))
                if state.waiting {
                    Text("Waiting for you — opens where it left off")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("\(state.stage) · step \(state.step) of \(state.totalSteps)")
                        .font(.caption).foregroundStyle(.secondary)
                    ProgressView(value: Double(state.step), total: Double(state.totalSteps))
                        .tint(Color(hex: 0xE08A5C))
                }
            }
            Spacer()
            if state.queuedCount > 0 {
                Text("\(state.queuedCount) queued").font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .accessibilityElement(children: .combine)
    }
}
