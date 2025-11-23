//
//  VisualNovelScene.swift
//  bigpinkcat.swift Shared
//
//  Main visual novel game scene
//

import SpriteKit
import AVFoundation

class VisualNovelScene: SKScene {

    // MARK: - UI State
    enum UIState {
        case none
        case loading
        case mainMenu
        case dialog
        case dialogOptions
        case finalWords
        case error
    }

    // MARK: - Properties
    private var currentState: UIState = .none
    private var gameDataLoader: GameDataLoader?
    private var currentDialog: DialogNode?
    private var videoPlayer: AVPlayer?
    private var audioPlayer: AVAudioPlayer?

    // AV player item observation
    private static var playerItemContext = 0
    private var currentPlayerItem: AVPlayerItem?
    private var avSessionActivated: Bool = false

    // UI Elements (rendered above video)
    private var titleLabel: SKLabelNode?
    private var dialogLabel: SKLabelNode?
    private var characterNameLabel: SKLabelNode?
    private var optionButtons: [SKShapeNode] = []
    private var videoNode: SKVideoNode?
    private var backgroundNode: SKSpriteNode?
    private var dialogBackgroundPanel: SKShapeNode?
    private var optionsCaptionLabel: SKLabelNode?
    private var optionsCaptionPanel: SKShapeNode?

    // Settings keys
    private static let muteSettingKey = "bigpinkcat_isMuted"

    // Mute state with persistent storage
    private var isMuted: Bool {
        get { UserDefaults.standard.bool(forKey: Self.muteSettingKey) }
        set {
            UserDefaults.standard.set(newValue, forKey: Self.muteSettingKey)
            applyMuteState()
        }
    }

    #if DEBUG
    private var debugLabel: SKLabelNode?
    private var currentSummaryIndex: Int = 0
    private var showDebug: Bool = false
    #endif
    // Track current video sizing inputs for dynamic layout (to relayout on window/scene resize)
    private var currentVideoNaturalSizePx: CGSize?
    private var currentVideoPreferredTransform: CGAffineTransform = .identity

    // MARK: - Initialization
    override func didMove(to view: SKView) {
        setupScene()
        changeState(to: .loading)
    }

    deinit {
        cleanupVideoPlayer()
    }

    private func cleanupVideoPlayer() {
        cleanupVideoOnly()

        // Stop audio player
        audioPlayer?.stop()
        audioPlayer = nil
    }

    private func cleanupVideoOnly() {
        // Remove KVO observer and notifications from current player item
        if let item = currentPlayerItem {
            item.removeObserver(self, forKeyPath: "status", context: &Self.playerItemContext)
            NotificationCenter.default.removeObserver(self, name: .AVPlayerItemFailedToPlayToEndTime, object: item)
            NotificationCenter.default.removeObserver(self, name: .AVPlayerItemDidPlayToEndTime, object: item)
            currentPlayerItem = nil
        }

        // Stop and release video player
        videoPlayer?.pause()
        videoPlayer = nil

        // Remove video node from scene
        videoNode?.removeFromParent()
        videoNode = nil
    }

    private func setupScene() {
        backgroundColor = .black
        scaleMode = .resizeFill

        // Create background (video will be placed behind UI)
        backgroundNode = SKSpriteNode(color: .black, size: size)
        backgroundNode?.position = CGPoint(x: size.width / 2, y: size.height / 2)
        backgroundNode?.zPosition = 0
        if let bg = backgroundNode {
            addChild(bg)
        }

        // Create title label (UI layer above video) - supports wrapping for long titles
        titleLabel = SKLabelNode(fontNamed: "Helvetica-Bold")
        titleLabel?.fontSize = 56
        titleLabel?.position = CGPoint(x: size.width / 2, y: size.height / 2 + 180)
        titleLabel?.zPosition = 2
        titleLabel?.fontColor = .white
        titleLabel?.verticalAlignmentMode = .center
        titleLabel?.horizontalAlignmentMode = .center
        titleLabel?.preferredMaxLayoutWidth = size.width - 100
        titleLabel?.numberOfLines = 0
        if let title = titleLabel {
            addChild(title)
        }

        // Create character name label (positioned above dialog)
        characterNameLabel = SKLabelNode(fontNamed: "Helvetica-Bold")
        characterNameLabel?.fontSize = 28
        characterNameLabel?.position = CGPoint(x: size.width / 2, y: size.height / 2 + 120)
        characterNameLabel?.horizontalAlignmentMode = .center
        characterNameLabel?.zPosition = 3
        characterNameLabel?.fontColor = .cyan
        if let nameLabel = characterNameLabel {
            addChild(nameLabel)
        }

        // Create dialog label (centered, smaller text to prevent overlap)
        dialogLabel = SKLabelNode(fontNamed: "Helvetica")
        dialogLabel?.fontSize = 24
        dialogLabel?.position = CGPoint(x: size.width / 2, y: size.height / 2 + 40)
        dialogLabel?.preferredMaxLayoutWidth = size.width - 100
        dialogLabel?.numberOfLines = 0
        dialogLabel?.zPosition = 3
        dialogLabel?.fontColor = .white
        dialogLabel?.verticalAlignmentMode = .top
        if let label = dialogLabel {
            addChild(label)
        }

        // Create options caption label (used for "Choose your path:")
        optionsCaptionLabel = SKLabelNode(fontNamed: "Helvetica-Bold")
        optionsCaptionLabel?.fontSize = 28
        optionsCaptionLabel?.zPosition = 2
        optionsCaptionLabel?.fontColor = .white
        optionsCaptionLabel?.horizontalAlignmentMode = .center
        optionsCaptionLabel?.verticalAlignmentMode = .center
        optionsCaptionLabel?.isHidden = true
        if let caption = optionsCaptionLabel {
            addChild(caption)
        }

        #if DEBUG
        // Create debug label at bottom of screen
        debugLabel = SKLabelNode(fontNamed: "Courier")
        debugLabel?.fontSize = 14
        debugLabel?.position = CGPoint(x: size.width / 2, y: 30)
        debugLabel?.zPosition = 10
        debugLabel?.fontColor = .yellow
        debugLabel?.horizontalAlignmentMode = .center
        debugLabel?.isHidden = true
        if let debug = debugLabel {
            addChild(debug)
        }
        #endif
    }

