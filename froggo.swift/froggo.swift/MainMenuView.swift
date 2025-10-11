//
//  MainMenuView.swift
//  froggo.swift
//
//  Created by Oleksandr Koreniuk on 19.09.2025.
//

import SwiftUI
import SpriteKit

struct MainMenuView: View {
    @State private var isMuted = UserDefaults.standard.bool(forKey: "mute")
    @Binding var gameState: GameState

    var body: some View {
        ZStack {
            // Background scene with skyscrapers and frog
            SpriteView(scene: createMenuScene())
                .ignoresSafeArea()

            VStack(spacing: 40) {
                Spacer()
                    .frame(height: 50)

                // Game Title - "Skyscraper Frog" in bright green like Unity
                Text("Skyscraper Frog")
                    .font(.system(size: 48, weight: .bold, design: .monospaced))
                    .foregroundColor(Color(red: 0.4, green: 1.0, blue: 0.2)) // Bright green
                    .shadow(color: .black.opacity(0.5), radius: 3, x: 2, y: 2)

                Spacer()

                VStack(spacing: 15) {
                    // Start Button - green squared style
                    Button(action: {
                        SoundManager.shared.playSound("button_clicked")
                        gameState = .playing
                    }) {
                        Text("Start")
                            .font(.system(size: 24, weight: .bold, design: .monospaced))
                            .foregroundColor(.white)
                            .frame(width: 180, height: 50)
                            .background(
                                Rectangle()
                                    .fill(Color(red: 0.2, green: 0.8, blue: 0.2))
                                    .cornerRadius(3)
                            )
                            .overlay(
                                Rectangle()
                                    .stroke(Color.black.opacity(0.3), lineWidth: 2)
                                    .cornerRadius(3)
                            )
                    }
                    .buttonStyle(SquaredButtonStyle())

                    // Mute/Unmute Button - white/gray squared style
                    Button(action: {
                        SoundManager.shared.playSound("button_clicked")
                        isMuted.toggle()
                        UserDefaults.standard.set(isMuted, forKey: "mute")
                        SoundManager.shared.isMuted = isMuted
                    }) {
                        Text(isMuted ? "Unmute" : "Mute")
                            .font(.system(size: 24, weight: .bold, design: .monospaced))
                            .foregroundColor(.black)
                            .frame(width: 180, height: 50)
                            .background(
                                Rectangle()
                                    .fill(Color.white)
                                    .cornerRadius(3)
                            )
                            .overlay(
                                Rectangle()
                                    .stroke(Color.black.opacity(0.3), lineWidth: 2)
                                    .cornerRadius(3)
                            )
                    }
                    .buttonStyle(SquaredButtonStyle())
                }

                Spacer()
                    .frame(height: 80)
            }
            .padding()
        }
        .onAppear {
            isMuted = UserDefaults.standard.bool(forKey: "mute")
            SoundManager.shared.isMuted = isMuted
        }
    }

    private func createMenuScene() -> MenuScene {
        let scene = MenuScene()
        scene.size = CGSize(width: 800, height: 600)
        scene.scaleMode = .aspectFill
        return scene
    }
}

// Custom button style for squared game buttons
struct SquaredButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .brightness(configuration.isPressed ? -0.1 : 0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

enum GameState {
    case menu
    case playing
    case gameOver
}

// Menu scene with skyscrapers and frog prop
class MenuScene: SKScene {
    override func didMove(to view: SKView) {
        setupMenuScene()
    }

    private func setupMenuScene() {
        backgroundColor = SKColor(red: 0.0, green: 0.2, blue: 0.4, alpha: 1.0) // Dark blue

        // Add background
        let bgTexture = SKTexture(imageNamed: "NightSky")
        if bgTexture.size() != .zero {
            let bg = SKSpriteNode(texture: bgTexture)
            let scale = size.height / bgTexture.size().height
            bg.setScale(scale * 1.2)
            bg.position = CGPoint(x: size.width / 2, y: size.height / 2)
            bg.zPosition = -10
            addChild(bg)
        }

        // Add skyscrapers (3 buildings) - solid like original
        let scraperTexture = SKTexture(imageNamed: "scraper")
        let scraperPositions: [(x: CGFloat, width: CGFloat, height: CGFloat)] = [
            (200, 80, 300),
            (450, 100, 250),
            (650, 90, 280)
        ]

        for (i, pos) in scraperPositions.enumerated() {
            let scraper = SKSpriteNode(texture: scraperTexture)
            scraper.size = CGSize(width: pos.width, height: pos.height)
            scraper.position = CGPoint(x: pos.x, y: pos.height / 2)
            scraper.zPosition = CGFloat(i)

            // Apply tiling shader
            let shader = createTilingShader(width: pos.width, height: pos.height, texture: scraperTexture)
            scraper.shader = shader

            addChild(scraper)
        }

        // Add frog on middle building
        let frogTexture = SKTexture(imageNamed: "idle_frog")
        let frog = SKSpriteNode(texture: frogTexture)
        frog.size = CGSize(width: 40, height: 40)
        frog.position = CGPoint(x: 450, y: 250 + 20) // On top of middle building
        frog.zPosition = 10
        addChild(frog)
    }

    private func createTilingShader(width: CGFloat, height: CGFloat, texture: SKTexture) -> SKShader {
        let source = """
        void main() {
            vec2 uv = v_tex_coord * u_textureScale;
            uv = fract(uv);
            gl_FragColor = texture2D(u_texture, uv) * v_color_mix;
        }
        """
        let shader = SKShader(source: source)
        let scaleX = Float((width / texture.size().width) * 6.0)
        let scaleY = Float((height / texture.size().height) * 6.0)
        let uniform = SKUniform(name: "u_textureScale", vectorFloat2: vector_float2(scaleX, scaleY))
        shader.uniforms = [uniform]
        return shader
    }
}
