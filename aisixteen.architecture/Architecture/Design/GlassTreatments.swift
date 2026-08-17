import SwiftUI

/// THE SINGLE CHOKEPOINT for Liquid Glass in this app.
///
/// Nothing else calls `.glassEffect` directly. There is a grep guard for it in the unit tests,
/// and the reason is the sibling's, stated plainly in its own treatments file: *a design with even
/// one bare `.glassEffect` call site ships a screen that ignores Reduce Transparency.* The handoff
/// mockups are that design — every surface in them is a bare `.glassEffect(in:)`, and not one of
/// them responds to the setting.
///
/// Under Reduce Transparency the fill becomes opaque `#F6F3ED` with a hairline border and
/// **geometry that does not move**: same shape, same radius, same padding, same shadow-free
/// footprint. The README's wording is "layout identical", and it means it — nothing may reflow
/// when the setting changes, or a user who needs it gets a different app.
///
/// ⚠️ NEVER `.ultraThinMaterial` / `.regularMaterial` / `.thinMaterial`. Those are the previous
/// generation, they are what `aisixteen.studio.old` is built on, and they are exactly what this
/// family is not.
enum GlassRole: Equatable {
    /// The default surface: sheets, cards, capsules.
    case regular
    /// Carries the accent. Used sparingly — a tinted surface competes with the accent's real job,
    /// which is to mark the one thing the user is choosing.
    case tinted
    /// Responds to touch. For controls that are pressed rather than read.
    case interactive
}

private struct GlassPlate<S: Shape>: ViewModifier {
    let role: GlassRole
    let shape: S
    let shadow: Bool

    @Environment(\.arcAccessibility) private var accessibility
    @Environment(\.accentDrained) private var accentDrained

    func body(content: Content) -> some View {
        if accessibility.reduceTransparency {
            content
                .background(ARC.opaquePlate, in: shape)
                .overlay {
                    shape.stroke(ARC.hairline(opaque: true), lineWidth: 0.5)
                        .allowsHitTesting(false)
                }
        } else {
            content
                .glassEffect(glass, in: shape)
                .overlay {
                    // The border recipe from the token table: white .60 → .70, top-lit.
                    shape.stroke(
                        LinearGradient(colors: [ARC.hairline(opaque: false).opacity(ARC.Glass.borderHigh),
                                                ARC.hairline(opaque: false).opacity(ARC.Glass.borderLow)],
                                       startPoint: .top, endPoint: .bottom),
                        lineWidth: 0.75)
                    .allowsHitTesting(false)
                }
                .shadow(color: .black.opacity(shadow ? 0.10 : 0),
                        radius: shadow ? 10 : 0, y: shadow ? 5 : 0)
        }
    }

    private var glass: Glass {
        switch role {
        case .regular: return .regular
        case .tinted: return .regular.tint(accentDrained ? ARC.neutral : ARC.accent)
        case .interactive: return .regular.interactive()
        }
    }
}

extension View {
    func arcGlass<S: Shape>(_ role: GlassRole = .regular,
                            in shape: S,
                            shadow: Bool = true) -> some View {
        modifier(GlassPlate(role: role, shape: shape, shadow: shadow))
    }

    func arcGlassCapsule(_ role: GlassRole = .regular, shadow: Bool = true) -> some View {
        arcGlass(role, in: Capsule(), shadow: shadow)
    }

    func arcGlassCard(_ role: GlassRole = .regular,
                      radius: CGFloat = ARC.Radius.card,
                      shadow: Bool = true) -> some View {
        arcGlass(role, in: RoundedRectangle(cornerRadius: radius, style: .continuous), shadow: shadow)
    }

    /// The bottom sheet's top corners, and the one shape the handoff's `GlassSheet` used.
    func arcGlassSheet(shadow: Bool = true) -> some View {
        arcGlass(.regular,
                 in: UnevenRoundedRectangle(topLeadingRadius: ARC.Radius.sheet,
                                            bottomLeadingRadius: 0,
                                            bottomTrailingRadius: 0,
                                            topTrailingRadius: ARC.Radius.sheet,
                                            style: .continuous),
                 shadow: shadow)
    }
}

/// Label colour that stays legible on glass and on the opaque fallback alike.
enum GlassLabel {
    static func color(enabled: Bool = true) -> Color {
        enabled ? ARC.ink : ARC.ink.opacity(0.35)
    }
}