    // MARK: - State Machine
    private func changeState(to newState: UIState) {
        print("Changing state: \(currentState) -> \(newState)")
        currentState = newState

        // Hide all UI first
        titleLabel?.isHidden = true
        dialogLabel?.isHidden = true
        characterNameLabel?.isHidden = true
        dialogBackgroundPanel?.removeFromParent()
        dialogBackgroundPanel = nil
        optionsCaptionLabel?.isHidden = true
        optionsCaptionPanel?.removeFromParent()
        optionsCaptionPanel = nil
        removeOptionButtons()

        switch newState {
        case .none:
            break

        case .loading:
            loadGameData()

        case .mainMenu:
            showMainMenu()

        case .dialog:
            showDialog()

        case .dialogOptions:
            showDialogOptions()

        case .finalWords:
            showFinalWords()

        case .error:
            showError("An error occurred")
        }
    }

    // MARK: - Loading State
    private func loadGameData() {
        titleLabel?.text = "Loading..."
        titleLabel?.isHidden = false

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let loader = GameDataLoader(gameFolder: "output_story")
                try loader.loadAllData()

                DispatchQueue.main.async {
                    self.gameDataLoader = loader
                    self.currentDialog = loader.getInitialDialog()
                    self.changeState(to: .mainMenu)
                }
            } catch {
                print("Error loading game data: \(error)")
                DispatchQueue.main.async {
                    self.changeState(to: .error)
                }
            }
        }
    }

    // MARK: - Main Menu State
    private func showMainMenu() {
        guard let gameMeta = gameDataLoader?.gameMeta else {
            changeState(to: .error)
            return
        }

        titleLabel?.text = gameMeta.gameName
        titleLabel?.isHidden = false

        // Fade in title
        titleLabel?.alpha = 0
        titleLabel?.run(SKAction.fadeIn(withDuration: 2.0))

        // Create "Start Game" button
        let startButton = createOptionButton(
            text: "Start Game",
            position: CGPoint(x: size.width / 2, y: size.height / 2),
            size: CGSize(width: 300, height: 60),
            tag: -1  // Special tag for start button
        )
        startButton.name = "startButton"
        startButton.alpha = 0
        addChild(startButton)
        optionButtons.append(startButton)

        // Create "Mute/Unmute" button
        let muteButton = createOptionButton(
            text: isMuted ? "Unmute" : "Mute",
            position: CGPoint(x: size.width / 2, y: size.height / 2 - 80),
            size: CGSize(width: 300, height: 60),
            tag: -2  // Special tag for mute button
        )
        muteButton.name = "muteButton"
        muteButton.alpha = 0
        addChild(muteButton)
        optionButtons.append(muteButton)

        // Fade in buttons
        let fadeIn = SKAction.fadeIn(withDuration: 1.0)
        startButton.run(fadeIn)
        muteButton.run(fadeIn)

        // Play background music if available
        playBackgroundMusic()

        // Try to play background style video if available (use subdirectory-aware loader)
        playBackgroundVideo("style/latest_u_d")

        #if DEBUG
        debugLabel?.text = "Main Menu"
        debugLabel?.isHidden = !showDebug
        #endif
    }

    // MARK: - Dialog State
    private func showDialog() {
        guard let dialog = currentDialog else {
            changeState(to: .error)
            return
        }

        // Show character name
        characterNameLabel?.text = dialog.character.name
        characterNameLabel?.isHidden = false

        // Reset dialog label position and alignment for regular dialog
        dialogLabel?.position = CGPoint(x: size.width / 2, y: size.height / 2 + 40)
        dialogLabel?.verticalAlignmentMode = .top
        dialogLabel?.horizontalAlignmentMode = .center

        // Show dialog text with typing effect (also creates background panel)
        dialogLabel?.isHidden = false
        animateDialogText(dialog.dialog.characterText)

        // Load and play character video if available
        if let videoName = dialog.character.videoName {
            playCharacterVideo(videoName)
        }

        #if DEBUG
        updateDebugLabel()
        #endif
    }

    #if DEBUG
    private func updateDebugLabel() {
        guard let dialog = currentDialog else {
            debugLabel?.isHidden = true
            return
        }

        // Find total dialogs in current summary and current position
        let dialogId = dialog.dialog.id
        var totalInSummary = 0
        var currentPosition = 0

        // Walk backwards to find first dialog in chain
        var firstInChain: DialogNode? = dialog
        while let prev = firstInChain?.previousDialog {
            firstInChain = prev
        }

        // Count total and find position
        var walker: DialogNode? = firstInChain
        while walker != nil {
            totalInSummary += 1
            if walker?.dialog.id == dialogId {
                currentPosition = totalInSummary
            }
            walker = walker?.nextDialog
        }

        let hasOptions = dialog.options != nil && !(dialog.options?.isEmpty ?? true)
        let hasFinalWords = dialog.dialog.finalWordsOfTheStory != nil
        let isLastDialog = dialog.nextDialog == nil

        debugLabel?.text = "Summary: \(currentSummaryIndex) | Dialog: \(currentPosition)/\(totalInSummary) (id:\(dialogId)) | Last:\(isLastDialog) | Options:\(hasOptions) | Final:\(hasFinalWords)"
        debugLabel?.isHidden = !showDebug
    }
    #endif

    private func animateDialogText(_ text: String) {
        dialogLabel?.text = text
        dialogLabel?.alpha = 0
        dialogLabel?.run(SKAction.fadeIn(withDuration: 0.5))

        // Update background panel to wrap around text
        updateDialogBackgroundPanel()
    }

    private func updateDialogBackgroundPanel() {
        // Remove old panel
        dialogBackgroundPanel?.removeFromParent()

        // Calculate bounds that encompass character name and dialog text
        guard let nameLabel = characterNameLabel, !nameLabel.isHidden,
              let dialogLbl = dialogLabel, !dialogLbl.isHidden else {
            // If only dialog label is visible (e.g., final words)
            if let dialogLbl = dialogLabel, !dialogLbl.isHidden {
                let textFrame = dialogLbl.frame
                let padding: CGFloat = 30
                let panelWidth = max(textFrame.width + padding * 2, 400)
                let panelHeight = textFrame.height + padding * 2

                let panel = SKShapeNode(rectOf: CGSize(width: panelWidth, height: panelHeight), cornerRadius: 15)
                panel.position = CGPoint(x: dialogLbl.position.x, y: dialogLbl.position.y)
                panel.fillColor = SKColor.black.withAlphaComponent(0.4)
                panel.strokeColor = SKColor.white.withAlphaComponent(0.2)
                panel.lineWidth = 1
                panel.zPosition = 1
                addChild(panel)
                dialogBackgroundPanel = panel
            }
            return
        }

        // Calculate combined bounds for name + dialog
        let nameFrame = nameLabel.frame
        let dialogFrame = dialogLbl.frame
        let padding: CGFloat = 30

        let minY = min(nameFrame.minY, dialogFrame.minY)
        let maxY = max(nameFrame.maxY, dialogFrame.maxY)
        let minX = min(nameFrame.minX, dialogFrame.minX)
        let maxX = max(nameFrame.maxX, dialogFrame.maxX)

        let panelWidth = max(maxX - minX + padding * 2, 400)
        let panelHeight = maxY - minY + padding * 2
        let centerX = (minX + maxX) / 2
        let centerY = (minY + maxY) / 2

        let panel = SKShapeNode(rectOf: CGSize(width: panelWidth, height: panelHeight), cornerRadius: 15)
        panel.position = CGPoint(x: centerX, y: centerY)
        panel.fillColor = SKColor.black.withAlphaComponent(0.4)
        panel.strokeColor = SKColor.white.withAlphaComponent(0.2)
        panel.lineWidth = 1
        panel.zPosition = 1
        addChild(panel)
        dialogBackgroundPanel = panel
    }

    private func advanceDialog() {
        guard let current = currentDialog else { return }

        if let next = current.nextDialog {
            currentDialog = next
            showDialog()
        } else {
            // No more dialogs, check for options or final words
            if let options = current.options, !options.isEmpty {
                changeState(to: .dialogOptions)
            } else if current.dialog.finalWordsOfTheStory != nil {
                changeState(to: .finalWords)
            } else {
                // Story ended, go back to menu
                changeState(to: .mainMenu)
            }
        }
    }

    // MARK: - Dialog Options State
    private func showDialogOptions() {
        guard let dialog = currentDialog,
              let options = dialog.options else {
            changeState(to: .error)
            return
        }

        let centerX = size.width / 2
        let centerY = size.height / 2
        let layout = adaptiveLayout

        // Calculate button sizing with overflow protection
        let buttonCount = options.count
        let totalHeight = CGFloat(buttonCount) * (layout.buttonHeight + layout.buttonSpacing)
        let availableHeight = size.height - 100

        let effectiveButtonHeight = totalHeight > availableHeight
            ? min(layout.buttonHeight, (availableHeight - 50) / CGFloat(buttonCount) - layout.buttonSpacing)
            : layout.buttonHeight
        let effectiveTotalHeight = CGFloat(buttonCount) * (effectiveButtonHeight + layout.buttonSpacing)

        var yPosition = centerY + effectiveTotalHeight / 2
        let captionY = min(yPosition + effectiveButtonHeight / 2 + 20, size.height - 50)

        // Position caption above the buttons
        optionsCaptionLabel?.text = "Choose your path:"
        optionsCaptionLabel?.position = CGPoint(x: centerX, y: captionY)
        optionsCaptionLabel?.isHidden = false

        // Create background panel for caption (same style as dialog panels)
        let captionWidth: CGFloat = 280
        let captionHeight: CGFloat = 50
        let captionPanel = SKShapeNode(rectOf: CGSize(width: captionWidth, height: captionHeight), cornerRadius: 15)
        captionPanel.position = CGPoint(x: centerX, y: captionY)
        captionPanel.fillColor = SKColor.black.withAlphaComponent(0.4)
        captionPanel.strokeColor = SKColor.white.withAlphaComponent(0.2)
        captionPanel.lineWidth = 1
        captionPanel.zPosition = 1
        addChild(captionPanel)
        optionsCaptionPanel = captionPanel

        for (index, option) in options.enumerated() {
            let button = createOptionButton(
                text: option.text,
                position: CGPoint(x: centerX, y: yPosition),
                size: CGSize(width: layout.maxButtonWidth, height: effectiveButtonHeight),
                tag: index
            )
            optionButtons.append(button)
            addChild(button)
            yPosition -= (effectiveButtonHeight + layout.buttonSpacing)
        }
    }

    private func createOptionButton(text: String, position: CGPoint, size: CGSize, tag: Int) -> SKShapeNode {
        // Style buttons like dialog background panels (semi-transparent with subtle border)
        let button = SKShapeNode(rectOf: size, cornerRadius: 15)
        button.position = position
        button.fillColor = SKColor.black.withAlphaComponent(0.4)
        button.strokeColor = SKColor.white.withAlphaComponent(0.2)
        button.lineWidth = 1
        button.name = "option_\(tag)"
        // Ensure buttons render above video/background
        button.zPosition = 2

        // Adaptive font size based on button height
        let fontSize: CGFloat = min(size.height * 0.35, 28)

        let label = SKLabelNode(fontNamed: "Helvetica")
        label.text = text
        label.fontSize = fontSize
        label.fontColor = .white
        label.verticalAlignmentMode = .center
        label.preferredMaxLayoutWidth = size.width - 40
        label.numberOfLines = 0
        button.addChild(label)

        return button
    }

    private func removeOptionButtons() {
        for button in optionButtons {
            button.removeFromParent()
        }
        optionButtons.removeAll()
    }

    private func selectOption(index: Int) {
        guard let dialog = currentDialog,
              let options = dialog.options,
              index < options.count else {
            return
        }

        let selectedOption = options[index]
        print("Selected option: \(selectedOption.text) -> summary \(selectedOption.nextSummaryIdx)")

        // Load the next summary part
        if let nextDialog = gameDataLoader?.getDialogForSummary(index: selectedOption.nextSummaryIdx) {
            #if DEBUG
            currentSummaryIndex = selectedOption.nextSummaryIdx
            #endif
            currentDialog = nextDialog
            changeState(to: .dialog)
        } else {
            print("Error: Could not load next dialog for summary \(selectedOption.nextSummaryIdx)")
            changeState(to: .error)
        }
    }

    // MARK: - Final Words State
    private func showFinalWords() {
        guard let dialog = currentDialog,
              let finalWords = dialog.dialog.finalWordsOfTheStory else {
            changeState(to: .error)
            return
        }

        characterNameLabel?.isHidden = true
        dialogLabel?.isHidden = false
        dialogLabel?.text = finalWords

        // Center the dialog label for final words
        dialogLabel?.position = CGPoint(x: size.width / 2, y: size.height / 2)
        dialogLabel?.verticalAlignmentMode = .center
        dialogLabel?.horizontalAlignmentMode = .center

        // Create background panel that wraps around final words
        updateDialogBackgroundPanel()

        // Return to menu after delay
        let wait = SKAction.wait(forDuration: 5.0)
        let returnToMenu = SKAction.run { [weak self] in
            self?.changeState(to: .mainMenu)
        }
        run(SKAction.sequence([wait, returnToMenu]))
    }

    // MARK: - Error State
    private func showError(_ message: String) {
        titleLabel?.text = "Error"
        titleLabel?.isHidden = false
        dialogLabel?.text = message
        dialogLabel?.isHidden = false
    }

    // MARK: - Audio Control
    private func toggleMute() {
        isMuted = !isMuted
        print("Audio muted: \(isMuted)")
    }

    private func applyMuteState() {
        let muted = isMuted
        audioPlayer?.volume = muted ? 0.0 : 1.0
        videoPlayer?.isMuted = muted

        // Update button label if visible
        if let muteButton = childNode(withName: "muteButton") as? SKShapeNode,
           let label = muteButton.children.first as? SKLabelNode {
            label.text = muted ? "Unmute" : "Mute"
        }
    }

    // MARK: - Media Playback
    // Layout helper: scales video to CSS cover for current scene size (handles up/down scaling and rotation)
    private func layoutVideoNode(_ node: SKVideoNode, naturalSizePx: CGSize, preferredTransform: CGAffineTransform) {
        let rotation = atan2(preferredTransform.b, preferredTransform.a)

        #if os(iOS) || os(tvOS)
        let screenScale: CGFloat = self.view?.contentScaleFactor ?? UIScreen.main.scale
        #elseif os(OSX)
        let screenScale: CGFloat = self.view?.window?.backingScaleFactor ?? 1.0
        #else
        let screenScale: CGFloat = 1.0
        #endif

        let nativeW = max(naturalSizePx.width, 1.0) / max(screenScale, 1.0)
        let nativeH = max(naturalSizePx.height, 1.0) / max(screenScale, 1.0)

        let cosT = abs(cos(rotation))
        let sinT = abs(sin(rotation))
        // AABB of rotated rect in points
        let aabbW = nativeW * cosT + nativeH * sinT
        let aabbH = nativeW * sinT + nativeH * cosT

        let sceneW = self.size.width
        let sceneH = self.size.height

        // CSS cover: ensure no black bars, one dimension matches or exceeds, allows downscale if scene smaller
        let coverScale = max(sceneW / max(aabbW, 1.0), sceneH / max(aabbH, 1.0))

        let finalW = nativeW * coverScale
        let finalH = nativeH * coverScale

        node.size = CGSize(width: finalW, height: finalH)
        node.zRotation = rotation
        node.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        node.position = CGPoint(x: sceneW / 2.0, y: sceneH / 2.0)
    }

    // Helper to determine if we're in landscape orientation
    private var isLandscape: Bool {
        return size.width > size.height
    }

    // Adaptive layout constants based on orientation
    private var adaptiveLayout: (titleOffset: CGFloat, nameOffset: CGFloat, dialogOffset: CGFloat, buttonSpacing: CGFloat, buttonHeight: CGFloat, maxButtonWidth: CGFloat, padding: CGFloat) {
        if isLandscape {
            // Landscape: more compact vertical spacing, use horizontal space
            return (
                titleOffset: min(size.height * 0.25, 120),
                nameOffset: min(size.height * 0.15, 80),
                dialogOffset: min(size.height * 0.05, 30),
                buttonSpacing: 12,
                buttonHeight: 60,
                maxButtonWidth: min(size.width - 80, 600),
                padding: 60
            )
        } else {
            // Portrait: original spacing
            return (
                titleOffset: 180,
                nameOffset: 120,
                dialogOffset: 40,
                buttonSpacing: 20,
                buttonHeight: 80,
                maxButtonWidth: min(size.width - 40, 800),
                padding: 100
            )
        }
    }

    // Re-layout video and UI on window/scene resize (macOS windowed, iPad multitasking, etc.)
    override func didChangeSize(_ oldSize: CGSize) {
        super.didChangeSize(oldSize)

        let centerX = self.size.width / 2
        let centerY = self.size.height / 2
        let layout = adaptiveLayout

        // Update background to fill scene
        backgroundNode?.size = self.size
        backgroundNode?.position = CGPoint(x: centerX, y: centerY)

        // Re-layout current video as CSS cover
        if let node = videoNode, let nat = currentVideoNaturalSizePx {
            layoutVideoNode(node, naturalSizePx: nat, preferredTransform: currentVideoPreferredTransform)
        }

        // Re-center all UI elements with adaptive offsets
        titleLabel?.position = CGPoint(x: centerX, y: centerY + layout.titleOffset)
        titleLabel?.preferredMaxLayoutWidth = self.size.width - layout.padding

        characterNameLabel?.position = CGPoint(x: centerX, y: centerY + layout.nameOffset)

        // For dialog, check if we're in finalWords state (centered) or regular dialog (top-aligned)
        if currentState == .finalWords {
            dialogLabel?.position = CGPoint(x: centerX, y: centerY)
        } else {
            dialogLabel?.position = CGPoint(x: centerX, y: centerY + layout.dialogOffset)
        }
        dialogLabel?.preferredMaxLayoutWidth = self.size.width - layout.padding

        optionsCaptionLabel?.position.x = centerX

        #if DEBUG
        debugLabel?.position = CGPoint(x: centerX, y: 30)
        #endif

        // Re-center option buttons based on current state
        if currentState == .mainMenu {
            // Reposition menu buttons
            if let startButton = childNode(withName: "startButton") {
                startButton.position = CGPoint(x: centerX, y: centerY)
            }
            if let muteButton = childNode(withName: "muteButton") {
                muteButton.position = CGPoint(x: centerX, y: centerY - 80)
            }
        } else if currentState == .dialogOptions {
            relayoutDialogOptions()
        }

        // Update dialog background panel position if visible
        if dialogBackgroundPanel != nil {
            updateDialogBackgroundPanel()
        }
    }

    // Relayout dialog options to fit current screen size
    private func relayoutDialogOptions() {
        let centerX = self.size.width / 2
        let centerY = self.size.height / 2
        let layout = adaptiveLayout

        let buttonCount = optionButtons.count
        let totalHeight = CGFloat(buttonCount) * (layout.buttonHeight + layout.buttonSpacing)

        // Check if options would overflow and adjust
        let availableHeight = size.height - 100 // Leave margins
        let needsScroll = totalHeight > availableHeight

        let effectiveButtonHeight = needsScroll ? min(layout.buttonHeight, (availableHeight - 50) / CGFloat(buttonCount) - layout.buttonSpacing) : layout.buttonHeight
        let effectiveTotalHeight = CGFloat(buttonCount) * (effectiveButtonHeight + layout.buttonSpacing)

        var yPosition = centerY + effectiveTotalHeight / 2
        let captionY = min(yPosition + effectiveButtonHeight / 2 + 20, size.height - 50)

        optionsCaptionLabel?.position = CGPoint(x: centerX, y: captionY)
        optionsCaptionPanel?.position = CGPoint(x: centerX, y: captionY)

        for button in optionButtons {
            button.position = CGPoint(x: centerX, y: yPosition)
            // Resize button width for current orientation
            let newPath = CGPath(roundedRect: CGRect(x: -layout.maxButtonWidth/2, y: -effectiveButtonHeight/2, width: layout.maxButtonWidth, height: effectiveButtonHeight), cornerWidth: 15, cornerHeight: 15, transform: nil)
            button.path = newPath
            yPosition -= (effectiveButtonHeight + layout.buttonSpacing)
        }
    }
    private func playBackgroundMusic() {
        // Activate audio session for playback on iOS/tvOS (avoid HALC messages)
        #if os(iOS) || os(tvOS)
        if !avSessionActivated {
            do {
                try AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback, options: [])
                try AVAudioSession.sharedInstance().setActive(true)
                avSessionActivated = true
            } catch {
                print("AVAudioSession setActive failed: \(error)")
            }
        }
        #endif

        // Load and play bgm.wav from Resources (use subdirectory)
        if let url = Bundle.main.url(forResource: "bgm", withExtension: "wav", subdirectory: "output_story/audio") {
            do {
                audioPlayer = try AVAudioPlayer(contentsOf: url)
                audioPlayer?.numberOfLoops = -1 // Loop forever
                audioPlayer?.volume = isMuted ? 0.0 : 1.0
                audioPlayer?.play()
            } catch {
                print("Error playing background music: \(error)")
            }
        } else {
            print("Background music file not found in bundle (output_story/audio/bgm.wav)")
        }
    }

    private func playCharacterVideo(_ videoName: String) {
        // Stop any existing video node/player and cleanup observers
        cleanupVideoOnly()

        // videoName expected like "char1/latest_u_d"
        let components = videoName.split(separator: "/").map(String.init)
        guard let fileName = components.last else {
            print("Invalid video name: \(videoName)")
            return
        }
        let subpathComponents = components.dropLast().joined(separator: "/") // e.g. "char1"
        let subdirectory = subpathComponents.isEmpty ? "output_story/video" : "output_story/video/\(subpathComponents)"

        // Try mp4 then mov
        var videoURL = Bundle.main.url(forResource: fileName, withExtension: "mp4", subdirectory: subdirectory)
        if videoURL == nil {
            videoURL = Bundle.main.url(forResource: fileName, withExtension: "mov", subdirectory: subdirectory)
        }
        guard let finalURL = videoURL else {
            print("Character video not found in bundle: \(subdirectory)/\(fileName).(mp4|mov)")
            return
        }

        print("Attempting to play character video: \(finalURL.path)")

        // Validate asset using modern AVAsset.load(_:) async API and add diagnostics
        let asset = AVURLAsset(url: finalURL)

        // Use Task to call async AVAsset loader without changing method signatures
        Task {
            do {
                // isPlayable
                let isPlayable: Bool = try await asset.load(.isPlayable)
                // natural size & preferred transform for sizing (use first video track)
                #if os(visionOS)
                let allTracks: [AVAssetTrack] = try await asset.load(.tracks)
                let firstTrackForSizing = allTracks.first(where: { $0.mediaType == .video })
                var naturalSize = CGSize(width: self.size.width, height: self.size.height)
                var preferredTransform = CGAffineTransform.identity
                if let v = firstTrackForSizing {
                    naturalSize = try await v.load(.naturalSize)
                    preferredTransform = try await v.load(.preferredTransform)
                }
                // Basic diagnostics
                let duration = try await asset.load(.duration)
                let videoTracks = allTracks.filter { $0.mediaType == .video }
                let audioTracks = allTracks.filter { $0.mediaType == .audio }
                #else
                let tracksForSizing = asset.tracks(withMediaType: .video)
                let firstTrackForSizing = tracksForSizing.first
                let naturalSize = firstTrackForSizing?.naturalSize ?? CGSize(width: self.size.width, height: self.size.height)
                let preferredTransform = firstTrackForSizing?.preferredTransform ?? .identity

                // Basic diagnostics
                let duration = asset.duration
                let videoTracks = asset.tracks.filter { $0.mediaType == .video }
                let audioTracks = asset.tracks.filter { $0.mediaType == .audio }
                #endif
                print("AVAsset diagnostics for \(finalURL.lastPathComponent): isPlayable=\(isPlayable), duration=\(CMTimeGetSeconds(duration))s, videoTracks=\(videoTracks.count), audioTracks=\(audioTracks.count)")

                // Inspect first video track format descriptions (best-effort)
                if let vTrack = videoTracks.first {
                    #if os(visionOS)
                    let fmtDescs: [CMFormatDescription] = (try? await vTrack.load(.formatDescriptions)) ?? []
                    #else
                    let fmtDescs = vTrack.formatDescriptions as? [CMFormatDescription] ?? []
                    #endif
                    let codecStrings = fmtDescs.compactMap { desc -> String? in
                        let c = CMFormatDescriptionGetMediaSubType(desc)
                        let n = String(format: "%c%c%c%c", Int((c >> 24) & 0xff), Int((c >> 16) & 0xff), Int((c >> 8) & 0xff), Int(c & 0xff))
                        return n
                    }
                    if !codecStrings.isEmpty {
                        print("Video codec(s): \(codecStrings)")
                    }
                }

                // If asset is playable create player item on main thread
                await MainActor.run {
                    if isPlayable {
                        let item = AVPlayerItem(asset: asset)
                        self.currentPlayerItem = item
                        item.addObserver(self, forKeyPath: "status", options: [.initial, .new], context: &Self.playerItemContext)
                        NotificationCenter.default.addObserver(self, selector: #selector(self.playerItemFailed(_:)), name: .AVPlayerItemFailedToPlayToEndTime, object: item)
                        NotificationCenter.default.addObserver(self, selector: #selector(self.playerItemDidEnd(_:)), name: .AVPlayerItemDidPlayToEndTime, object: item)

                        let player = AVPlayer(playerItem: item)
                        player.actionAtItemEnd = .none
                        self.videoPlayer = player

                        // Create video node and add behind UI (video z = 0)
                        let skNode = SKVideoNode(avPlayer: player)
                        skNode.zPosition = 0

                        // Layout as CSS cover and remember sizing params for future resizes
                        self.currentVideoNaturalSizePx = naturalSize
                        self.currentVideoPreferredTransform = preferredTransform
                        self.layoutVideoNode(skNode, naturalSizePx: naturalSize, preferredTransform: preferredTransform)

                        self.addChild(skNode)
                        self.videoNode = skNode

                        player.isMuted = self.isMuted
                        player.play()
                    } else {
                        print("Asset not playable (async): \(finalURL.lastPathComponent)")
                    }
                }
            } catch {
                await MainActor.run {
                    print("AVAsset async load failed for \(finalURL.lastPathComponent): \(error)")
                }
            }
        }
    }

    private func playBackgroundVideo(_ resourcePath: String) {
        // Stop any existing video node/player and cleanup observers
        cleanupVideoOnly()

        // resourcePath expected like "style/latest_u_d" or "char1/latest_u_d"
        let components = resourcePath.split(separator: "/").map(String.init)
        guard let fileName = components.last else {
            print("Invalid background video resource: \(resourcePath)")
            return
        }
        let subpathComponents = components.dropLast().joined(separator: "/") // e.g. "style"
        let subdirectory = subpathComponents.isEmpty ? "output_story/video" : "output_story/video/\(subpathComponents)"

        var videoURL = Bundle.main.url(forResource: fileName, withExtension: "mp4", subdirectory: subdirectory)
        if videoURL == nil {
            videoURL = Bundle.main.url(forResource: fileName, withExtension: "mov", subdirectory: subdirectory)
        }
        guard let finalURL = videoURL else {
            print("Background video not found in bundle: \(subdirectory)/\(fileName).(mp4|mov)")
            return
        }

        print("Attempting to play background video: \(finalURL.path)")

        // Validate asset using modern AVAsset.load(_:) async API and add diagnostics
        let asset = AVURLAsset(url: finalURL)

        Task {
            do {
                let isPlayable: Bool = try await asset.load(.isPlayable)
                // Determine sizing from first video track (avoid calling .naturalSize on asset)
                #if os(visionOS)
                let allTracks: [AVAssetTrack] = try await asset.load(.tracks)
                let firstTrackForSizing = allTracks.first(where: { $0.mediaType == .video })
                var naturalSize = CGSize(width: self.size.width, height: self.size.height)
                var preferredTransform = CGAffineTransform.identity
                if let v = firstTrackForSizing {
                    naturalSize = try await v.load(.naturalSize)
                    preferredTransform = try await v.load(.preferredTransform)
                }

                let duration = try await asset.load(.duration)
                let videoTracks = allTracks.filter { $0.mediaType == .video }
                let audioTracks = allTracks.filter { $0.mediaType == .audio }
                #else
                let tracksForSizing = asset.tracks(withMediaType: .video)
                let firstTrackForSizing = tracksForSizing.first
                let naturalSize = firstTrackForSizing?.naturalSize ?? CGSize(width: self.size.width, height: self.size.height)
                let preferredTransform = firstTrackForSizing?.preferredTransform ?? .identity

                let duration = asset.duration
                let videoTracks = asset.tracks.filter { $0.mediaType == .video }
                let audioTracks = asset.tracks.filter { $0.mediaType == .audio }
                #endif
                print("AVAsset diagnostics for \(finalURL.lastPathComponent): isPlayable=\(isPlayable), duration=\(CMTimeGetSeconds(duration))s, videoTracks=\(videoTracks.count), audioTracks=\(audioTracks.count)")

                if let vTrack = videoTracks.first {
                    #if os(visionOS)
                    let fmtDescs: [CMFormatDescription] = (try? await vTrack.load(.formatDescriptions)) ?? []
                    #else
                    let fmtDescs = vTrack.formatDescriptions as? [CMFormatDescription] ?? []
                    #endif
                    let codecStrings = fmtDescs.compactMap { desc -> String? in
                        let c = CMFormatDescriptionGetMediaSubType(desc)
                        let n = String(format: "%c%c%c%c", Int((c >> 24) & 0xff), Int((c >> 16) & 0xff), Int((c >> 8) & 0xff), Int(c & 0xff))
                        return n
                    }
                    if !codecStrings.isEmpty {
                        print("Video codec(s): \(codecStrings)")
                    }
                }

                await MainActor.run {
                    if isPlayable {
                        let item = AVPlayerItem(asset: asset)
                        self.currentPlayerItem = item
                        item.addObserver(self, forKeyPath: "status", options: [.initial, .new], context: &Self.playerItemContext)
                        NotificationCenter.default.addObserver(self, selector: #selector(self.playerItemFailed(_:)), name: .AVPlayerItemFailedToPlayToEndTime, object: item)
                        NotificationCenter.default.addObserver(self, selector: #selector(self.playerItemDidEnd(_:)), name: .AVPlayerItemDidPlayToEndTime, object: item)

                        let player = AVPlayer(playerItem: item)
                        player.actionAtItemEnd = .none
                        self.videoPlayer = player

                        let skNode = SKVideoNode(avPlayer: player)
                        skNode.zPosition = 0
                        skNode.position = CGPoint(x: self.size.width / 2, y: self.size.height / 2)

                        // Layout as CSS cover and remember sizing params for future resizes
                        self.currentVideoNaturalSizePx = naturalSize
                        self.currentVideoPreferredTransform = preferredTransform
                        self.layoutVideoNode(skNode, naturalSizePx: naturalSize, preferredTransform: preferredTransform)
                        skNode.alpha = 0.9

                        self.addChild(skNode)
                        self.videoNode = skNode

                        player.isMuted = self.isMuted
                        player.play()
                    } else {
                        print("Asset not playable (async): \(finalURL.lastPathComponent)")
                    }
                }
            } catch {
                await MainActor.run {
                    print("AVAsset async load failed for \(finalURL.lastPathComponent): \(error)")
                }
            }
        }
    }

    // Observe AVPlayerItem KVO and notifications
    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        guard context == &Self.playerItemContext else {
            super.observeValue(forKeyPath: keyPath, of: object, change: change, context: context)
            return
        }

        if keyPath == "status", let item = object as? AVPlayerItem {
            switch item.status {
            case .readyToPlay:
                print("PlayerItem readyToPlay for \(item.asset)")
            case .failed:
                print("PlayerItem failed: \(String(describing: item.error))")
            default:
                break
            }
        }
    }

    @objc private func playerItemFailed(_ note: Notification) {
        if let item = note.object as? AVPlayerItem {
            print("Notification: failed to play item: \(String(describing: item.error))")
        }
    }

    @objc private func playerItemDidEnd(_ note: Notification) {
        if let item = note.object as? AVPlayerItem {
            print("Notification: did play to end: \(item)")
            item.seek(to: .zero, completionHandler: nil)
        }
    }

    // MARK: - Input Handling
    #if os(iOS) || os(tvOS)
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        handleTap(at: touch.location(in: self))
    }
    #endif

    #if os(OSX)
    override func mouseDown(with event: NSEvent) {
        handleTap(at: event.location(in: self))
    }
    #endif

    private func handleTap(at location: CGPoint) {
        switch currentState {
        case .mainMenu:
            // Check if a menu button was tapped
            let touchedNodes = nodes(at: location)
            for node in touchedNodes {
                if node.name == "startButton" || node.parent?.name == "startButton" {
                    #if DEBUG
                    currentSummaryIndex = 0
                    #endif
                    currentDialog = gameDataLoader?.getInitialDialog()
                    changeState(to: .dialog)
                    return
                } else if node.name == "muteButton" || node.parent?.name == "muteButton" {
                    toggleMute()
                    return
                }
            }

        case .dialog:
            advanceDialog()

        case .dialogOptions:
            // Check if an option button was tapped
            let touchedNodes = nodes(at: location)
            for node in touchedNodes {
                // Accept taps on the button or its child label
                if let name = node.name, name.hasPrefix("option_") {
                    let indexStr = name.replacingOccurrences(of: "option_", with: "")
                    if let index = Int(indexStr) {
                        selectOption(index: index)
                        break
                    }
                } else if let parentName = node.parent?.name, parentName.hasPrefix("option_") {
                    let indexStr = parentName.replacingOccurrences(of: "option_", with: "")
                    if let index = Int(indexStr) {
                        selectOption(index: index)
                        break
                    }
                }
            }

        default:
            break
        }
    }
}
