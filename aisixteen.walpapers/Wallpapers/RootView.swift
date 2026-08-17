import SwiftUI
import GenerationKit

/// Which of the two screens is showing. Two cases, and there is no third.
enum Screen: String, CaseIterable, Identifiable {
    case create = "Create"
    case gallery = "Gallery"
    var id: String { rawValue }
}

/// The root: the gate, or the app.
///
/// The gate stands in front of everything until the model is installed, and never appears again
/// afterwards. Below it there is no `TabView` — the two screens sit behind a floating glass segment
/// control, so the picture stays edge to edge and nothing opaque ever covers it.
struct RootView: View {
    @Environment(\.scenePhase) private var scenePhase

    @State private var gate = ModelGate()
    @State private var library = LibraryModel()
    @State private var create = CreateModel()
    @State private var resume = ResumeModel()
    @State private var screen: Screen = .create

    #if os(macOS)
    @State private var actions = MacWallpaperActions()
    #else
    @State private var actions = IOSWallpaperActions()
    #endif

    var body: some View {
        ZStack {
            if gate.showsShell {
                shell
                    .transition(.opacity)
            } else {
                GateView(gate: gate,
                         onReady: dismissGate,
                         onLookAround: dismissGate,
                         onSurpriseMe: {
                    create.surpriseMe()
                    dismissGate()
                })
            }
        }
        .modifier(AccessibilityModeReader())
        .task {
            await gate.start()
            // Pay the Neural Engine compile here, not in front of someone waiting for a wallpaper.
            // It is minutes on a cold cache and it recurs after every reinstall or iOS update, so
            // it is done whenever the model is present rather than once ever.
            startTuning()
            await library.start()
            // After the library, because an Enhance offer needs the record its tiles belong to.
            resume.look()
        }
        .onChange(of: scenePhase) { _, phase in
            // Coming back to a download in flight must show where it actually got to, not where it
            // was when the app was backgrounded.
            if phase == .active, !gate.phase.isFinished { gate.keepWaiting() }
        }
    }

    @ViewBuilder
    private var shell: some View {
        #if os(macOS)
        MacRoot(create: create, library: library, resume: resume, actions: actions, onUsePrompt: usePrompt)
        #else
        AdaptiveRoot(screen: $screen, create: create, library: library, resume: resume,
                     actions: actions, onUsePrompt: usePrompt)
        #endif
    }

    /// The one-time Neural Engine compile, if anything is left to compile.
    ///
    /// Surveyed off the main actor — it walks the model directory — and skipped entirely on a warm
    /// launch, which is the common case.
    private func startTuning() {
        let parts = create.tunableParts
        guard !parts.isEmpty else { gate.markTuned(); return }
        let skipping = gate.begin(tuning: parts)
        guard skipping.count < parts.count else { return }
        create.tune(skipping: skipping) { event in gate.absorb(event) }
    }

    private func dismissGate() {
        withAnimation { gate.stopObserving() }
        screen = .create
    }

    private func usePrompt(_ prompt: String) {
        create.prompt = prompt
        screen = .create
    }
}

#if !os(macOS)
/// iPhone and iPad from one root, split on size class rather than on device model — an iPhone in
/// landscape on a Pro Max and an iPad in Slide Over are both genuinely the compact case.
struct AdaptiveRoot: View {
    @Environment(\.horizontalSizeClass) private var sizeClass

    @Binding var screen: Screen
    var create: CreateModel
    var library: LibraryModel
    var resume: ResumeModel
    var actions: IOSWallpaperActions
    var onUsePrompt: (String) -> Void

    var body: some View {
        if sizeClass == .regular {
            PadRoot(create: create, library: library, resume: resume,
                    actions: actions, onUsePrompt: onUsePrompt)
        } else {
            PhoneRoot(screen: $screen, create: create, library: library, resume: resume,
                      actions: actions, onUsePrompt: onUsePrompt)
        }
    }
}
#endif

/// The floating segment control. **Not a `TabView`**: a tab bar is an opaque band across the bottom
/// of a screen whose whole point is a full-bleed picture.
struct ScreenSwitcher: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.wpAccessibility) private var accessibility
    @Namespace private var switcher

    @Binding var screen: Screen

    /// Screens that cannot be entered right now. One job owns the model, so Create is closed while
    /// an Enhance is refining tiles.
    var blocked: Set<Screen> = []
    /// What to say when a blocked segment is tapped. **The segment stays tappable** — a control that
    /// simply does nothing reads as broken, and the one thing the user needs is the reason.
    var onBlocked: (Screen) -> Void = { _ in }

    var body: some View {
        GlassEffectContainer(spacing: WP.Space.hair) {
            HStack(spacing: WP.Space.hair) {
                ForEach(Screen.allCases) { candidate in
                    Button {
                        guard !blocked.contains(candidate) else {
                            onBlocked(candidate)
                            return
                        }
                        withAnimation(WPMotion.morph(reduceMotion: accessibility.reduceMotion)) {
                            screen = candidate
                        }
                    } label: {
                        Text(candidate.rawValue)
                            .wpFont(.control)
                            .foregroundStyle(blocked.contains(candidate)
                                             ? WP.inkDisabled(scheme)
                                             : (screen == candidate ? WP.ink(scheme) : WP.ink3(scheme)))
                            .padding(.horizontal, WP.Space.margin)
                            .padding(.vertical, 10)
                    }
                    .buttonStyle(.plain)
                    .background {
                        if screen == candidate {
                            Capsule()
                                .fill(WP.ink(scheme).opacity(0.08))
                                .matchedGeometryEffect(id: "activeSegment", in: switcher)
                        }
                    }
                    .accessibilityAddTraits(screen == candidate ? [.isButton, .isSelected] : .isButton)
                    .accessibilityHint(blocked.contains(candidate) ? EnhanceCopy.oneThingAtATime : "")
                }
            }
            .padding(WP.Space.hair)
            .wpGlassCapsule()
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Screens")
    }
}
