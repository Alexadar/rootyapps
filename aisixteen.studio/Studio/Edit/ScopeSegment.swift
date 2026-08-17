import SwiftUI
import RecipeKit

/// Whole photo · Subject · Background · Brush (`1b`, `1g`, `1h`).
///
/// Not a `Picker`: the segment carries per-scope state the system control cannot express — a scope
/// whose mask is still being computed, and one that turned out to be unavailable because the photo
/// has no clear subject.
struct ScopeSegment: View {

    @Environment(\.colorScheme) private var scheme

    @Binding var selection: Scope
    var compact: Bool = false
    var availability: (Scope) -> MaskAvailability

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Scope.allCases, id: \.self) { scope in
                item(scope)
            }
        }
        .padding(3)
        .stGlass(.regular, in: Capsule(), shadow: false)
        .accessibilityIdentifier("edit.scope")
    }

    private func item(_ scope: Scope) -> some View {
        let selected = selection == scope
        let state = availability(scope)

        return Button {
            selection = scope
        } label: {
            HStack(spacing: 5) {
                if state == .working && selected {
                    ProgressView().controlSize(.mini)
                }
                Text(compact ? scope.compactDisplayName : scope.displayName)
                    .stFont(.control)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(selected ? .white : ST.ink2(scheme))
            .padding(.horizontal, ST.Space.gap)
            .frame(height: ST.compactPillHeight)
            .frame(maxWidth: .infinity)
            .background {
                if selected {
                    Capsule().fill(ST.accent)
                }
            }
        }
        .buttonStyle(.plain)
        // The floor applies to the row even though each pill is 38 pt tall: the padding around the
        // segment brings the real target above 44.
        .frame(minHeight: ST.compactPillHeight)
        .accessibilityIdentifier("edit.scope.\(scope.rawValue)")
        .accessibilityLabel(scope.displayName)
        .accessibilityHint(scope.accessibilityHint)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }
}

/// The two-item shell that carries the whole app: Enhance · Library (`1a`).
///
/// ⚠️ **One `GlassEffectContainer`, not a `TabView`.** The handoff is explicit, and it is the same
/// shell as the wallpaper app — the family reads as a family because this component is identical in
/// both, not because the colours are similar.
struct SectionShell: View {

    @Environment(\.colorScheme) private var scheme
    @Namespace private var shell

    @Binding var selection: AppSection

    var body: some View {
        GlassEffectContainer(spacing: ST.Space.tight) {
            HStack(spacing: 4) {
                ForEach(AppSection.allCases, id: \.self) { section in
                    Button {
                        selection = section
                    } label: {
                        Label(section.title, systemImage: section.symbol)
                            .labelStyle(.titleAndIcon)
                            .stFont(.control)
                            .foregroundStyle(selection == section ? .white : ST.ink2(scheme))
                            .padding(.horizontal, ST.Space.grid)
                            .frame(height: ST.pillHeight)
                            .background {
                                if selection == section {
                                    Capsule()
                                        .fill(ST.accent)
                                        .matchedGeometryEffect(id: "section", in: shell)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("shell.\(section.rawValue)")
                    .accessibilityAddTraits(selection == section ? [.isButton, .isSelected] : .isButton)
                }
            }
            .padding(4)
            .stGlass(.regular, in: Capsule())
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: selection)
    }
}

enum AppSection: String, CaseIterable {
    case enhance
    case library

    var title: String {
        switch self {
        case .enhance: return "Enhance"
        case .library: return "Library"
        }
    }

    var symbol: String {
        switch self {
        case .enhance: return "wand.and.sparkles"
        case .library: return "square.grid.2x2"
        }
    }
}
