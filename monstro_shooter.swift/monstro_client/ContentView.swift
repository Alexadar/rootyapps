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
    @State private var allDropPoints: [DropPoint] = []
    @State private var selectedDropPointId: Int?
    @State private var availableMaps: [MapConfig] = []
    @State private var selectedMapIndex: Int = 0
    @State private var selectedWeaponId: Int = 1 // Default to pistol
    @State private var selectedExoskeletonId: Int = 1 // Default to standard suit

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

                    // Drop Point dropdown selector
                    if !allDropPoints.isEmpty {
                        DropdownSelector(
                            title: "Select Drop Point",
                            items: allDropPoints,
                            selectedItem: allDropPoints.first(where: { $0.id == selectedDropPointId }),
                            displayText: { dropPoint in
                                if let index = allDropPoints.firstIndex(where: { $0.id == dropPoint.id }) {
                                    return "\(index + 1). \(dropPoint.name)"
                                }
                                return dropPoint.name
                            },
                            onSelect: { dropPoint in
                                selectedDropPointId = dropPoint.id
                                saveSelectedDropPoint()
                                loadMaps() // Reload maps based on new drop point
                            }
                        )
                        .padding(.bottom, 10)
                    }

                    // Map dropdown selector
                    if !availableMaps.isEmpty {
                        DropdownSelector(
                            title: "Select Map",
                            items: availableMaps,
                            selectedItem: availableMaps[selectedMapIndex],
                            displayText: { map in
                                if let index = availableMaps.firstIndex(where: { $0.id == map.id }) {
                                    return "\(index + 1). \(map.getLocalizedName())"
                                }
                                return map.getLocalizedName()
                            },
                            onSelect: { map in
                                if let index = availableMaps.firstIndex(where: { $0.id == map.id }) {
                                    selectedMapIndex = index
                                    saveSelectedMap()
                                }
                            }
                        )
                        .padding(.bottom, 10)
                    }

                    // Weapon dropdown selector
                    DropdownSelector(
                        title: "Select Weapon",
                        items: getAvailableWeapons(),
                        selectedItem: getAvailableWeapons().first(where: { $0.id == selectedWeaponId }),
                        displayText: { $0.getLocalizedName() },
                        onSelect: { weapon in
                            selectedWeaponId = weapon.id
                            saveSelectedWeapon()
                        }
                    )
                    .padding(.bottom, 10)

                    // Exoskeleton dropdown selector
                    DropdownSelector(
                        title: "Select Exoskeleton",
                        items: getAvailableExoskeletons(),
                        selectedItem: getAvailableExoskeletons().first(where: { $0.id == selectedExoskeletonId }),
                        displayText: { exo in
                            "\(exo.getLocalizedName()) (⚔️\(Int(exo.defence)) 🏃\(String(format: "%.0f%%", exo.speed * 100)))"
                        },
                        onSelect: { exoskeleton in
                            selectedExoskeletonId = exoskeleton.id
                            saveSelectedExoskeleton()
                        }
                    )
                    .padding(.bottom, 10)

                    PrimaryButton(text: "PLAY", action: onPlayTapped)

                    SecondaryButton(text: "SETTINGS", action: { showSettings.toggle() })

                    Spacer().frame(height: 60)
                }
                .onAppear {
                    loadMaps()
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

    private func loadMaps() {
        allDropPoints = DropPointLoader.loadAllDropPoints()
        selectedDropPointId = SettingsManager.shared.selectedDropPointId

        availableMaps = DropPointLoader.getMaps(forDropPointId: selectedDropPointId)

        if availableMaps.isEmpty {
            print("[AnimatedMainMenuView] No maps loaded for selected drop point!")
            return
        }

        // Find saved map or default to first
        let savedFilename = SettingsManager.shared.selectedMapFilename
        if let index = availableMaps.firstIndex(where: { "map_\(String(format: "%04d", $0.id))" == savedFilename }) {
            selectedMapIndex = index
        } else {
            selectedMapIndex = 0
        }

        // Load selected weapon and exoskeleton
        selectedWeaponId = SettingsManager.shared.selectedWeaponId
        selectedExoskeletonId = SettingsManager.shared.selectedExoskeletonId
    }

    private func saveSelectedMap() {
        guard !availableMaps.isEmpty else { return }
        let filename = "map_\(String(format: "%04d", availableMaps[selectedMapIndex].id))"
        SettingsManager.shared.selectedMapFilename = filename
    }

    private func saveSelectedDropPoint() {
        SettingsManager.shared.selectedDropPointId = selectedDropPointId
    }

    private func saveSelectedWeapon() {
        SettingsManager.shared.selectedWeaponId = selectedWeaponId
    }

    private func saveSelectedExoskeleton() {
        SettingsManager.shared.selectedExoskeletonId = selectedExoskeletonId
    }

    private func getAvailableWeapons() -> [WeaponConfig] {
        return WeaponManager.shared.getAllWeapons()
    }

    private func getAvailableExoskeletons() -> [ExoskeletonConfig] {
        return ExoskeletonManager.shared.getAllExoskeletons()
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
