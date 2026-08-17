import SwiftUI

/// Which of the three glass variants a surface is.
///
/// Anything that is not one of these is not in the design.
enum GlassRole: Equatable {
    /// The default plate: the control panel, cards, tiles, the segment shell.
    case regular
    /// The single accent. Enhance, Save — one per screen, never two.
    case tinted
    /// A plate that responds to touch. Same material, `interactive()` so the system does the press
    /// response rather than a hand-rolled scale.
    case interactive
}

/// **The one place glass is applied.**
///
/// Every glass surface in the app goes through this modifier, for one reason: Reduce Transparency
/// has to change the material *everywhere*, and a design with even one bare `.glassEffect` call site
/// ships a screen that ignores the setting. It also means the opaque fallback is written once,
/// against the handoff's tokens, instead of guessed at per view.
///
/// Under Reduce Transparency (`1k`): the fill becomes opaque `#F7F6F4`, blur and glass shadows drop,
/// a 1 px hairline stays, and **the geometry does not move**. The setting changes material, never
/// meaning or layout.
///
/// ⚠️ `.ultraThinMaterial`, `.regularMaterial` and `.thinMaterial` appear nowhere in this app. The
/// legacy build is made of them, and `MaterialsChecks` scans the sources to keep it that way.
private struct GlassPlateModifier<S: Shape>: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var scheme

    let role: GlassRole
    let shape: S
    /// Only over light content. Over a dark photo a drop shadow does nothing — the fill floor and
    /// the hairline are what separate the plate.
    let shadow: Bool

    func body(content: Content) -> some View {
        if reduceTransparency {
            content
                .background(opaqueFill, in: shape)
                .overlay(shape.stroke(ST.hairline(scheme, opaque: true), lineWidth: 1))
        } else {
            content
                .glassEffect(glass, in: shape)
                // The handoff's recipe is not just a blur: a 0.5 pt `rgba(255,255,255,.78)` hairline
                // plus an inset top highlight. Over a pale photo the system material has almost
                // nothing to refract, so without these the plate reads as flat paper and the panel
                // loses its edge against the picture.
                //
                // One stroke does both jobs: bright at the top where the inset highlight sits,
                // settling to the plain hairline lower down. `strokeBorder` would be tidier but is
                // only available on `InsettableShape`, and this modifier is generic over `Shape` so
                // a Capsule, a rounded rect and a Circle can all use it.
                .overlay(
                    shape.stroke(
                        LinearGradient(colors: [.white.opacity(scheme == .dark ? 0.32 : 0.95),
                                                hairlineColour],
                                       startPoint: .top, endPoint: .bottom),
                        lineWidth: 0.75)
                        .allowsHitTesting(false))
                .shadow(color: shadowColour, radius: shadow ? 14 : 0, y: shadow ? 6 : 0)
        }
    }

    private var glass: Glass {
        switch role {
        case .regular:     return .regular
        case .tinted:      return .regular.tint(ST.accent)
        case .interactive: return .regular.interactive()
        }
    }

    /// Brighter on a tinted plate, where it has to read against the accent rather than the photo.
    private var hairlineColour: Color {
        role == .tinted ? .white.opacity(0.5) : ST.hairline(scheme)
    }

    private var opaqueFill: Color {
        role == .tinted ? ST.opaqueAccent : ST.opaquePlate(scheme)
    }

    /// `0 14px 40px rgba(20,20,25,.22)` from the token table, softened for the darker scheme where
    /// it would only muddy the photo.
    private var shadowColour: Color {
        guard shadow else { return .clear }
        if scheme == .dark { return .black.opacity(0.28) }
        return role == .tinted ? ST.accent.opacity(0.24) : Color(hex: 0x141419).opacity(0.22)
    }
}

extension View {
    /// Applies the app's glass material to a shape.
    ///
    /// - Parameter shadow: pass `true` for plates that float over a photo. A white plate on a pale
    ///   photo disappears without it, and it must be absent on plates that sit on the canvas.
    func stGlass<S: Shape>(_ role: GlassRole = .regular, in shape: S, shadow: Bool = true) -> some View {
        modifier(GlassPlateModifier(role: role, shape: shape, shadow: shadow))
    }

    func stGlassCapsule(_ role: GlassRole = .regular, shadow: Bool = true) -> some View {
        stGlass(role, in: Capsule(), shadow: shadow)
    }

    func stGlassCard(_ role: GlassRole = .regular,
                     radius: CGFloat = ST.Radius.card,
                     shadow: Bool = true) -> some View {
        stGlass(role, in: RoundedRectangle(cornerRadius: radius, style: .continuous), shadow: shadow)
    }
}

/// The label colour that belongs on a given plate.
///
/// A tinted plate always carries white; a regular plate carries ink. Written down because getting it
/// wrong is the failure mode the legibility rules exist to catch, and because under Reduce
/// Transparency the tinted plate is a flat blue where a mid-grey label would vanish.
enum GlassLabel {
    static func color(on role: GlassRole, scheme: ColorScheme, enabled: Bool = true) -> Color {
        switch role {
        case .tinted:
            return enabled ? .white : .white.opacity(0.5)
        case .regular, .interactive:
            return enabled ? ST.ink(scheme) : ST.inkDisabled(scheme)
        }
    }
}
