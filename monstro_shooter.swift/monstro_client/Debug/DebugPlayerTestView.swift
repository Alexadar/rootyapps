import SwiftUI
import SpriteKit

/// Debug view: Test player weapons/exoskeletons in actual gameplay
struct DebugPlayerTestView: View {
    let onBack: () -> Void
    @State private var gameScene: GameScene?
    @State private var currentWeaponId: Int = SettingsManager.shared.selectedWeaponId
    @State private var currentExoId: Int = SettingsManager.shared.selectedExoskeletonId

    var body: some View {
        ZStack {
            // Actual game scene
            if let scene = gameScene {
                SpriteView(scene: scene)
                    .ignoresSafeArea()
            }

            // Debug control overlay
            VStack {
                HStack {
                    DebugBackButton(action: onBack)
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)

                Spacer()

                HStack(spacing: 15) {
                    // Weapon buttons
                    VStack(alignment: .leading, spacing: 8) {
                        Text("WEAPONS")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.white.opacity(0.7))

                        ForEach(WeaponManager.shared.getAllWeapons()) { weapon in
                            Button(action: {
                                currentWeaponId = weapon.id
                                switchWeapon(weapon)
                            }) {
                                Text(weapon.getLocalizedName())
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(.white)
                                    .frame(width: 100, height: 28)
                                    .background(currentWeaponId == weapon.id ? Color.green.opacity(0.8) : Color.black.opacity(0.5))
                                    .cornerRadius(4)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 4)
                                            .stroke(currentWeaponId == weapon.id ? Color.green : Color.white.opacity(0.3), lineWidth: 1)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    Spacer()

                    // Exoskeleton buttons
                    VStack(alignment: .trailing, spacing: 8) {
                        Text("EXOSKELETONS")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.white.opacity(0.7))

                        ForEach(ExoskeletonManager.shared.getAllExoskeletons()) { exo in
                            Button(action: {
                                currentExoId = exo.id
                                switchExoskeleton(exo)
                            }) {
                                Text(exo.getLocalizedName())
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(.white)
                                    .frame(width: 120, height: 28)
                                    .background(currentExoId == exo.id ? Color.blue.opacity(0.8) : Color.black.opacity(0.5))
                                    .cornerRadius(4)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 4)
                                            .stroke(currentExoId == exo.id ? Color.blue : Color.white.opacity(0.3), lineWidth: 1)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
        }
        .onAppear {
            let scene = GameScene(size: CGSize(width: 1024, height: 768))
            scene.scaleMode = .resizeFill
            scene.onReturnToMenu = onBack
            gameScene = scene

            #if os(macOS)
            NSApp.mainWindow?.acceptsMouseMovedEvents = true
            #endif
        }
    }

    private func switchWeapon(_ config: WeaponConfig) {
        guard let player = gameScene?.playerEntity else { return }
        player.currentWeapon = Weapon(config: config)
    }

    private func switchExoskeleton(_ exo: ExoskeletonConfig) {
        guard let player = gameScene?.playerEntity else { return }
        player.applyExoskeleton(exo)
    }
}
