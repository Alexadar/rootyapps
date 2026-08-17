import SwiftUI

/// Which of the three glass variants a surface is.
///
/// The bundle defines exactly three (`1f`). Anything that is not one of these is not in the design.
enum GlassRole: Equatable {
    /// The default plate: prompt field, cards, tiles, the segment control.
    case regular
    /// The single accent. Create, Save for Wallpaper, Download — one per screen, never two.
    case tinted
    /// A plate that responds to touch. Same material, `interactive()` so the system does the
    /// press response rather than a hand-rolled scale.
    case interactive
}

/// **The one place glass is applied.**
///
/// Every glass surface in the app goes through this modifier, for one reason: Reduce Transparency
/// has to change the material *everywhere*, and a design with even one bare `.glassEffect` call
/// site ships a screen that ignores the setting. It also means the opaque fallback is written once,
/// against the bundle's tokens, instead of guessed at per view.
///
/// Under Reduce Transparency: fill becomes the opaque token, blur / saturation / inner highlight are
/// gone, the hairline stays, and **the geometry does not move**. The setting changes material, never
/// meaning or layout (bundle `1h`).
private struct GlassPlateModifier<S: Shape>: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var scheme

    let role: GlassRole
    let shape: S
    /// Only over light backdrops. On dark content a drop shadow does nothing — the fill floor and
    /// the hairline are what separate the plate (bundle `1g`).
    let shadow: Bool

    func body(content: Content) -> some View {
        if reduceTransparency {
            content
                .background(opaqueFill, in: shape)
                .overlay(shape.stroke(WP.hairline(scheme, opaque: true), lineWidth: 0.5))
        } else {
            content
                .glassEffect(glass, in: shape)
                // The bundle's recipe is not just a blur: `0.5 pt rgba(255,255,255,.8)` hairline
                // plus an inset top highlight. Over a pale backdrop the system material has almost
                // nothing to refract, so without these the plate reads as flat paper and the whole
                // screen loses its edges — which is exactly how it looked on device.
                // One stroke does both jobs the recipe asks for: bright at the top where the inset
                // highlight sits, settling to the plain hairline lower down. `strokeBorder` would be
                // tidier but is only available on `InsettableShape`, and this modifier is generic
                // over `Shape` so that a Capsule, a rounded rect and a Circle can all use it.
                .overlay(
                    shape.stroke(
                        LinearGradient(colors: [.white.opacity(scheme == .dark ? 0.32 : 0.95),
                                                hairlineColour],
                                       startPoint: .top, endPoint: .bottom),
                        lineWidth: 0.75)
                        .allowsHitTesting(false))
                .shadow(color: shadowColor, radius: shadow ? 10 : 0, y: shadow ? 5 : 0)
        }
    }

    private var glass: Glass {
        switch role {
        case .regular:     return .regular
        case .tinted:      return .regular.tint(WP.accent)
        case .interactive: return .regular.interactive()
        }
    }

    /// Brighter on a tinted plate, where it has to read against the accent rather than against the
    /// wallpaper.
    private var hairlineColour: Color {
        role == .tinted ? .white.opacity(0.5) : WP.hairline(scheme)
    }

    private var opaqueFill: Color {
        role == .tinted ? WP.opaqueAccent : WP.opaquePlate(scheme)
    }

    private var shadowColor: Color {
        guard shadow, scheme == .light else { return .clear }
        return role == .tinted ? WP.accent.opacity(0.20) : .black.opacity(0.08)
    }
}

extension View {
    /// Applies the app's glass material to a shape.
    ///
    /// - Parameter shadow: pass `true` for plates that float over pale content. The bundle's
    ///   legibility proof (`1g`) is explicit that this is the thing keeping a white plate from
    ///   disappearing into a near-white wallpaper, and equally that it must be absent on dark.
    func wpGlass<S: Shape>(_ role: GlassRole = .regular, in shape: S, shadow: Bool = true) -> some View {
        modifier(GlassPlateModifier(role: role, shape: shape, shadow: shadow))
    }

    func wpGlassCapsule(_ role: GlassRole = .regular, shadow: Bool = true) -> some View {
        wpGlass(role, in: Capsule(), shadow: shadow)
    }

    func wpGlassCard(_ role: GlassRole = .regular,
                     radius: CGFloat = WP.Radius.card,
                     shadow: Bool = true) -> some View {
        wpGlass(role, in: RoundedRectangle(cornerRadius: radius, style: .continuous), shadow: shadow)
    }
}

/// The label colour that belongs on a given plate.
///
/// A tinted plate always carries white; a regular plate carries ink. Written down because getting it
/// wrong is the failure mode the legibility proof exists to catch, and because under Reduce
/// Transparency the tinted plate is a flat blue where a mid-grey label would vanish.
enum GlassLabel {
    static func color(on role: GlassRole, scheme: ColorScheme, enabled: Bool = true) -> Color {
        switch role {
        case .tinted:
            return enabled ? .white : .white.opacity(0.5)
        case .regular, .interactive:
            return enabled ? WP.ink(scheme) : WP.inkDisabled(scheme)
        }
    }
}
