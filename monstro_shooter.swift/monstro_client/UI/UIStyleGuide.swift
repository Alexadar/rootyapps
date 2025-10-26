import SpriteKit
#if os(macOS)
import AppKit
typealias PlatformColor = NSColor
#else
import UIKit
typealias PlatformColor = UIColor
#endif

// MARK: - UIStyleGuide
struct UIStyleGuide {

    // MARK: - Color Palette
    struct Colors {
        // Primary
        static let deepSpaceBlue = PlatformColor(hex: "#0A1428")
        static let cyanAccent = PlatformColor(hex: "#00D9FF")
        static let electricBlue = PlatformColor(hex: "#0066FF")

        // Secondary
        static let gold = PlatformColor(hex: "#FFD700")
        static let brightGreen = PlatformColor(hex: "#00FF99")
        static let white = PlatformColor(hex: "#FFFFFF")
        static let orange = PlatformColor(hex: "#FF8800")

        // Backgrounds
        static let containerBg = PlatformColor(hex: "#0A1428")
        static let overlayBg = PlatformColor(hex: "#000000")
    }

    // MARK: - Glow Effects
    struct Glow {
        let color: PlatformColor
        let radius: CGFloat
        let opacity: CGFloat

        static let cyan = Glow(
            color: Colors.cyanAccent,
            radius: 8.0,
            opacity: 0.8
        )

        static let white = Glow(
            color: Colors.white,
            radius: 6.0,
            opacity: 0.6
        )

        static let subtle = Glow(
            color: Colors.cyanAccent,
            radius: 4.0,
            opacity: 0.4
        )

        static let strong = Glow(
            color: Colors.cyanAccent,
            radius: 12.0,
            opacity: 0.9
        )
    }

    // MARK: - Typography
    struct Typography {
        #if os(macOS)
        static let header = NSFont.systemFont(ofSize: 20, weight: .bold)
        static let stats = NSFont.systemFont(ofSize: 26, weight: .bold)
        static let body = NSFont.systemFont(ofSize: 13, weight: .regular)
        static let button = NSFont.systemFont(ofSize: 16, weight: .bold)
        static let smallButton = NSFont.systemFont(ofSize: 14, weight: .semibold)
        static let label = NSFont.systemFont(ofSize: 12, weight: .regular)
        #else
        static let header = UIFont.systemFont(ofSize: 20, weight: .bold)
        static let stats = UIFont.systemFont(ofSize: 26, weight: .bold)
        static let body = UIFont.systemFont(ofSize: 13, weight: .regular)
        static let button = UIFont.systemFont(ofSize: 16, weight: .bold)
        static let smallButton = UIFont.systemFont(ofSize: 14, weight: .semibold)
        static let label = UIFont.systemFont(ofSize: 12, weight: .regular)
        #endif
    }

    // MARK: - Button Styles
    struct Button {
        // Primary Button
        struct Primary {
            static let backgroundColor = Colors.deepSpaceBlue
            static let backgroundOpacity: CGFloat = 0.7
            static let borderColor = Colors.white
            static let borderWidth: CGFloat = 2.0
            static let borderGlow = Glow.white
            static let textColor = Colors.white
            static let textFont = Typography.button
            static let textGlow = Glow.white
            static let cornerRadius: CGFloat = 8.0
            static let paddingHorizontal: CGFloat = 24.0
            static let paddingVertical: CGFloat = 12.0
            static let minHeight: CGFloat = 44.0
        }

        // Secondary Button
        struct Secondary {
            static let backgroundColor = Colors.deepSpaceBlue
            static let backgroundOpacity: CGFloat = 0.5
            static let borderColor = Colors.cyanAccent
            static let borderWidth: CGFloat = 2.0
            static let borderGlow = Glow.cyan
            static let textColor = Colors.cyanAccent
            static let textFont = Typography.button
            static let textGlow = Glow.subtle
            static let cornerRadius: CGFloat = 8.0
            static let paddingHorizontal: CGFloat = 20.0
            static let paddingVertical: CGFloat = 10.0
            static let minHeight: CGFloat = 40.0
        }

        // Small Button (Plus buttons, etc)
        struct Small {
            static let backgroundColor = Colors.deepSpaceBlue
            static let backgroundOpacity: CGFloat = 0.6
            static let borderColor = Colors.cyanAccent
            static let borderWidth: CGFloat = 1.5
            static let borderGlow = Glow.subtle
            static let contentColor = Colors.white
            static let iconSize: CGFloat = 20.0
            static let textFont = Typography.smallButton
            static let size: CGFloat = 32.0
            static let cornerRadius: CGFloat = 6.0
        }
    }

    // MARK: - Container Styles
    struct Container {
        static let backgroundColor = Colors.containerBg
        static let backgroundOpacity: CGFloat = 0.85
        static let borderColor = Colors.cyanAccent
        static let borderWidth: CGFloat = 2.0
        static let borderGlow = Glow.cyan
        static let cornerRadius: CGFloat = 10.0
        static let padding: CGFloat = 12.0
        static let spacing: CGFloat = 10.0
    }

    // MARK: - Dimensions
    struct Layout {
        static let cornerRadius: CGFloat = 10.0
        static let borderWidth: CGFloat = 2.0
        static let containerPadding: CGFloat = 12.0
        static let elementSpacing: CGFloat = 10.0
        static let topBarHeight: CGFloat = 64.0
        static let bottomBarHeight: CGFloat = 140.0
    }
}

// MARK: - PlatformColor Hex Extension
extension PlatformColor {
    convenience init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }

        #if os(macOS)
        self.init(
            red: CGFloat(r) / 255,
            green: CGFloat(g) / 255,
            blue: CGFloat(b) / 255,
            alpha: CGFloat(a) / 255
        )
        #else
        self.init(
            red: CGFloat(r) / 255,
            green: CGFloat(g) / 255,
            blue: CGFloat(b) / 255,
            alpha: CGFloat(a) / 255
        )
        #endif
    }
}

// MARK: - SKNode Glow Extension
extension SKNode {
    func applyGlow(_ glow: UIStyleGuide.Glow) {
        let effectNode = SKEffectNode()
        effectNode.shouldRasterize = true

        let filter = CIFilter(name: "CIGaussianBlur")
        filter?.setValue(glow.radius, forKey: kCIInputRadiusKey)
        effectNode.filter = filter
        effectNode.alpha = glow.opacity

        // Apply to node
        if let parent = self.parent {
            parent.addChild(effectNode)
            self.removeFromParent()
            effectNode.addChild(self)
        }
    }
}
