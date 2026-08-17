import SwiftUI

/// The floating glass segment: Redesign · Library.
///
/// **Not a `TabView`.** The handoff is explicit, and the reason is that a tab bar is a chrome the
/// system owns and styles — the whole shell here is one piece of glass floating over a full-bleed
/// photo, and a tab bar would put an opaque system surface underneath it.
struct ScreenSegment: View {
    @Binding var section: Router.Section

    var body: some View {
        GlassSegment(options: Router.Section.allCases,
                     selection: $section,
                     title: \.rawValue,
                     identifier: { "shell.segment.\($0.rawValue.lowercased())" },
                     accessibilityLabel: "Screen")
    }
}
