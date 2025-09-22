import SwiftUI

struct MenuView: View {
    @EnvironmentObject var gameEngine: GameEngine
    @State private var animatePig = false
    @State private var showSettings = false

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color.green.opacity(0.3), Color.blue.opacity(0.3)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 40) {
                VStack(spacing: 20) {
                    Text("🐷")
                        .font(.system(size: 100))
                        .scaleEffect(animatePig ? 1.1 : 1.0)
                        .animation(
                            .easeInOut(duration: 1.5).repeatForever(autoreverses: true),
                            value: animatePig
                        )

                    Text("Pig Maze Adventure")
                        .font(.system(size: 42, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 2)

                    HStack(spacing: 10) {
                        ForEach(["💎", "💰", "🏆", "🌟", "🍎"], id: \.self) { emoji in
                            Text(emoji)
                                .font(.system(size: 30))
                        }
                    }
                }
                .padding(.top, 50)

                VStack(spacing: 20) {
                    Button(action: {
                        gameEngine.startGame()
                    }) {
                        HStack {
                            Image(systemName: "play.fill")
                                .font(.system(size: 24))
                            Text("Play")
                                .font(.system(size: 28, weight: .bold, design: .rounded))
                        }
                        .frame(width: 250, height: 60)
                        .background(
                            LinearGradient(
                                colors: [Color.green, Color.green.opacity(0.7)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .foregroundColor(.white)
                        .cornerRadius(20)
                        .shadow(color: .green.opacity(0.3), radius: 5, x: 0, y: 3)
                    }
                    .buttonStyle(PressedButtonStyle())

                    Button(action: {
                        showSettings = true
                    }) {
                        HStack {
                            Image(systemName: "gearshape.fill")
                                .font(.system(size: 22))
                            Text("Settings")
                                .font(.system(size: 24, weight: .semibold, design: .rounded))
                        }
                        .frame(width: 200, height: 50)
                        .background(
                            LinearGradient(
                                colors: [Color.blue, Color.blue.opacity(0.7)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .foregroundColor(.white)
                        .cornerRadius(15)
                        .shadow(color: .blue.opacity(0.3), radius: 5, x: 0, y: 3)
                    }
                    .buttonStyle(PressedButtonStyle())

                    Button(action: {
                        // High scores placeholder
                    }) {
                        HStack {
                            Image(systemName: "trophy.fill")
                                .font(.system(size: 22))
                            Text("High Scores")
                                .font(.system(size: 24, weight: .semibold, design: .rounded))
                        }
                        .frame(width: 200, height: 50)
                        .background(
                            LinearGradient(
                                colors: [Color.yellow, Color.orange],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .foregroundColor(.white)
                        .cornerRadius(15)
                        .shadow(color: .orange.opacity(0.3), radius: 5, x: 0, y: 3)
                    }
                    .buttonStyle(PressedButtonStyle())
                }

                Spacer()

                HStack(spacing: 15) {
                    ForEach(["👻", "🦇", "🕷️", "🐍", "🔥"], id: \.self) { enemy in
                        Text(enemy)
                            .font(.system(size: 25))
                            .opacity(0.7)
                    }
                }
                .padding(.bottom, 30)
            }
        }
        .onAppear {
            animatePig = true
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject var gameEngine: GameEngine
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationView {
            Form {
                Section("Game Settings") {
                    Picker("Difficulty", selection: $gameEngine.difficulty) {
                        Text("Easy").tag(Difficulty.easy)
                        Text("Medium").tag(Difficulty.medium)
                        Text("Hard").tag(Difficulty.hard)
                    }
                    .pickerStyle(SegmentedPickerStyle())

                    Toggle("Sound Effects", isOn: $gameEngine.soundEnabled)
                    Toggle("Haptic Feedback", isOn: $gameEngine.hapticEnabled)
                }

                Section("Controls") {
                    Picker("Control Type", selection: $gameEngine.controlType) {
                        Text("Swipe").tag(ControlType.swipe)
                        Text("D-Pad").tag(ControlType.dpad)
                        #if os(macOS)
                        Text("Keyboard").tag(ControlType.keyboard)
                        #endif
                    }
                    .pickerStyle(SegmentedPickerStyle())
                }
            }
            .navigationTitle("Settings")
#if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

struct PressedButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

#Preview {
    MenuView()
        .environmentObject(GameEngine())
}
