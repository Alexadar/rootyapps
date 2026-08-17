import SwiftUI

/// What sits behind the glass.
///
/// Glass takes its character from its backdrop, so this is not decoration — it is half of every
/// control's appearance. The bundle specifies two cases: the most recent wallpaper, heavily blurred
/// and dimmed, once there is one; and a pale dawn gradient on first launch, before there is.
struct AmbientBackground: View {
    @Environment(\.colorScheme) private var scheme

    /// The most recent wallpaper, or `nil` on first launch.
    var recent: PlatformImage?

    var body: some View {
        ZStack {
            gradient
            if let recent {
                // **Measured and clipped.** `scaledToFill` makes the image's frame *larger* than the
                // space offered, and a ZStack sizes itself to its largest child — so an unclipped
                // fill here silently inflated the whole screen's width, and every `maxWidth:
                // .infinity` control inside the app stretched off both edges to match. The bug was
                // never in the padding; it was in this background.
                GeometryReader { proxy in
                    Image(platformImage: recent)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        // Heavy enough that no detail survives — a colour field derived from the
                        // user's own picture, not a thumbnail of it.
                        .blur(radius: 60, opaque: true)
                        .clipped()
                        .overlay(dimming)
                }
                .accessibilityHidden(true)
            }
        }
        .ignoresSafeArea()
    }

    private var gradient: some View {
        // Radial from the top, matching the bundle's `radial-gradient(120% 90% at 50% 0%, …)`.
        RadialGradient(colors: scheme == .dark ? WP.darkBackground : WP.dawn,
                       center: .top,
                       startRadius: 0,
                       endRadius: 900)
    }

    /// Keeps a bright wallpaper from turning the backdrop into a light box, and a dark one from
    /// swallowing the plates. Both extremes are what the legibility proof (`1g`) is about.
    private var dimming: some View {
        (scheme == .dark ? Color.black.opacity(0.45) : Color.white.opacity(0.55))
    }
}

/// The Mac window's warm paper. Not a stretched phone background — the window is its own object.
struct MacPaperBackground: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        LinearGradient(colors: scheme == .dark ? WP.darkBackground : WP.macPaper,
                       startPoint: .topLeading,
                       endPoint: .bottomTrailing)
            .ignoresSafeArea()
    }
}
