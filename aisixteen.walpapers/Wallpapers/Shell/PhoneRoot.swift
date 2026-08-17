#if !os(macOS)
import SwiftUI

/// iPhone — the default case. One hand, portrait, phone-shaped output.
struct PhoneRoot: View {
    @Binding var screen: Screen
    var create: CreateModel
    var library: LibraryModel
    var resume: ResumeModel
    /// **Concrete, not `any WallpaperActions`.** `@Observable` tracking does not see through an
    /// existential, so mutations to `handoff` never invalidated this view and the handoff sheet
    /// simply never appeared — the save had happened, with nothing on screen to say so.
    var actions: IOSWallpaperActions
    var onUsePrompt: (String) -> Void

    var body: some View {
        ZStack {
            AmbientBackground(recent: library.mostRecentImage)

            switch screen {
            case .create:
                CreateView(model: create, actions: actions, library: library)
            case .gallery:
                GalleryView(library: library, create: create, actions: actions,
                            onUsePrompt: onUsePrompt,
                            onSurpriseMe: {
                                create.surpriseMe()
                                screen = .create
                            })
            }

            VStack(spacing: WP.Space.gap) {
                Spacer()
                BottomShelf(create: create, resume: resume, library: library)
                ScreenSwitcher(screen: $screen,
                               // One job owns the model: starting a generation mid-Enhance would
                               // put two pipelines in memory, which is what used to crash the app.
                               blocked: create.isEnhancing ? [.create] : [],
                               onBlocked: { _ in create.explainBusy() })
                    .padding(.bottom, 52)
            }
            // Tapping Create while a finished picture is showing means "let me make another one",
            // not "stay here". The second exit from the result, alongside the back circle.
            .onChange(of: screen) { _, now in
                if now == .create, case .done = create.phase { create.dismissResult() }
            }
            // The switcher is chrome; while a wallpaper is forming it would be the only thing on
            // screen competing with the picture, and the picture is the content.
            .opacity(create.isRunning ? 0 : 1)
            .animation(.easeInOut(duration: 0.2), value: create.isRunning)
        }
        .sheet(item: handoffBinding) { handoff in
            HandoffSheet(handoff: handoff)
        }
    }

    /// The iOS handoff sheet, hoisted here so it can present over either screen.
    private var handoffBinding: Binding<WallpaperHandoff?> {
        Binding(get: { actions.handoff }, set: { if $0 == nil { actions.dismissHandoff() } })
    }
}
#endif
