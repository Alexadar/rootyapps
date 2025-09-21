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
    
    var body: some View {
        Group {
            if isEnabled {
                StarfieldView(
                    typingChar: typingChar,
                    typingSpeed: typingSpeed,
                    difficulty: difficulty
                )
            }
        }
    }
}

// MARK: - Flowing Particles Animation
struct FlowingParticlesView: View {
    let typingChar: Character?
    let typingSpeed: Double
    let difficulty: Int
    
    @State private var particles: [Particle] = []
    @State private var animationTime: Double = 0
    
    private struct Particle: Identifiable {
        let id = UUID()
        var x: Double
        var y: Double
        var size: Double
        var speed: Double
        var hue: Double
        var opacity: Double
        var phase: Double
    }
    
    var body: some View {
        Canvas { context, size in
            let time = animationTime
            
            for particle in particles {
                let waveOffset = sin(time * 0.5 + particle.phase) * 30
                let currentX = particle.x + waveOffset
                let currentY = particle.y - particle.speed * time
                
                // Wrap around screen
                let wrappedY = currentY.truncatingRemainder(dividingBy: size.height + 100) - 50
                
                let color = Color(hue: particle.hue, saturation: 0.7, brightness: 0.8)
                    .opacity(particle.opacity * 0.6)
                
                context.fill(
                    Path(ellipseIn: CGRect(
                        x: currentX - particle.size/2,
                        y: wrappedY - particle.size/2,
                        width: particle.size,
                        height: particle.size
                    )),
                    with: .color(color)
                )
            }
        }
        .onAppear {
            generateParticles()
            startAnimation()
        }
        .onChange(of: typingChar) { _, _ in
            addTypingParticle()
        }
        .onChange(of: difficulty) { _, _ in
            generateParticles()
        }
    }
    
    private func generateParticles() {
        let particleCount = 20 + difficulty * 10
        particles = (0..<particleCount).map { _ in
            Particle(
                x: Double.random(in: 0...400),
                y: Double.random(in: 0...800),
                size: Double.random(in: 2...8),
                speed: Double.random(in: 10...30),
                hue: Double.random(in: 0...1),
                opacity: Double.random(in: 0.3...0.8),
                phase: Double.random(in: 0...2*Double.pi)
            )
        }
    }
    
    private func addTypingParticle() {
        let speedHue = min(typingSpeed / 100, 1.0) // Blue to red based on speed
        let newParticle = Particle(
            x: Double.random(in: 0...400),
            y: 0,
            size: Double.random(in: 4...12),
            speed: 20 + typingSpeed / 10,
            hue: speedHue * 0.7, // Blue to orange range
            opacity: 0.9,
            phase: 0
        )
        particles.append(newParticle)
        
        // Keep particle count reasonable
        if particles.count > 100 {
            particles.removeFirst(10)
        }
    }
    
    private func startAnimation() {
        Timer.scheduledTimer(withTimeInterval: 1/60, repeats: true) { _ in
            animationTime += 1/60
        }
    }
}

// MARK: - Neural Network Animation
struct NeuralNetworkView: View {
    let typingChar: Character?
    let typingSpeed: Double
    let difficulty: Int
    
    @State private var nodes: [NetworkNode] = []
    @State private var connections: [Connection] = []
    @State private var pulses: [Pulse] = []
    @State private var animationTime: Double = 0
    
    private struct NetworkNode: Identifiable {
        let id = UUID()
        let x: Double
        let y: Double
        var activation: Double = 0
    }
    
    private struct Connection: Identifiable {
        let id = UUID()
        let from: UUID
        let to: UUID
        var strength: Double
    }
    
    private struct Pulse: Identifiable {
        let id = UUID()
        let connectionId: UUID
        var progress: Double = 0
        let color: Color
    }
    
