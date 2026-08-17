import SwiftUI

// Two-screen shell: floating glass segment control (Redesign · Library),
// one GlassEffectContainer — NOT a TabView. Same shell as the wallpaper app.
struct RootView: View {
    enum Tab: String, CaseIterable { case redesign = "Redesign", library = "Library" }
    @State private var tab: Tab = .redesign
    @Namespace private var glass

    var body: some View {
        GlassEffectContainer {
            ZStack(alignment: .top) {
                switch tab {
                case .redesign: CaptureView()
                case .library: LibraryView()
                }
                segment
                    .padding(.top, 8)
            }
        }
        .background(DS.canvas)
    }

    private var segment: some View {
        HStack(spacing: 0) {
            ForEach(Tab.allCases, id: \.self) { t in
                Button(t.rawValue) { withAnimation(DS.morph) { tab = t } }
                    .font(.subheadline.weight(tab == t ? .semibold : .regular))
                    .foregroundStyle(tab == t ? .white : DS.ink)
                    .padding(.horizontal, 20).padding(.vertical, 8)
                    .background {
                        if tab == t {
                            Capsule().fill(DS.ink)
                                .matchedGeometryEffect(id: "seg", in: glass)
                        }
                    }
                    .accessibilityAddTraits(tab == t ? .isSelected : [])
            }
        }
        .padding(3)
        .glassEffect(in: .capsule)
    }
}
