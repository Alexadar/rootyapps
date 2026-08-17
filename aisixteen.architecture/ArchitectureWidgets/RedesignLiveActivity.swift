import ActivityKit
import SwiftUI
import WidgetKit

/// The queue's public face while the app is not on screen.
///
/// The one rule that governs every line of this file: **it never shows progress it is not making.**
/// When the app is suspended the state flips to `waiting`, the step counter freezes exactly where
/// it was, and the text reads "Waiting for you". An activity that keeps ticking on a lock screen
/// while nothing is running is lying somewhere the user cannot even open the app to check.
struct RedesignLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RedesignActivityAttributes.self) { context in
            LockScreenView(attributes: context.attributes, state: context.state)
                .activityBackgroundTint(Color(hex: 0x1D1A17).opacity(0.82))
                .activitySystemActionForegroundColor(Color(hex: RedesignActivity.accentHex))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    FormingThumbnail(state: context.state, size: 44)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if let queued = queueText(context.state.queuedCount) {
                        Text(queued)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(context.state.spaceName) · \(context.state.styleName)")
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                        Text(context.state.statusLine)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    if !context.state.waiting {
                        ProgressView(value: Double(context.state.step),
                                     total: Double(max(context.state.totalSteps, 1)))
                            .tint(Color(hex: RedesignActivity.accentHex))
                    }
                }
            } compactLeading: {
                FormingThumbnail(state: context.state, size: 18)
            } compactTrailing: {
                // Frozen while waiting: an ellipsis, not a number that is not moving.
                Text(context.state.waiting
                     ? "…"
                     : "\(context.state.step)/\(context.state.totalSteps)")
                    .font(.caption2.monospacedDigit())
            } minimal: {
                FormingThumbnail(state: context.state, size: 18)
            }
            .keylineTint(Color(hex: RedesignActivity.accentHex))
        }
    }

    private func queueText(_ count: Int) -> String? {
        count > 0 ? "\(count) queued" : nil
    }
}

struct LockScreenView: View {
    let attributes: RedesignActivityAttributes
    let state: RedesignActivityAttributes.ContentState

    var body: some View {
        HStack(spacing: 12) {
            FormingThumbnail(state: state, size: 52)

            VStack(alignment: .leading, spacing: 3) {
                Text("\(state.spaceName) · \(state.styleName)")
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)

                Text(state.statusLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                if !state.waiting {
                    ProgressView(value: Double(state.step),
                                 total: Double(max(state.totalSteps, 1)))
                        .tint(Color(hex: RedesignActivity.accentHex))
                        .frame(maxWidth: 180)
                }
            }

            Spacer(minLength: 4)

            if state.queuedCount > 0 {
                Text("\(state.queuedCount) queued")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .accessibilityElement(children: .combine)
        // `.combine` synthesises a joined identifier on macOS and drops the children's; naming the
        // result explicitly is the fix (uitests.md §3, trap 4). Harmless here and correct.
        .accessibilityIdentifier("activity.lockscreen")
        .accessibilityLabel("\(state.spaceName), \(state.styleName). \(state.statusLine)")
    }
}

/// The latest decoded latent, read from the shared App Group container.
///
/// Content state is capped at a few KB and cannot carry a picture, so the app writes a ~20 KB JPEG
/// to the group and the widget loads it by name. `thumbnailStamp` is in the state purely so the
/// content changes when the file does — without it the widget serves a cached image for an
/// unchanged file name and the picture never appears to form.
struct FormingThumbnail: View {
    let state: RedesignActivityAttributes.ContentState
    let size: CGFloat

    var body: some View {
        ZStack {
            if let image = loaded {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                LinearGradient(colors: [Color(hex: 0xE7E0D4), Color(hex: 0xC4AC82)],
                               startPoint: .top, endPoint: .bottom)
            }
            // The milk veil, so the thumbnail reads as forming rather than finished.
            Color.white.opacity(0.25)
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size > 24 ? 12 : 5, style: .continuous))
        .accessibilityHidden(true)
        .id(state.thumbnailStamp)
    }

    private var loaded: UIImage? {
        guard let name = state.thumbnailName else { return nil }
        let jobID = (name as NSString).deletingPathExtension
        guard let url = RedesignActivity.thumbnailURL(jobID: jobID) else { return nil }
        return UIImage(contentsOfFile: url.path)
    }
}

private extension Color {
    init(hex: UInt32) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: 1)
    }
}
