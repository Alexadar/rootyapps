import SwiftUI

#if os(iOS)

/// The AR entry button (top corner of menu and draw screens).
struct ARToggleButton: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if !AppModel.arFeatureEnabled {
            EmptyView()
        } else if model.arMode {
            button
                .buttonStyle(.glassProminent)
                .tint(Tokens.gold.opacity(0.8))
        } else {
            button
                .buttonStyle(.glass)
        }
    }

    private var button: some View {
        Button {
            model.toggleAR()
        } label: {
            Image(systemName: model.arMode ? "arkit.badge.xmark" : "arkit")
                .font(Tokens.label(16))
                .padding(10)
        }
        .accessibilityIdentifier("ar.toggle")
    }
}

/// Place / Re-place, shown at the bottom of whichever screen is up while AR is on.
/// Settlement belongs to the MENU flow (place the table, then begin the draw), but the
/// controls stay available during the draw so a bumped table can be re-placed.
struct ARPlacementControls: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if AppModel.arFeatureEnabled, model.arMode {
            VStack(spacing: 8) {
                if !model.arPlaced {
                    Text("Aim at your table")
                        .font(Tokens.body(14))
                        .foregroundStyle(Tokens.ink)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .tarotGlassChip()
                    Button {
                        model.fixateAR()
                    } label: {
                        Label("Place the table here", systemImage: "checkmark.circle.fill")
                            .font(Tokens.label(18))
                            .padding(.vertical, 6)
                            .padding(.horizontal, 10)
                    }
                    .buttonStyle(.glassProminent)
                    .tint(Tokens.gold.opacity(0.8))
                    .accessibilityIdentifier("ar.place")
                } else {
                    Button {
                        model.replaceAR()
                    } label: {
                        Label("Re-place", systemImage: "arrow.up.and.down.and.arrow.left.and.right")
                            .font(Tokens.label(14))
                    }
                    .buttonStyle(.glass)
                    .accessibilityIdentifier("ar.replace")
                }
                #if DEBUG
                let status = model.renderer.arDebugStatus()
                if !status.isEmpty {
                    Text(status)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(Tokens.inkDim)
                }
                #endif
            }
        }
    }
}

#endif
