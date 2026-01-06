import SwiftUI
import SpriteKit
#if os(macOS)
import AppKit
#else
import UIKit
#endif

// MARK: - Launch Mode
enum LaunchMode {
    case normal
    case debug
    case debugMapSelector
    case debugMonsters
    case debugPlayerTest

    static var current: LaunchMode {
        if CommandLine.arguments.contains("--debug") {
            return .debug
        } else if CommandLine.arguments.contains("--debug-map-selector") {
            return .debugMapSelector
        } else if CommandLine.arguments.contains("--debug-monsters") {
            return .debugMonsters
        } else if CommandLine.arguments.contains("--debug-player-test") {
            return .debugPlayerTest
        }
        return .normal
    }
}

// MARK: - View Type
enum ViewType {
    case mainMenu
    case game
    case debugMasterMenu
    case debugMapSelector
    case debugMonsters
    case debugPlayerTest
}

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
    @State private var currentView: ViewType

    init() {
        switch LaunchMode.current {
        case .debug:
            _currentView = State(initialValue: .debugMasterMenu)
        case .debugMapSelector:
            _currentView = State(initialValue: .debugMapSelector)
        case .debugMonsters:
            _currentView = State(initialValue: .debugMonsters)
        case .debugPlayerTest:
            _currentView = State(initialValue: .debugPlayerTest)
        default:
            _currentView = State(initialValue: .mainMenu)
        }
    }

    var body: some View {
        switch currentView {
        case .mainMenu:
            AnimatedMainMenuView(onPlayTapped: {
                AudioManager.shared.fadeOut(duration: 0.3) {
                    currentView = .game
                }
            })
            .onAppear {
                AudioManager.shared.playMenuMusic()
            }

        case .game:
            GameView(onReturnToMenu: {
                AudioManager.shared.fadeOut(duration: 0.3) {
                    currentView = .mainMenu
                    AudioManager.shared.playMenuMusic()
                }
            })
            .onAppear {
                AudioManager.shared.fadeOut(duration: 0.3) {
                    AudioManager.shared.playFightMusic()
                }
            }

        case .debugMasterMenu:
            DebugMasterMenuView(selectedDebugView: Binding(
                get: { nil },
                set: { newView in
                    if let debugView = newView {
                        switch debugView {
                        case .mapSelector:
                            currentView = .debugMapSelector
                        case .monsters:
                            currentView = .debugMonsters
                        case .playerTest:
                            currentView = .debugPlayerTest
                        }
                    }
                }
            ))

        case .debugMapSelector:
            DebugMapSelectorView(onBack: { currentView = .debugMasterMenu })

        case .debugMonsters:
            DebugMonstersView(onBack: { currentView = .debugMasterMenu })

        case .debugPlayerTest:
            DebugPlayerTestView(onBack: { currentView = .debugMasterMenu })
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
                // Video background layer (CSS cover style)
                MainMenuVideoLayer()

                // Overlay UI (Selectors, Play and Settings buttons)
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
    @State private var selectedFPS: Int = SettingsManager.shared.targetFPS

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

                // FPS Selector
                HStack(spacing: 20) {
                    Text("FPS")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(Color(hex: "#FFFFFF"))
                        .frame(width: 120, alignment: .leading)

                    HStack(spacing: 8) {
                        ForEach(SettingsManager.fpsOptions, id: \.self) { fps in
                            Button(action: {
                                selectedFPS = fps
                                SettingsManager.shared.targetFPS = fps
                            }) {
                                Text("\(fps)")
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundColor(selectedFPS == fps ? Color(hex: "#00FF99") : Color(hex: "#FFFFFF"))
                                    .frame(width: 50)
                                    .padding(.vertical, 12)
                                    .background(
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(Color(hex: "#0A1428").opacity(0.7))
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(selectedFPS == fps ? Color(hex: "#00FF99") : Color(hex: "#555555"), lineWidth: 2)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
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
                SpriteView(
                    scene: scene,
                    preferredFramesPerSecond: SettingsManager.shared.targetFPS,
                    options: [.ignoresSiblingOrder, .shouldCullNonVisibleNodes]
                )
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
