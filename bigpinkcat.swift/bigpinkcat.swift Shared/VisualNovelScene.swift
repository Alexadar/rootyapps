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
    // Track current video sizing inputs for dynamic layout (to relayout on window/scene resize)
    private var currentVideoNaturalSizePx: CGSize?
    private var currentVideoPreferredTransform: CGAffineTransform = .identity

    // MARK: - Initialization
    override func didMove(to view: SKView) {
        setupScene()
        changeState(to: .loading)
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

        // Create title label (UI layer above video)
        titleLabel = SKLabelNode(fontNamed: "Helvetica-Bold")
        titleLabel?.fontSize = 72
        titleLabel?.position = CGPoint(x: size.width / 2, y: size.height / 2 + 220)
        titleLabel?.zPosition = 2
        titleLabel?.fontColor = .white
        titleLabel?.verticalAlignmentMode = .center
        if let title = titleLabel {
            addChild(title)
        }

        // Create character name label (centered vertically)
        characterNameLabel = SKLabelNode(fontNamed: "Helvetica-Bold")
        characterNameLabel?.fontSize = 36
        characterNameLabel?.position = CGPoint(x: size.width / 2, y: size.height / 2 + 100)
        characterNameLabel?.horizontalAlignmentMode = .center
        characterNameLabel?.zPosition = 2
        characterNameLabel?.fontColor = .cyan
        if let nameLabel = characterNameLabel {
            addChild(nameLabel)
        }

        // Create dialog label (centered)
        dialogLabel = SKLabelNode(fontNamed: "Helvetica")
        dialogLabel?.fontSize = 32
        dialogLabel?.position = CGPoint(x: size.width / 2, y: size.height / 2 - 40)
        dialogLabel?.preferredMaxLayoutWidth = size.width - 400
        dialogLabel?.numberOfLines = 0
        dialogLabel?.zPosition = 2
        dialogLabel?.fontColor = .white
        dialogLabel?.verticalAlignmentMode = .center
        if let label = dialogLabel {
            addChild(label)
        }
    }

    // MARK: - State Machine
    private func changeState(to newState: UIState) {
        print("Changing state: \(currentState) -> \(newState)")
        currentState = newState

        // Hide all UI first
        titleLabel?.isHidden = true
        dialogLabel?.isHidden = true
        characterNameLabel?.isHidden = true
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

        // Show "Tap to Start" after delay
        let startLabel = SKLabelNode(fontNamed: "Helvetica")
        startLabel.name = "startLabel"
        startLabel.text = "Tap to Start"
        startLabel.fontSize = 48
        startLabel.position = CGPoint(x: size.width / 2, y: size.height / 2)
        startLabel.fontColor = .white
        startLabel.alpha = 0
        addChild(startLabel)

        let fadeIn = SKAction.fadeIn(withDuration: 1.0)
        let fadeOut = SKAction.fadeOut(withDuration: 1.0)
        let sequence = SKAction.sequence([fadeIn, fadeOut])
        startLabel.run(SKAction.repeatForever(sequence))

        // Play background music if available
        playBackgroundMusic()

        // Try to play background style video if available (use subdirectory-aware loader)
        playBackgroundVideo("style/latest_u_d")
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

        // Show dialog text with typing effect
        dialogLabel?.isHidden = false
        animateDialogText(dialog.dialog.characterText)

        // Load and play character video if available
        if let videoName = dialog.character.videoName {
            playCharacterVideo(videoName)
        }
    }

    private func animateDialogText(_ text: String) {
        dialogLabel?.text = text
        dialogLabel?.alpha = 0
        dialogLabel?.run(SKAction.fadeIn(withDuration: 0.5))
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

        dialogLabel?.isHidden = false
        dialogLabel?.text = "Choose your path:"

        // Create option buttons
        let buttonHeight: CGFloat = 80
        let buttonWidth: CGFloat = 800
        let buttonSpacing: CGFloat = 20
        let totalHeight = CGFloat(options.count) * (buttonHeight + buttonSpacing)
        var yPosition = size.height / 2 + totalHeight / 2

        for (index, option) in options.enumerated() {
            let button = createOptionButton(
                text: option.text,
                position: CGPoint(x: size.width / 2, y: yPosition),
                size: CGSize(width: buttonWidth, height: buttonHeight),
                tag: index
            )
            optionButtons.append(button)
            addChild(button)
            yPosition -= (buttonHeight + buttonSpacing)
        }
    }

    private func createOptionButton(text: String, position: CGPoint, size: CGSize, tag: Int) -> SKShapeNode {
        let button = SKShapeNode(rectOf: size, cornerRadius: 10)
        button.position = position
        button.fillColor = .darkGray
        button.strokeColor = .white
        button.lineWidth = 2
        button.name = "option_\(tag)"
        // Ensure buttons render above video/background
        button.zPosition = 2

        let label = SKLabelNode(fontNamed: "Helvetica")
        label.text = text
        label.fontSize = 28
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
        print("Selected option: \(selectedOption.text)")

        // Load the next summary part
        if let nextDialog = gameDataLoader?.getDialogForSummary(index: selectedOption.nextSummaryIdx) {
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

    // Re-layout video on window/scene resize (macOS windowed, iPad multitasking, etc.)
    override func didChangeSize(_ oldSize: CGSize) {
        super.didChangeSize(oldSize)
        // Update background to fill scene
        backgroundNode?.size = self.size
        backgroundNode?.position = CGPoint(x: self.size.width / 2, y: self.size.height / 2)
        // Re-layout current video as CSS cover
        if let node = videoNode, let nat = currentVideoNaturalSizePx {
            layoutVideoNode(node, naturalSizePx: nat, preferredTransform: currentVideoPreferredTransform)
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
        if let oldItem = currentPlayerItem {
            oldItem.removeObserver(self, forKeyPath: "status", context: &Self.playerItemContext)
            NotificationCenter.default.removeObserver(self, name: .AVPlayerItemFailedToPlayToEndTime, object: oldItem)
            NotificationCenter.default.removeObserver(self, name: .AVPlayerItemDidPlayToEndTime, object: oldItem)
            currentPlayerItem = nil
        }
        videoNode?.removeFromParent()
        videoNode = nil
        if let player = videoPlayer {
            player.pause()
            videoPlayer = nil
        }

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
        if let oldItem = currentPlayerItem {
            oldItem.removeObserver(self, forKeyPath: "status", context: &Self.playerItemContext)
            NotificationCenter.default.removeObserver(self, name: .AVPlayerItemFailedToPlayToEndTime, object: oldItem)
            NotificationCenter.default.removeObserver(self, name: .AVPlayerItemDidPlayToEndTime, object: oldItem)
            currentPlayerItem = nil
        }
        videoNode?.removeFromParent()
        videoNode = nil
        if let player = videoPlayer {
            player.pause()
            videoPlayer = nil
        }

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
            // Remove start label and begin
            childNode(withName: "startLabel")?.removeFromParent()
            changeState(to: .dialog)

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
