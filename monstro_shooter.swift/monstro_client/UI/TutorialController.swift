import Foundation

/// Tutorial hint types
enum TutorialHint: Int, CaseIterable {
    case move = 0
    case shoot = 1
    case kill = 2

    var delay: TimeInterval {
        switch self {
        case .move: return GameConstants.tutorialMoveHintDelay
        case .shoot: return GameConstants.tutorialShootHintDelay
        case .kill: return GameConstants.tutorialKillHintDelay
        }
    }

    /// Localized hint text based on platform
    var text: String {
        #if os(macOS)
        switch self {
        case .move: return "To move and avoid monsters, use WASD"
        case .shoot: return "To shoot, press Left Mouse Button"
        case .kill: return "Target monster with crosshair and shoot!"
        }
        #else
        switch self {
        case .move: return "To move and avoid monsters, use left joystick"
        case .shoot: return "To shoot, tap right side of screen"
        case .kill: return "Target monster with crosshair and shoot!"
        }
        #endif
    }
}

/// Controller for tutorial hints - tracks player actions and shows hints when needed
class TutorialController {
    // Action completion flags (RAM only, resets each session)
    private var completedActions: Set<TutorialHint> = []

    // Timers for each action (time since last action)
    private var lastMoveTime: TimeInterval = 0
    private var lastShootTime: TimeInterval = 0
    private var lastKillTime: TimeInterval = 0

    // Track if timers have been initialized with real time
    private var isInitialized: Bool = false

    // Current hint queue and display state
    private var pendingHints: [TutorialHint] = []
    private var currentHintIndex: Int = 0
    private var isShowingHint: Bool = false
    private var hintCooldownUntil: TimeInterval = 0

    // Callback to show hint
    var onShowHint: ((String) -> Void)?
    var onHideHint: (() -> Void)?

    init() {}

    // MARK: - Action Tracking

    func recordMove(at time: TimeInterval) {
        lastMoveTime = time
        completedActions.insert(.move)
    }

    func recordShoot(at time: TimeInterval) {
        lastShootTime = time
        completedActions.insert(.shoot)
    }

    func recordKill(at time: TimeInterval) {
        lastKillTime = time
        completedActions.insert(.kill)
    }

    // MARK: - Update

    func update(currentTime: TimeInterval) {
        // Initialize timers on first update
        if !isInitialized {
            lastMoveTime = currentTime
            lastShootTime = currentTime
            lastKillTime = currentTime
            isInitialized = true
            return
        }

        // Don't process if showing hint or in cooldown
        if isShowingHint { return }
        if currentTime < hintCooldownUntil { return }

        // Build list of hints that should show
        pendingHints.removeAll()

        for hint in TutorialHint.allCases {
            // Skip if already completed
            if completedActions.contains(hint) { continue }

            let lastActionTime: TimeInterval
            switch hint {
            case .move: lastActionTime = lastMoveTime
            case .shoot: lastActionTime = lastShootTime
            case .kill: lastActionTime = lastKillTime
            }

            // Check if delay exceeded
            if currentTime - lastActionTime >= hint.delay {
                pendingHints.append(hint)
            }
        }

        // Show next hint in round-robin
        if !pendingHints.isEmpty {
            currentHintIndex = currentHintIndex % pendingHints.count
            let hint = pendingHints[currentHintIndex]
            showHint(hint, at: currentTime)
            currentHintIndex += 1
        }
    }

    private func showHint(_ hint: TutorialHint, at time: TimeInterval) {
        isShowingHint = true
        onShowHint?(hint.text)

        // Schedule hide after display duration
        let totalDuration = GameConstants.tutorialHintFadeDuration +
                           GameConstants.tutorialHintDisplayDuration +
                           GameConstants.tutorialHintFadeDuration

        DispatchQueue.main.asyncAfter(deadline: .now() + totalDuration) { [weak self] in
            self?.onHideHint?()
            self?.isShowingHint = false
            self?.hintCooldownUntil = time + totalDuration + GameConstants.tutorialHintPauseDuration
        }
    }

    // MARK: - Reset

    func reset(at time: TimeInterval) {
        completedActions.removeAll()
        lastMoveTime = time
        lastShootTime = time
        lastKillTime = time
        pendingHints.removeAll()
        isShowingHint = false
        hintCooldownUntil = 0
        isInitialized = false  // Re-initialize on next update
    }

    // MARK: - State Persistence

    /// Get current completion state for saving
    func getState() -> (moveShown: Bool, shootShown: Bool, killShown: Bool) {
        return (
            completedActions.contains(.move),
            completedActions.contains(.shoot),
            completedActions.contains(.kill)
        )
    }

    /// Restore completion state from saved data
    func restoreState(moveShown: Bool, shootShown: Bool, killShown: Bool) {
        if moveShown { completedActions.insert(.move) }
        if shootShown { completedActions.insert(.shoot) }
        if killShown { completedActions.insert(.kill) }
    }
}
