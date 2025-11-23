//
//  BackgroundAnimationView.swift
//  typingmill.swift
//
//  Created by Oleksandr Koreniuk on 20.09.2025.
//

import SwiftUI

struct BackgroundAnimationView: View {
    let isEnabled: Bool
    let typingChar: Character?
    let typingSpeed: Double // characters per minute
    let difficulty: Int
    let correctKeystroke: Bool
    
    var body: some View {
        Group {
            if isEnabled {
                StarfieldWithShootingStarsView(
                    typingChar: typingChar,
                    typingSpeed: typingSpeed,
                    difficulty: difficulty,
                    correctKeystroke: correctKeystroke
                )
            }
        }
    }
}

// MARK: - Starfield with Shooting Stars Animation
struct StarfieldWithShootingStarsView: View {
    // TEMP: Set to true to trigger animation for demo
    static let animDemo = false
    static let animDemoInterval = 0.1

    let typingChar: Character?
    let typingSpeed: Double
    let difficulty: Int
    let correctKeystroke: Bool

    @State private var stars: [Star] = []
    @State private var shootingStars: [ShootingStar] = []
    @State private var demoTimer: Timer?
    
    private struct Star: Identifiable {
        let id = UUID()
        let x: Double
        let y: Double
        let size: Double
        let brightness: Double
        let twinklePhase: Double
    }
    
    private struct ShootingStar: Identifiable {
        let id = UUID()
        let startX: Double
        let startY: Double
        let speed: Double
        let length: Double
        let color: Color
        let creationTime: Date
    }
    
    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                let currentTime = timeline.date.timeIntervalSinceReferenceDate
                
                // Never mutate @State here; only draw based on existing state.
                
                // Draw blinking stars
                for star in stars {
                    let twinkle = sin(currentTime * 2 + star.twinklePhase) * 0.3 + 0.7
                    let starColor = Color.white.opacity(star.brightness * twinkle * 0.6)
                    
                    context.fill(
                        Path(ellipseIn: CGRect(
                            x: star.x - star.size/2,
                            y: star.y - star.size/2,
                            width: star.size,
                            height: star.size
                        )),
                        with: .color(starColor)
                    )
                }
                
                // Draw shooting stars (pointing downward)
                let currentShootingStars = shootingStars.compactMap { shootingStar -> (ShootingStar, Double, Double, Double)? in
                    let elapsed = currentTime - shootingStar.creationTime.timeIntervalSinceReferenceDate
                    let life = max(0, 1.0 - elapsed)
                    
                    if life <= 0 {
                        return nil
                    }
                    
                    let currentX = shootingStar.startX - shootingStar.speed * 0.5 * elapsed
                    let currentY = shootingStar.startY + shootingStar.speed * elapsed
                    
                    if currentY > 1000 {
                        return nil
                    }
                    
                    return (shootingStar, currentX, currentY, life)
                }
                
                for (shootingStar, currentX, currentY, life) in currentShootingStars {
                    let gradient = Gradient(colors: [
                        shootingStar.color.opacity(life),
                        shootingStar.color.opacity(life * 0.5),
                        .clear
                    ])
                    
                    let path = Path { path in
                        path.move(to: CGPoint(x: currentX, y: currentY))
                        path.addLine(to: CGPoint(
                            x: currentX + shootingStar.length * 0.5,
                            y: currentY - shootingStar.length
                        ))
                    }
                    
                    context.stroke(path, with: .linearGradient(
                        gradient,
                        startPoint: CGPoint(x: currentX, y: currentY),
                        endPoint: CGPoint(x: currentX + shootingStar.length * 0.5, y: currentY - shootingStar.length)
                    ), lineWidth: 2)
                }
            }
        }
        .onChange(of: correctKeystroke) { _, isCorrect in
            // Defer state mutations to the next runloop outside the view update phase
            if isCorrect {
                DispatchQueue.main.async {
                    createShootingStar(canvasSize: CGSize(width: 1200, height: 800))
                }
            }
        }
        .onChange(of: difficulty) { _, _ in
            DispatchQueue.main.async {
                generateStars(canvasSize: CGSize(width: 1200, height: 800))
            }
        }
        .onAppear {
            DispatchQueue.main.async {
                generateStars(canvasSize: CGSize(width: 1200, height: 800))
            }
            // Demo mode: trigger shooting stars at interval
            if Self.animDemo {
                demoTimer = Timer.scheduledTimer(withTimeInterval: Self.animDemoInterval, repeats: true) { _ in
                    createShootingStar(canvasSize: CGSize(width: 1200, height: 800))
                }
            }
        }
        .onDisappear {
            demoTimer?.invalidate()
            demoTimer = nil
        }
    }
    
    private func generateStars(canvasSize: CGSize) {
        let starCount = 30 + difficulty * 15
        stars = (0..<starCount).map { _ in
            Star(
                x: Double.random(in: 0...canvasSize.width),
                y: Double.random(in: 0...canvasSize.height),
                size: Double.random(in: 1...3),
                brightness: Double.random(in: 0.3...1.0),
                twinklePhase: Double.random(in: 0...2*Double.pi)
            )
        }
    }
    
    private func createShootingStar(canvasSize: CGSize) {
        // Create multiple shooting stars based on difficulty
        let starCount = 1 + difficulty
        
        for _ in 0..<starCount {
            let hue = Double.random(in: 0...1)
            let newShootingStar = ShootingStar(
                startX: Double.random(in: canvasSize.width * 0.2...canvasSize.width),
                startY: Double.random(in: 0...canvasSize.height * 0.4),
                speed: Double.random(in: 150...300),
                length: Double.random(in: 40...80),
                color: Color(hue: hue, saturation: 0.8, brightness: 1.0),
                creationTime: Date()
            )
            shootingStars.append(newShootingStar)
        }
        
        // Clean up old shooting stars
        let now = Date()
        shootingStars.removeAll { shootingStar in
            now.timeIntervalSince(shootingStar.creationTime) > 2.0
        }
        
        // Keep reasonable number of shooting stars
        if shootingStars.count > 20 {
            shootingStars.removeFirst(5)
        }
    }
}
