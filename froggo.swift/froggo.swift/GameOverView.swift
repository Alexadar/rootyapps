//
//  GameOverView.swift
//  froggo.swift
//
//  Created by Oleksandr Koreniuk on 19.09.2025.
//

import SwiftUI
import SpriteKit

struct GameOverView: View {
    @Binding var gameState: GameState
    let score: Int
    @State private var highScore: Int = UserDefaults.standard.integer(forKey: "highScore")
    @State private var isNewHighScore: Bool = false

    var body: some View {
        ZStack {
            // Background scene with skyscrapers and frog
            SpriteView(scene: createGameOverScene())
                .ignoresSafeArea()

            VStack(spacing: 30) {
                Spacer()
                    .frame(height: 50)

                // Game Over Title - bright green like Unity
                Text("Game Over")
                    .font(.system(size: 56, weight: .bold, design: .monospaced))
                    .foregroundColor(Color(red: 0.4, green: 1.0, blue: 0.2)) // Bright green
                    .shadow(color: .black.opacity(0.5), radius: 3, x: 2, y: 2)

                Spacer()

                VStack(spacing: 15) {
                    // Try Again Button - green squared style
                    Button(action: {
                        SoundManager.shared.playSound("button_clicked")
                        gameState = .playing
                    }) {
                        Text("Try again")
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

                    // To Menu Button - white/gray squared style
                    Button(action: {
                        SoundManager.shared.playSound("button_clicked")
                        gameState = .menu
                    }) {
                        Text("To Menu")
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
            checkHighScore()
        }
    }

    private func checkHighScore() {
        highScore = UserDefaults.standard.integer(forKey: "highScore")
        if score > highScore {
            isNewHighScore = true
            UserDefaults.standard.set(score, forKey: "highScore")
            highScore = score
        }
    }

    private func createGameOverScene() -> GameOverScene {
        let scene = GameOverScene()
        scene.size = CGSize(width: 800, height: 600)
        scene.scaleMode = .aspectFill
        return scene
    }
}

// Game Over scene with skyscrapers and frog prop
class GameOverScene: SKScene {
    override func didMove(to view: SKView) {
        setupGameOverScene()
    }

    private func setupGameOverScene() {
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

        // Add skyscrapers (2 buildings for game over screen) - solid blocks
        let scraperTexture = SKTexture(imageNamed: "scraper")
        let scraperPositions: [(x: CGFloat, width: CGFloat, height: CGFloat)] = [
            (250, 110, 320),
            (550, 100, 280)
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

        // Add frog on left building
        let frogTexture = SKTexture(imageNamed: "idle_frog")
        let frog = SKSpriteNode(texture: frogTexture)
        frog.size = CGSize(width: 40, height: 40)
        frog.position = CGPoint(x: 250, y: 320 + 20) // On top of left building
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
