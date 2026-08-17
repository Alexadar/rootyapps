import DirectionKit
import ProjectKit
import RedesignKit
import SwiftUI

/// The shell: a floating glass segment over a full-bleed stage. Never a `TabView`.
///
/// ⚠️ `GlassEffectContainer` wraps THE GLASS, not the whole screen. An earlier version put the
/// entire flow inside it and hung a `glassEffectID` on the stage — an id on a view that carries no
/// glass effect at all. The result was a stage that laid out at the wrong size, where spacers
/// collapsed and a control at the leading edge of a row silently drew nothing. Nothing about that
/// is visible in a test log; it took looking at a frame and then probing the pixels.
///
/// The morph's three silent killers (from the sibling's `JobMorph.swift`) still apply wherever a
/// morph is added: the container must be a stable ancestor declared above the branch, the
/// `@Namespace` must live there too, and every branch must carry the glass AND the same id.
struct RootView: View {

    @Bindable var router: Router
    let coordinator: RedesignCoordinator
    @Bindable var capture: CaptureModel

    // No `@Namespace` here any more. It existed to feed a `glassEffectID` on the whole flow
    // stage — the shape that collapsed the layout. The glass segment owns its own namespace
    // internally (see `GlassSegment`), and a namespace threaded through three shells and used by
    // none of them is just a parameter nobody can delete with confidence later.
    @Environment(\.arcAccessibility) private var accessibility
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        content
            // The accent drains while any render is live. Published once, here, so every accent in
            // the app follows it.
            .environment(\.accentDrained, coordinator.engine.state.hasLiveWork)
            .onReceive(NotificationCenter.default.publisher(for: .arcOpenResult)) { note in
                guard let projectID = note.userInfo?["projectID"] as? String else { return }
                let project = coordinator.library.project(id: projectID)
                let variation = project?.variations.last?.index ?? 1
                router.openResult(projectID: projectID, variation: variation)
            }
    }

    @ViewBuilder private var content: some View {
        #if os(macOS)
        MacRoot(router: router, coordinator: coordinator, capture: capture)
        #else
        if horizontalSizeClass == .regular {
            PadRoot(router: router, coordinator: coordinator, capture: capture)
        } else {
            PhoneRoot(router: router, coordinator: coordinator, capture: capture)
        }
        #endif
    }
}

/// The phone: full-bleed stage, floating segment on top.
struct PhoneRoot: View {
    @Bindable var router: Router
    let coordinator: RedesignCoordinator
    @Bindable var capture: CaptureModel

    @Environment(\.arcAccessibility) private var accessibility

    var body: some View {
        ZStack(alignment: .top) {
            FlowStage(router: router, coordinator: coordinator, capture: capture, layout: .sheet)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            GlassEffectContainer(spacing: ARC.Space.gap) {
                ScreenSegment(section: $router.section)
            }
            .padding(.top, ARC.Space.tight)
        }
        .animation(ARCMotion.morph(reduceMotion: accessibility.reduceMotion), value: router.section)
        .background(ARC.canvas)
    }
}

/// The iPad: the direction rail beside the photo, not a bottom sheet over it.
struct PadRoot: View {
    @Bindable var router: Router
    let coordinator: RedesignCoordinator
    @Bindable var capture: CaptureModel

    @Environment(\.arcAccessibility) private var accessibility

    var body: some View {
        ZStack(alignment: .top) {
            FlowStage(router: router, coordinator: coordinator, capture: capture, layout: .rail)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            GlassEffectContainer(spacing: ARC.Space.gap) {
                ScreenSegment(section: $router.section)
            }
            .padding(.top, ARC.Space.tight)
        }
        .animation(ARCMotion.morph(reduceMotion: accessibility.reduceMotion), value: router.section)
        .background(ARC.canvas)
    }
}

/// Whichever screen the flow is on.
struct FlowStage: View {
    @Bindable var router: Router
    let coordinator: RedesignCoordinator
    @Bindable var capture: CaptureModel
    let layout: SheetSurface<AnyView>.Layout

    @State private var direction: DirectionModel?
    @State private var result = ResultModel()

    var body: some View {
        Group {
            switch router.section {
            case .redesign: redesign
            case .library: library
            }
        }
    }

