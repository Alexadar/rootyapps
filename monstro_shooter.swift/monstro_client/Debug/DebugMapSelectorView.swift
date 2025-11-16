import SwiftUI
import SpriteKit

/// Debug view: Game without main menu, just starts directly with map/weapon/exo selectors
struct DebugMapSelectorView: View {
    let onBack: () -> Void
    @State private var showGame = false
    @State private var showSettings = false
    @State private var bgmEnabled = SettingsManager.shared.bgmEnabled
    @State private var sfxEnabled = SettingsManager.shared.sfxEnabled
    @State private var allDropPoints: [DropPoint] = []
    @State private var selectedDropPointId: Int?
    @State private var availableMaps: [MapConfig] = []
    @State private var selectedMapIndex: Int = 0
    @State private var selectedWeaponId: Int = 1
    @State private var selectedExoskeletonId: Int = 1

    var body: some View {
        ZStack {
            // Video background layer
            MainMenuVideoLayer()

            if showGame {
                DebugGameView(onReturnToMenu: {
                    showGame = false
                    AudioManager.shared.fadeOut(duration: 0.3) {
                        AudioManager.shared.playMenuMusic()
                    }
                })
                .onAppear {
                    AudioManager.shared.fadeOut(duration: 0.3) {
                        AudioManager.shared.playFightMusic()
                    }
                }
            } else {
                VStack(spacing: 20) {
                    HStack {
                        DebugBackButton(action: onBack)
                        Spacer()
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 20)

                    Text("DEBUG: MAP SELECTOR")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(.white)

                    Spacer()

                    // Drop Point selector
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
                                loadMaps()
                            }
                        )
                        .padding(.bottom, 10)
                    }

                    // Map selector
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

                    // Weapon selector
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

                    // Exoskeleton selector
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

                    PrimaryButton(text: "START GAME", action: { showGame = true })

                    SecondaryButton(text: "SETTINGS", action: { showSettings.toggle() })

                    Spacer().frame(height: 60)
                }
                .onAppear {
                    loadMaps()
                    AudioManager.shared.playMenuMusic()
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
            return
        }

        let savedFilename = SettingsManager.shared.selectedMapFilename
        if let index = availableMaps.firstIndex(where: { "map_\(String(format: "%04d", $0.id))" == savedFilename }) {
            selectedMapIndex = index
        } else {
            selectedMapIndex = 0
        }

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

/// Simple game wrapper for debug mode
struct DebugGameView: View {
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
                onReturnToMenu()
            }
            gameScene = s

            #if os(macOS)
            NSApp.mainWindow?.acceptsMouseMovedEvents = true
            #endif
        }
    }
}