    var body: some View {
        Canvas { context, size in
            // Draw connections
            for connection in connections {
                if let fromNode = nodes.first(where: { $0.id == connection.from }),
                   let toNode = nodes.first(where: { $0.id == connection.to }) {
                    
                    let path = Path { path in
                        path.move(to: CGPoint(x: fromNode.x, y: fromNode.y))
                        path.addLine(to: CGPoint(x: toNode.x, y: toNode.y))
                    }
                    
                    context.stroke(
                        path,
                        with: .color(.white.opacity(connection.strength * 0.3)),
                        lineWidth: 1
                    )
                }
            }
            
            // Draw pulses
            for pulse in pulses {
                if let connection = connections.first(where: { $0.id == pulse.connectionId }),
                   let fromNode = nodes.first(where: { $0.id == connection.from }),
                   let toNode = nodes.first(where: { $0.id == connection.to }) {
                    
                    let currentX = fromNode.x + (toNode.x - fromNode.x) * pulse.progress
                    let currentY = fromNode.y + (toNode.y - fromNode.y) * pulse.progress
                    
                    context.fill(
                        Path(ellipseIn: CGRect(x: currentX - 3, y: currentY - 3, width: 6, height: 6)),
                        with: .color(pulse.color.opacity(1 - pulse.progress))
                    )
                }
            }
            
            // Draw nodes
            for node in nodes {
                let nodeColor = Color.white.opacity(0.4 + node.activation * 0.6)
                let nodeSize = 4.0 + node.activation * 4
                
                context.fill(
                    Path(ellipseIn: CGRect(
                        x: node.x - nodeSize/2,
                        y: node.y - nodeSize/2,
                        width: nodeSize,
                        height: nodeSize
                    )),
                    with: .color(nodeColor)
                )
            }
        }
        .onAppear {
            generateNetwork()
            startAnimation()
        }
        .onChange(of: typingChar) { _, _ in
            triggerPulse()
        }
        .onChange(of: difficulty) { _, _ in
            generateNetwork()
        }
    }
    
    private func generateNetwork() {
        let nodeCount = 15 + difficulty * 5
        nodes = (0..<nodeCount).map { _ in
            NetworkNode(
                x: Double.random(in: 50...350),
                y: Double.random(in: 50...550)
            )
        }
        
        // Create connections
        connections = []
        for node in nodes {
            let nearbyNodes = nodes.filter { other in
                let distance = sqrt(pow(node.x - other.x, 2) + pow(node.y - other.y, 2))
                return distance < 100 && other.id != node.id
            }
            
            for nearbyNode in nearbyNodes.prefix(3) {
                connections.append(Connection(
                    from: node.id,
                    to: nearbyNode.id,
                    strength: Double.random(in: 0.3...1.0)
                ))
            }
        }
    }
    
    private func triggerPulse() {
        guard !connections.isEmpty else { return }
        
        let randomConnection = connections.randomElement()!
        let pulseColor = Color(hue: Double.random(in: 0...1), saturation: 0.8, brightness: 1.0)
        
        pulses.append(Pulse(
            connectionId: randomConnection.id,
            color: pulseColor
        ))
        
        // Activate source node
        if let nodeIndex = nodes.firstIndex(where: { $0.id == randomConnection.from }) {
            nodes[nodeIndex].activation = 1.0
        }
    }
    
    private func startAnimation() {
        Timer.scheduledTimer(withTimeInterval: 1/60, repeats: true) { _ in
            animationTime += 1/60
            
            // Update pulses
            pulses = pulses.compactMap { pulse in
                var updatedPulse = pulse
                updatedPulse.progress += 0.02
                return updatedPulse.progress < 1.0 ? updatedPulse : nil
            }
            
            // Decay node activation
            for i in nodes.indices {
                nodes[i].activation *= 0.95
            }
        }
    }
}

// MARK: - Starfield Animation
struct StarfieldView: View {
    let typingChar: Character?
    let typingSpeed: Double
    let difficulty: Int
    
