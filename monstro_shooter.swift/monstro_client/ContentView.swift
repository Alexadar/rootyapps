import SwiftUI
import SpriteKit
#if os(macOS)
import AppKit
#else
import UIKit
#endif

// MARK: - Color Hex Extension
extension Color {
    init(hex: String) {
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
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

struct ContentView: View {
    @State private var showGame = false

    var body: some View {
        if showGame {
            GameView(onReturnToMenu: {
                showGame = false
            })
            .onAppear {
                // Switch to fight music when entering game
                AudioManager.shared.playFightMusic()
            }
        } else {
            AnimatedMainMenuView(onPlayTapped: {
                showGame = true
            })
            .onAppear {
                // Start menu music when menu appears
                AudioManager.shared.playMenuMusic()
            }
        }
    }
}

// MARK: - Animated Main Menu with arcade background
struct AnimatedMainMenuView: View {
    let onPlayTapped: () -> Void
    @State private var showSettings = false
    @State private var bgmEnabled = SettingsManager.shared.bgmEnabled
    @State private var sfxEnabled = SettingsManager.shared.sfxEnabled

    // Pick random arcade background at runtime
    @State private var backgroundImage: String = ["arcade_bg_1.jpg", "arcade_bg_2.jpg"].randomElement() ?? "arcade_bg_1.jpg"

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Arcade background with CSS cover style (aspect fill, centered)
                if let imagePath = Bundle.main.path(forResource: backgroundImage.replacingOccurrences(of: ".jpg", with: ""),
                                                    ofType: "jpg") {
                    let _ = print("[AnimatedMainMenuView] Using background: \(backgroundImage)")
                    #if os(macOS)
                    if let nsImage = NSImage(contentsOfFile: imagePath) {
                        Image(nsImage: nsImage)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: geometry.size.width, height: geometry.size.height)
                            .clipped()
                            .ignoresSafeArea()
                    } else {
                        Color.black.ignoresSafeArea()
                    }
                    #else
                    if let uiImage = UIImage(contentsOfFile: imagePath) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
                            .edgesIgnoringSafeArea(.all)
                    } else {
                        Color.black.ignoresSafeArea()
                    }
                    #endif
                } else {
                    // Fallback to black background
                    Color.black.ignoresSafeArea()
                }

                // Overlay UI (Play and Settings buttons with styleguide)
                VStack(spacing: 20) {
                    Spacer()

                    PrimaryButton(text: "PLAY", action: onPlayTapped)

                    SecondaryButton(text: "SETTINGS", action: { showSettings.toggle() })

                    Spacer().frame(height: 60)
                }

                // Settings popup overlay
                if showSettings {
                    SettingsView(
                        isPresented: $showSettings,
                        bgmEnabled: $bgmEnabled,
                        sfxEnabled: $sfxEnabled
                    )
                }
            }
        }
    }
}

// MARK: - Settings View
struct SettingsView: View {
    @Binding var isPresented: Bool
    @Binding var bgmEnabled: Bool
    @Binding var sfxEnabled: Bool

    var body: some View {
        ZStack {
            // Semi-transparent background
            Color.black.opacity(0.8)
                .ignoresSafeArea()
                .onTapGesture {
                    isPresented = false
                }

            // Settings panel
            VStack(spacing: 30) {
                Text("SETTINGS")
                    .font(.system(size: 36, weight: .bold))
                    .foregroundColor(Color(hex: "#FFFFFF"))

                // BGM Toggle
                HStack(spacing: 20) {
                    Text("MUSIC")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(Color(hex: "#FFFFFF"))
                        .frame(width: 120, alignment: .leading)

                    Button(action: {
                        bgmEnabled.toggle()
                        AudioManager.shared.setBGMEnabled(bgmEnabled)
                    }) {
                        Text(bgmEnabled ? "ON" : "OFF")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(bgmEnabled ? Color(hex: "#00FF99") : Color(hex: "#FF8800"))
                            .frame(width: 80)
                            .padding(.vertical, 12)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color(hex: "#0A1428").opacity(0.7))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(bgmEnabled ? Color(hex: "#00FF99") : Color(hex: "#FF8800"), lineWidth: 2)
                            )
                    }
                    .buttonStyle(.plain)
                }

                // SFX Toggle
                HStack(spacing: 20) {
                    Text("SOUNDS")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(Color(hex: "#FFFFFF"))
                        .frame(width: 120, alignment: .leading)

                    Button(action: {
                        sfxEnabled.toggle()
                        AudioManager.shared.setSFXEnabled(sfxEnabled)
                    }) {
                        Text(sfxEnabled ? "ON" : "OFF")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(sfxEnabled ? Color(hex: "#00FF99") : Color(hex: "#FF8800"))
                            .frame(width: 80)
                            .padding(.vertical, 12)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color(hex: "#0A1428").opacity(0.7))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(sfxEnabled ? Color(hex: "#00FF99") : Color(hex: "#FF8800"), lineWidth: 2)
                            )
                    }
                    .buttonStyle(.plain)
                }

                // Close button
                Button(action: { isPresented = false }) {
                    Text("CLOSE")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(Color(hex: "#FFFFFF"))
                        .padding(.horizontal, 40)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color(hex: "#0A1428").opacity(0.7))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color(hex: "#FFFFFF"), lineWidth: 2)
                        )
                }
                .buttonStyle(.plain)
            }
            .padding(40)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(hex: "#0A1428").opacity(0.95))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Color(hex: "#00D9FF"), lineWidth: 3)
                            .shadow(color: Color(hex: "#00D9FF").opacity(0.8), radius: 12, x: 0, y: 0)
                    )
            )
        }
    }
}

// MARK: - Game View (full game)
struct GameView: View {
    let onReturnToMenu: () -> Void
    @State private var gameScene: GameScene?

    var body: some View {
        ZStack {
            if let scene = gameScene {
                SpriteView(scene: scene)
                    .ignoresSafeArea()
            }
        }
        .onAppear {
            let s = GameScene(size: CGSize(width: 1024, height: 768))
            s.scaleMode = .resizeFill
            s.onReturnToMenu = { [onReturnToMenu] in
                // Return to menu via callback
                onReturnToMenu()
            }
            gameScene = s

            #if os(macOS)
            NSApp.mainWindow?.acceptsMouseMovedEvents = true
            #endif
        }
    }
}

#Preview {
    ContentView()
}
