//
//  GameManager.swift
//  froggo.swift
//
//  Created by Oleksandr Koreniuk on 19.09.2025.
//

import SpriteKit

class GameManager {
    weak var scene: GameScene?
    
    // Physics parameters
    public let gravitation: CGFloat = -5.8 // Gravity force applied to frog
    public let jumpForce: CGFloat = 50 // Base jump force
    public let jumperLength: CGFloat = 150 // Length of the drag indicator line

    // City generation parameters (matching main menu thickness, full height)
    private let initialSkyscrapers = 20
    private let scraperSizeYDeviation: CGFloat = 100
    private let scraperWidthDeviation: CGFloat = 30 // Width variation ±30% (80-110 range like menu)
    private let scraperDistanceDeviation: CGFloat = 1.62 // Golden ratio
    private let initialDeltaBetweenScrapers: CGFloat = 80 // Space between buildings
    private let scraperHeight: CGFloat = 150 // Base height from ground
    private let scaleY: CGFloat = 1200 // 2x increase from 3000 - buildings extending even further down
    private let scaleX: CGFloat = 80 // Base width (like menu: 80-100)
    
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
            scene.tutorialText = tutorialSteps[currentTutorialStep]
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

        // Only try to reuse scrapers if they're far enough behind
        let frogX = scene.frog.position.x
        let screenWidth = scene.size.width
        let removalThreshold = frogX - (screenWidth * 2)

        let canReuse = useExisting &&
                      !skyscrapers.isEmpty &&
                      skyscrapers.first!.position.x + skyscrapers.first!.size.width < removalThreshold

        if canReuse {
            // Reuse first scraper (it's far behind, safe to move it to the end)
            scraper = skyscrapers.removeFirst()
        } else {
            // Create new scraper (don't remove visible scrapers)
            let width = scaleX + CGFloat.random(in: 0...scraperWidthDeviation)
            let height = scaleY + CGFloat.random(in: -scraperSizeYDeviation...scraperSizeYDeviation)
            // Tile density matching main menu
            let tileX: CGFloat = 6.0
            let tileY: CGFloat = 6.0
            scraper = Skyscraper(width: width, height: height, tileX: tileX, tileY: tileY)
            scene.addChild(scraper)
        }

        scraper.index = index

        // Position scraper
        let scraperPositionXDelta = initialDeltaBetweenScrapers * CGFloat.random(in: 0.38...scraperDistanceDeviation)
        // Position buildings so they extend from near the ground (bottom of scene) upward
        // Center point is at height/2, so position = height/2 to make bottom touch y=0
        let yPosition = scraper.size.height / 2

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
            // Spawn extra scrapers ahead to ensure continuous generation
            for _ in progress..<newProgress {
                spawnScraper()
            }
            // Spawn 2 more ahead to prevent emptiness
            spawnScraper()
            spawnScraper()

            progress = newProgress
            scene?.score = progress

            // Update tutorial
            updateTutorial()
        }
    }

    // Called every frame to check if we need to spawn scrapers ahead
    func update() {
        guard let scene = scene else { return }

        // Calculate how far ahead we should have scrapers
        let frogX = scene.frog.position.x
        let screenWidth = scene.size.width

        // Clean up scrapers that are 2 screen widths behind the camera
        // This keeps them visible longer before removal
        let removalThreshold = frogX - (screenWidth * 2)
        while let firstScraper = skyscrapers.first,
              firstScraper.position.x + firstScraper.size.width < removalThreshold {
            // This scraper is far behind, safe to remove/reuse
            skyscrapers.removeFirst()
        }

        // Ensure we have scrapers at least 4 screen widths ahead (increased from 2)
        // This ensures there's always platforms visible ahead
        let requiredCityLength = frogX + (screenWidth * 4)

        // Aggressively spawn scrapers if needed
        var spawnCount = 0
        while cityLength < requiredCityLength && spawnCount < 50 {
            spawnScraper()
            spawnCount += 1
        }
    }
    
    private func updateTutorial() {
        guard let scene = scene else { return }

        currentTutorialStep += 1

        if currentTutorialStep < tutorialSteps.count {
            scene.tutorialText = tutorialSteps[currentTutorialStep]
        } else {
            scene.tutorialText = ""
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