    @State private var stars: [Star] = []
    @State private var shootingStars: [ShootingStar] = []
    @State private var animationTime: Double = 0
    
    private struct Star: Identifiable {
        let id = UUID()
        let x: Double
        let y: Double
        let size: Double
        let brightness: Double
        let twinklePhase: Double
        let speed: Double
    }
    
    private struct ShootingStar: Identifiable {
        let id = UUID()
        var x: Double
        var y: Double
        let speed: Double
        let length: Double
        var life: Double = 1.0
    }
    
    var body: some View {
        Canvas { context, size in
            let time = animationTime
            
            // Always ensure we have stars
            if stars.isEmpty || stars.count < (30 + difficulty * 20) {
                generateStars(canvasSize: size)
            }
            
            // Draw stars
            for star in stars {
                let twinkle = sin(time * 2 + star.twinklePhase) * 0.3 + 0.7
                let currentX = star.x - star.speed * time * 10
                let wrappedX = currentX.truncatingRemainder(dividingBy: size.width + 100) - 50
                
                let starColor = Color.white.opacity(star.brightness * twinkle * 0.8)
                
                context.fill(
                    Path(ellipseIn: CGRect(
                        x: wrappedX - star.size/2,
                        y: star.y - star.size/2,
                        width: star.size,
                        height: star.size
                    )),
                    with: .color(starColor)
                )
            }
            
            // Draw shooting stars (pointing downward)
            for shootingStar in shootingStars {
                let gradient = Gradient(colors: [
                    .white.opacity(shootingStar.life),
                    .blue.opacity(shootingStar.life * 0.5),
                    .clear
                ])
                
                let path = Path { path in
                    path.move(to: CGPoint(x: shootingStar.x, y: shootingStar.y))
                    path.addLine(to: CGPoint(
                        x: shootingStar.x + shootingStar.length * 0.5,
                        y: shootingStar.y - shootingStar.length
                    ))
                }
                
                context.stroke(path, with: .linearGradient(
                    gradient,
                    startPoint: CGPoint(x: shootingStar.x, y: shootingStar.y),
                    endPoint: CGPoint(x: shootingStar.x + shootingStar.length * 0.5, y: shootingStar.y - shootingStar.length)
                ), lineWidth: 2)
            }
        }
        .onAppear {
            generateStars(canvasSize: CGSize(width: 1200, height: 800)) // Initial generation
            startAnimation()
        }
        .onChange(of: typingChar) { _, newChar in
            if newChar != nil && Bool.random() { // 50% chance to create shooting star on keypress
                createShootingStar(canvasSize: CGSize(width: 1200, height: 800))
            }
        }
        .onChange(of: difficulty) { _, _ in
            DispatchQueue.main.async {
                generateStars(canvasSize: CGSize(width: 1200, height: 800))
            }
        }
    }
    
    private func generateStars(canvasSize: CGSize) {
        let starCount = 30 + difficulty * 20
        stars = (0..<starCount).map { _ in
            Star(
                x: Double.random(in: 0...canvasSize.width),
                y: Double.random(in: 0...canvasSize.height),
                size: Double.random(in: 1...4),
                brightness: Double.random(in: 0.3...1.0),
                twinklePhase: Double.random(in: 0...2*Double.pi),
                speed: Double.random(in: 0.1...0.5)
            )
        }
    }
    
    private func createShootingStar(canvasSize: CGSize) {
        let newShootingStar = ShootingStar(
            x: Double.random(in: canvasSize.width * 0.75...canvasSize.width),
            y: Double.random(in: 0...canvasSize.height * 0.33),
            speed: Double.random(in: 100...200),
            length: Double.random(in: 30...60)
        )
        shootingStars.append(newShootingStar)
    }
    