    @ViewBuilder private var redesign: some View {
        switch router.stage {
        case .capture:
            CaptureView(model: capture) { shot in
                direction = DirectionModel(shot: shot)
                router.begin(shot)
            }

        case .direction(let shot):
            DirectionView(model: model(for: shot),
                          layout: layout,
                          onRetake: { router.startOver() },
                          onStart: { start(shot) })

        case .generating:
            if let progress = coordinator.engine.progress, let head = coordinator.engine.state.head {
                GeneratingView(progress: progress,
                               queuedLabels: coordinator.engine.state.queuedLabels,
                               variationLabel: "\(head.request.variationLabel) of \(head.request.variationCount)",
                               styleName: head.request.styleName,
                               onCancel: { coordinator.engine.cancel(head.id) },
                               onResumeAnyway: { coordinator.engine.resumeAnyway(head.id) },
                               onWaitForCharge: { coordinator.engine.waitForCharge(head.id) })
            } else {
                waiting
            }

        case .result(let projectID, let variation):
            if let project = coordinator.library.project(id: projectID) {
                ResultView(project: project,
                           variationIndex: variation,
                           model: result,
                           layout: layout,
                           onSelectVariation: { router.openResult(projectID: projectID, variation: $0) },
                           onNewVariation: { try? coordinator.again(project: project) },
                           onSave: { save(project, variation: variation) },
                           onTryAgain: { try? coordinator.again(project: project) },
                           onShare: { share(project, variation: variation) },
                           onRegenerate: { regenerate(project) },
                           onDelete: { delete(project) })
            } else {
                waiting
            }
        }
    }

    private var library: some View {
        LibraryView(library: coordinator.library,
                    onOpen: { project, variation in
                        router.openResult(projectID: project.id, variation: variation)
                    },
                    onNewVariation: { try? coordinator.again(project: $0) },
                    onRename: { router.renamingProjectID = $0.id },
                    onDelete: { try? coordinator.library.delete($0) })
    }

    private var waiting: some View {
        ZStack {
            ARC.canvas
            ProgressView().arcAccentTint()
        }
        .ignoresSafeArea()
    }

    // ── actions ──────────────────────────────────────────────────────────────────────────────

    private func model(for shot: SourceShot) -> DirectionModel {
        if let direction, direction.shot == shot { return direction }
        let model = DirectionModel(shot: shot)
        Task { @MainActor in direction = model }
        return model
    }

    private func start(_ shot: SourceShot) {
        guard let direction else { return }
        try? coordinator.start(shot: shot,
                               recipe: direction.recipe,
                               variations: direction.variations)
    }

    private func save(_ project: SpaceProject, variation: Int) {
        guard let record = project.variations.first(where: { $0.index == variation }) else { return }
        #if os(iOS)
        ShareActions.saveToPhotos(record.imageURL)
        #else
        MacActions.export(record.imageURL,
                          suggestedName: "\(project.displayName) \(variation).png")
        #endif
    }

    private func share(_ project: SpaceProject, variation: Int) {
        guard let record = project.variations.first(where: { $0.index == variation }) else { return }
        #if os(macOS)
        MacActions.reveal(record.imageURL)
        #else
        ShareActions.saveToPhotos(record.imageURL)
        #endif
    }

    /// "Regenerate with edits" returns to Direction with the recipe loaded, per the handoff.
    private func regenerate(_ project: SpaceProject) {
        guard let sidecar = project.sidecar,
              let data = try? Data(contentsOf: project.sourceURL),
              let size = SampleAssets.pixelSize(of: data) else { return }

        var depthValues: [Float] = []
        var depthSize = PixelSize(width: 0, height: 0)
        if let depthData = try? Data(contentsOf: project.depthURL),
           let decoded = RedesignCoordinator.decodeDepth(depthData) {
            depthValues = decoded.values
            depthSize = decoded.size
        }

        let shot = SourceShot(mode: sidecar.mode == .interior ? .interior : .exterior,
                              imageData: data,
                              pixelSize: size,
                              depthValues: depthValues,
                              depthSize: depthSize,
                              provenance: RedesignCoordinator.provenance(sidecar.depthProvenance))

        let recipe = PromptRecipe(presetID: sidecar.recipe.presetID,
                                  prompt: sidecar.recipe.prompt,
                                  mode: sidecar.mode == .interior ? .interior : .exterior)
        direction = DirectionModel(shot: shot,
                                   recipe: recipe,
                                   variations: sidecar.recipe.requestedVariations)
        router.editAgain(shot)
    }

    private func delete(_ project: SpaceProject) {
        try? coordinator.library.delete(project)
        router.openLibrary()
    }
}
