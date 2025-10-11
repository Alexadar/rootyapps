//
//  GameManager.swift
//  froggo.swift
//
//  Created by Oleksandr Koreniuk on 19.09.2025.
//

import SpriteKit

class GameManager {
    weak var scene: GameScene?
    
    // City generation parameters (adjusted for solid buildings like menu)
    private let initialSkyscrapers = 20
    private let scraperSizeYDeviation: CGFloat = 50 // More height variation
    private let scraperWidthDeviation: CGFloat = 30 // More width variation for solid buildings
    private let scraperDistanceDeviation: CGFloat = 1.62 // Golden ratio
    private let initialDeltaBetweenScrapers: CGFloat = 80 // More space between solid buildings
    private let scraperHeight: CGFloat = 100 // Base height from ground
    private let scaleY: CGFloat = 250 // Taller buildings (like menu: 250-300)
    private let scaleX: CGFloat = 80 // Wider buildings (like menu: 80-100)
    
    // Game state
    private var cityLength: CGFloat = 0
    private var progress = 0
    private var progressShift = 0
    private var skyscrapers: [Skyscraper] = []
    
    // Tutorial
    private let tutorialSteps = [
        "Slide down and sideways to help Freddy jump",
        "When Freddy falls, you lose",
        "Freddy jumps better if he eats flies"
    ]
    private let tutorialStepKey = "tutorialStep"
    private var currentTutorialStep = 0
    
    init(scene: GameScene) {
        self.scene = scene
        // Load tutorial progress from UserDefaults (like Unity's PlayerPrefs)
        currentTutorialStep = UserDefaults.standard.integer(forKey: tutorialStepKey)
        // Display current tutorial step
        if currentTutorialStep < tutorialSteps.count {
            scene.tutorialLabel.text = tutorialSteps[currentTutorialStep]
        }
    }
    
    func generateInitialCity() {
        // Generate initial skyscrapers
        for _ in 0..<initialSkyscrapers {
            spawnScraper(useExisting: false)
        }
        
        // Position frog on middle scraper
        if let middleScraper = skyscrapers[safe: initialSkyscrapers / 2] {
            progressShift = middleScraper.index
            scene?.frog.position = CGPoint(
                x: middleScraper.position.x,
                y: middleScraper.position.y + middleScraper.size.height / 2 + 20
            )
        }
    }
    
    private func spawnScraper(useExisting: Bool = true) {
        guard let scene = scene else { return }
        
    let scraper: Skyscraper
    let index = (skyscrapers.last?.index ?? -1) + 1
        
        if useExisting && !skyscrapers.isEmpty {
            // Reuse first scraper (move it to the end)
            scraper = skyscrapers.removeFirst()
        } else {
            // Create new scraper
            let width = scaleX + CGFloat.random(in: 0...scraperWidthDeviation)
            let height = scaleY
            // Tile density tuned to match the original look
            let tileX: CGFloat = 8.0
            let tileY: CGFloat = 6.0
            scraper = Skyscraper(width: width, height: height, tileX: tileX, tileY: tileY)
            scene.addChild(scraper)
        }
        
        scraper.index = index
        
        // Position scraper
        let scraperPositionXDelta = initialDeltaBetweenScrapers * CGFloat.random(in: 0.38...scraperDistanceDeviation)
        let yPosition = -scaleY / 2 + scraperHeight + CGFloat.random(in: 0...scraperSizeYDeviation)
        
        scraper.position = CGPoint(
            x: cityLength + scraperPositionXDelta,
            y: yPosition
        )
        
        skyscrapers.append(scraper)
        cityLength += scraper.size.width + scraperPositionXDelta
    }
    
    func onProgress(_ scraperIndex: Int) {
        let newProgress = scraperIndex - progressShift
        
        if newProgress > progress {
            // Spawn new scrapers for each progress increment
            for _ in progress..<newProgress {
                spawnScraper()
            }
            
            progress = newProgress
            scene?.score = progress
            
            // Update tutorial
            updateTutorial()
        }
    }
    
    private func updateTutorial() {
        guard let scene = scene else { return }

        currentTutorialStep += 1

        if currentTutorialStep < tutorialSteps.count {
            scene.tutorialLabel.text = tutorialSteps[currentTutorialStep]
        } else {
            scene.tutorialLabel.text = ""
        }

        // Save tutorial progress (like Unity's PlayerPrefs.SetInt + Save)
        UserDefaults.standard.set(currentTutorialStep, forKey: tutorialStepKey)
    }
}

// Safe array subscript extension
extension Array {
    subscript(safe index: Index) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
}