    private func startAnimation() {
        Timer.scheduledTimer(withTimeInterval: 1/60, repeats: true) { _ in
            animationTime += 1/60
            
            // Update shooting stars (moving downward and to the left)
            for i in shootingStars.indices.reversed() {
                shootingStars[i].x -= shootingStars[i].speed * 0.5 * (1/60)
                shootingStars[i].y += shootingStars[i].speed * (1/60)
                shootingStars[i].life -= 1/60
                
                if shootingStars[i].life <= 0 || shootingStars[i].y > 1000 {
                    shootingStars.remove(at: i)
                }
            }
        }
    }
}

// MARK: - Audio Waves Animation
struct AudioWavesView: View {
    let typingChar: Character?
    let typingSpeed: Double
    let difficulty: Int
    
    @State private var animationTime: Double = 0
    @State private var waveAmplitude: Double = 20
    @State private var lastTypingTime: Date = Date()
    
    var body: some View {
        Canvas { context, size in
            let time = animationTime
            let centerY = size.height / 2
            let waveCount = 3 + difficulty
            
            for waveIndex in 0..<waveCount {
                let waveOffset = Double(waveIndex) * 0.5
                let frequency = 0.01 + Double(waveIndex) * 0.005
                let amplitude = waveAmplitude * (1.0 - Double(waveIndex) * 0.2)
                
                let path = Path { path in
                    let points = Int(size.width / 2)
                    for i in 0..<points {
                        let x = Double(i) * 2
                        let wave1 = sin(x * frequency + time * 2 + waveOffset) * amplitude
                        let wave2 = sin(x * frequency * 1.5 + time * 1.5 + waveOffset) * amplitude * 0.5
                        let y = centerY + wave1 + wave2
                        
                        if i == 0 {
                            path.move(to: CGPoint(x: x, y: y))
                        } else {
                            path.addLine(to: CGPoint(x: x, y: y))
                        }
                    }
                }
                
                let hue = (Double(waveIndex) / Double(waveCount) + time * 0.1).truncatingRemainder(dividingBy: 1.0)
                let waveColor = Color(hue: hue, saturation: 0.7, brightness: 0.8)
                    .opacity(0.6 - Double(waveIndex) * 0.1)
                
                context.stroke(path, with: .color(waveColor), lineWidth: 2)
            }
        }
        .onAppear {
            startAnimation()
        }
        .onChange(of: typingChar) { _, _ in
            lastTypingTime = Date()
            waveAmplitude = min(waveAmplitude + 10, 50)
        }
    }
    
    private func startAnimation() {
        Timer.scheduledTimer(withTimeInterval: 1/60, repeats: true) { _ in
            animationTime += 1/60
            
            // Decay wave amplitude based on time since last typing
            let timeSinceTyping = Date().timeIntervalSince(lastTypingTime)
            if timeSinceTyping > 0.5 {
                waveAmplitude = max(waveAmplitude * 0.98, 10)
            }
        }
    }
}

// MARK: - Geometric Morphing Animation
struct GeometricMorphingView: View {
    let typingChar: Character?
    let typingSpeed: Double
    let difficulty: Int
    
    @State private var shapes: [MorphingShape] = []
    @State private var animationTime: Double = 0
    
    private struct MorphingShape: Identifiable {
        let id = UUID()
        var x: Double
        var y: Double
        var size: Double
        var rotation: Double
        var morphProgress: Double
        let shapeType: ShapeType
        let color: Color
        let speed: Double
        
        enum ShapeType: CaseIterable {
            case circle, triangle, square, hexagon
        }
    }
    
    var body: some View {
        Canvas { context, size in
            let time = animationTime
            
            for shape in shapes {
                let currentRotation = shape.rotation + time * shape.speed
                let morphOffset = sin(time * 0.5 + shape.morphProgress) * 10
                let currentSize = shape.size + morphOffset
                
                // Create transformed path directly instead of using save/restore
                let shapePath = createShapePath(
                    type: shape.shapeType,
                    size: currentSize,
                    morphProgress: sin(time * 0.3 + shape.morphProgress),
                    center: CGPoint(x: shape.x, y: shape.y),
                    rotation: currentRotation
                )
                
                context.stroke(
                    shapePath,
                    with: .color(shape.color.opacity(0.4)),
                    lineWidth: 1.5
                )
            }
        }
        .onAppear {
            generateShapes()
            startAnimation()
        }
        .onChange(of: typingChar) { _, _ in
            addTypingShape()
        }
        .onChange(of: difficulty) { _, _ in
            generateShapes()
        }
    }
    
