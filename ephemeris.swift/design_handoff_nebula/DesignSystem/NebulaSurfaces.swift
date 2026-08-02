import SwiftUI
// import WidgetKit / ActivityKit in the widget extension targets.

/// Nebula tokens & guidance for the auxiliary surfaces:
/// WidgetKit (home + lock screen), ActivityKit (Dynamic Island), watchOS,
/// visionOS and tvOS. Uses NebulaPalette + Color(rgbHex:).
enum NebulaSurfaces {

    // MARK: Widget backgrounds (home screen)
    /// Same deep-space recipe as the app background, no star field
    /// (too noisy at widget size). Use in `containerBackground(for: .widget)`.
    static var widgetBackground: some View {
        ZStack {
            LinearGradient(colors: [NebulaPalette.bgTop, NebulaPalette.bgBottom],
                           startPoint: .top, endPoint: .bottom)
            RadialGradient(colors: [NebulaPalette.glowMagenta.opacity(0.9), .clear],
                           center: UnitPoint(x: 0.2, y: 0.0),
                           startRadius: 0, endRadius: 220)
        }
    }

    // MARK: Widget content patterns
    // Small  — "NEXT EVENT" (caption2, textHead, tracking 1) → big event glyph
    //          (30pt, #FFD9EA) → title (13.5pt bold, textPrimary, 2 lines)
    //          → date (11pt, accentCyan, monospacedDigit).
    // Medium — mini chart wheel left (rings + chords + planet glyphs only,
    //          no sign tiles) + 3 event rows right (12pt, glyph · bold label ·
    //          faint date).
    // Lock screen (accessory family): render `.accessoryCircular` as a Gauge
    //          (currentValueLabel = "☿︎") in `.gaugeStyle(.accessoryCircularCapacity)`;
    //          `.accessoryRectangular` = bold line "☿︎ ℞ · Full Moon Jul 10" +
    //          secondary "Next: Inf. ☌︎ Jul 13". Lock widgets are system-tinted —
    //          do not hard-code Nebula colors there.

    // MARK: ActivityKit (retrograde live activity)
    // Compact leading:  "☿︎ ℞" in NebulaPalette.retrograde
    // Compact trailing: "D−16d" monospacedDigit, textPrimary
    // Expanded center:  ProgressView tinted with `wordmark` gradient
    //                   (magenta→cyan), track white @ 25%.
    static let liveActivityTrack = Color(rgbHex: 0x966EFF).opacity(0.25)

    // MARK: watchOS
    // App: EPHEMERIS wordmark (10pt, wordmark gradient) + time (accentCyan),
    //      wheel at ~128pt (rings 2pt, chords 3.5pt, planet glyphs 26pt SVG-scale),
    //      one status capsule (cardFill bg, cardBorder stroke, radius 14).
    // Complications: circular = Gauge with ☿︎; keep monochrome-safe for
    //      tinted faces.

    // MARK: visionOS
    // Use `.glassBackgroundEffect()` on the window — do NOT paint the Nebula
    // gradient as window background; only content tints carry the brand.
    // Rings/spokes switch to white opacities (0.35 / 0.2 / 0.14) since the
    // glass is bright; aspect rows sit in capsules of white @ 8%.

    // MARK: tvOS
    // Full-bleed NebulaBackground. Title 40pt heavy with the title glow.
    // Event cards: unfocused = cardFill + cardBorder, radius 20, padding 20;
    //      focused = white @ 14% fill, 2pt white @ 85% border, scale 1.03,
    //      shadow #000 @ 60% r 50 + violet glow (150,110,255 @ 35%) r 34.
    //      Let the system focus effect drive scale/parallax where possible.

    // MARK: Notifications
    // Rich notification attachment/banner styling is system-owned; the app
    // icon carries the brand (nebula radial + ✦). Copy pattern:
    //   title: event, plain ("Mercury stations direct", "Full Moon tonight 🌕")
    //   body:  one sentence of astronomy + one actionable detail
    //          ("Retrograde ends at 6°♋︎ 18′ … elongation W peaks Aug 2.")
}
