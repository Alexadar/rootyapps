#if os(macOS)
import ProjectKit
import RedesignKit
import SwiftUI

/// The Mac: a sidebar of spaces, with the in-flight queue living quietly at its foot.
///
/// Three deliberate divergences from the phone, all from the handoff:
///   • **No Live Activity.** Completion is a standard user notification.
///   • **No camera.** A redesign starts from an imported photo — an open panel or a drop.
///   • **No "Set as Desktop".** The deliverable here is the image itself.
///
/// The queue at the sidebar's foot is the Mac's answer to the Live Activity: ambient, always
/// visible, with real step counts. On a machine where the app is one window among many, a queue
/// you have to navigate to is a queue you forget is running.
struct MacRoot: View {

    @Bindable var router: Router
    let coordinator: RedesignCoordinator
    @Bindable var capture: CaptureModel

    @State private var isImporting = false

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 240, ideal: 280, max: 360)
        } detail: {
            // ⚠️ NOT wrapped in a `GlassEffectContainer` with a `glassEffectID` on the stage.
            //
            // That was the original shape here and in both iOS shells, and it is what collapsed
            // the phone layout: an effect id on a view carrying no glass effect, inside a container
            // sizing itself to content, left the stage with no width — spacers vanished and
            // edge-pinned controls drew nothing while still reserving space. The two iOS shells
            // were fixed at the time and this one was not, because macOS UI tests seize the screen
            // and are not run by default, so nothing caught it.
            //
            // The container belongs around the glass, not around the screen.
            FlowStage(router: router,
                      coordinator: coordinator,
                      capture: capture,
                      layout: .rail)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(ARC.canvas)
        }
        .fileImporter(isPresented: $isImporting, allowedContentTypes: [.image]) { result in
            guard case .success(let url) = result,
                  let shot = capture.imported(from: url) else { return }
            router.begin(shot)
        }
    }

    // ── sidebar ──────────────────────────────────────────────────────────────────────────────

    private var sidebar: some View {
        VStack(spacing: 0) {
            List(selection: Binding(get: { router.selectedProjectID },
                                    set: { id in
                                        guard let id,
                                              let project = coordinator.library.project(id: id) else { return }
                                        router.openResult(projectID: id,
                                                          variation: project.variations.last?.index ?? 1)
                                    })) {
                Section {
                    ForEach(coordinator.library.projects) { project in
                        MacSidebarRow(project: project)
                            .tag(project.id)
                    }
                } header: {
                    Text("Spaces")
                        .arcText(.label)
                        .foregroundStyle(ARC.ink.opacity(0.5))
                }
            }
            .listStyle(.sidebar)

            Divider()
            queueFoot
        }
        .safeAreaInset(edge: .top) {
            Button {
                isImporting = true
            } label: {
                Label("New space", systemImage: "plus")
                    .arcText(.subheading)
                    .frame(maxWidth: .infinity, minHeight: ARC.minimumHitTarget)
            }
            .buttonStyle(.glass)
            .padding(ARC.Space.tight)
            .accessibilityIdentifier("mac.newSpace")
        }
    }

    /// The in-flight queue. Present only while there is work — an empty box that says "nothing is
    /// happening" is a box that takes up room for no reason.
    @ViewBuilder private var queueFoot: some View {
        let live = coordinator.engine.state.jobs.filter { $0.phase.isLive }
        if !live.isEmpty {
            VStack(alignment: .leading, spacing: ARC.Space.tight) {
                Text("IN PROGRESS")
                    .arcText(.label)
                    .foregroundStyle(ARC.ink.opacity(0.5))
                    .padding(.horizontal, ARC.Space.tight)
                QueueStrip(jobs: live) { coordinator.engine.cancel($0) }
            }
            .padding(.vertical, ARC.Space.gap)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(ARC.canvasAlt)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("mac.queue")
        }
    }
}

struct MacSidebarRow: View {
    let project: SpaceProject

    var body: some View {
        HStack(spacing: ARC.Space.gap) {
            Group {
                if FileManager.default.fileExists(atPath: project.thumbnailURL.path) {
                    FileImage(url: project.thumbnailURL, maxPixel: 120)
                } else {
                    RoundedRectangle(cornerRadius: 6, style: .continuous).fill(ARC.canvas)
                }
            }
            .frame(width: 40, height: 30)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

            VStack(alignment: .leading, spacing: 1) {
                Text(project.displayName)
                    .arcText(.secondary)
                    .lineLimit(1)
                Text("\(project.variations.count) · \(project.isGhost ? "arriving" : "ready")")
                    .arcText(.micro)
                    .foregroundStyle(ARC.ink.opacity(0.5))
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("mac.space.\(project.id)")
    }
}
#endif