    private func generateShapes() {
        let shapeCount = 8 + difficulty * 3
        shapes = (0..<shapeCount).map { _ in
            MorphingShape(
                x: Double.random(in: 50...350),
                y: Double.random(in: 50...550),
                size: Double.random(in: 20...60),
                rotation: Double.random(in: 0...360),
                morphProgress: Double.random(in: 0...2*Double.pi),
                shapeType: MorphingShape.ShapeType.allCases.randomElement()!,
                color: Color(hue: Double.random(in: 0...1), saturation: 0.7, brightness: 0.8),
                speed: Double.random(in: 10...30)
            )
        }
    }
    
    private func addTypingShape() {
        let newShape = MorphingShape(
            x: Double.random(in: 50...350),
            y: Double.random(in: 50...550),
            size: Double.random(in: 30...80),
            rotation: 0,
            morphProgress: 0,
            shapeType: MorphingShape.ShapeType.allCases.randomElement()!,
            color: Color(hue: min(typingSpeed / 100, 1.0) * 0.7, saturation: 0.8, brightness: 1.0),
            speed: 20 + typingSpeed / 5
        )
        shapes.append(newShape)
        
        if shapes.count > 30 {
            shapes.removeFirst(5)
        }
    }
    
    private func createShapePath(type: MorphingShape.ShapeType, size: Double, morphProgress: Double, center: CGPoint, rotation: Double) -> Path {
        let morphedSize = size * (1 + morphProgress * 0.2)
        let rotationRadians = rotation * Double.pi / 180
        
        switch type {
        case .circle:
            return Path(ellipseIn: CGRect(
                x: center.x - morphedSize/2,
                y: center.y - morphedSize/2,
                width: morphedSize,
                height: morphedSize
            ))
        case .triangle:
            return Path { path in
                let points = 3
                for i in 0...points {
                    let angle = Double(i) * 2 * Double.pi / Double(points) - Double.pi/2 + rotationRadians
                    let x = center.x + cos(angle) * morphedSize/2
                    let y = center.y + sin(angle) * morphedSize/2
                    if i == 0 {
                        path.move(to: CGPoint(x: x, y: y))
                    } else {
                        path.addLine(to: CGPoint(x: x, y: y))
                    }
                }
            }
        case .square:
            return Path { path in
                let points = 4
                for i in 0...points {
                    let angle = Double(i) * 2 * Double.pi / Double(points) + rotationRadians
                    let x = center.x + cos(angle) * morphedSize/2
                    let y = center.y + sin(angle) * morphedSize/2
                    if i == 0 {
                        path.move(to: CGPoint(x: x, y: y))
                    } else {
                        path.addLine(to: CGPoint(x: x, y: y))
                    }
                }
            }
        case .hexagon:
            return Path { path in
                let points = 6
                for i in 0...points {
                    let angle = Double(i) * 2 * Double.pi / Double(points) + rotationRadians
                    let x = center.x + cos(angle) * morphedSize/2
                    let y = center.y + sin(angle) * morphedSize/2
                    if i == 0 {
                        path.move(to: CGPoint(x: x, y: y))
                    } else {
                        path.addLine(to: CGPoint(x: x, y: y))
                    }
                }
            }
        }
    }
    
    private func startAnimation() {
        Timer.scheduledTimer(withTimeInterval: 1/60, repeats: true) { _ in
            animationTime += 1/60
        }
    }
}
