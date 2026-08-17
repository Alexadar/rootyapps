import SwiftUI
import RecipeKit

/// Where the app's one promise is actually made (`1e`).
///
/// Every row says, literally, what happens to the original. No watermark, no Pro badge, no upsell —
/// this sheet is where the one-payment position is felt, and a row that hedged would undo the whole
/// product.
///
/// ⚠️ **Two rows, not three.** The handoff draws a third, "Replace in Photos". It is deliberately
/// absent: replacing needs full read-write access to the photo library, and the owner chose to keep
/// this build add-only so the app never asks for more than it needs. Flagged in the report.
struct ExportSheet: View {

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme

    let deviceName: String
    var onChoose: (ExportOption) -> Void

    @State private var selection: ExportOption = .default

    var body: some View {
        VStack(alignment: .leading, spacing: ST.Space.margin) {
            Text("Save")
                .stFont(.screenTitle)
                .foregroundStyle(ST.ink(scheme))

            VStack(spacing: ST.Space.tight) {
                ForEach(ExportOption.allCases, id: \.self) { option in
                    row(option)
                }
            }

            Button {
                onChoose(selection)
                dismiss()
            } label: {
                Text(selection.primaryButtonTitle)
                    .stFont(.button)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: ST.primaryCapsuleHeight)
            }
            .buttonStyle(.plain)
            .stGlassCapsule(.tinted)
            .accessibilityIdentifier("export.confirm")

            Text(PrivacyCopy.exportFooter(deviceName: deviceName))
                .stFont(.footnote)
                .foregroundStyle(ST.ink3(scheme))
                .frame(maxWidth: .infinity, alignment: .center)
                .accessibilityIdentifier("export.privacy")
        }
        .padding(ST.Space.margin)
        .frame(maxWidth: 460)
        .background(ST.canvas)
        .presentationDetents([.medium])
        .accessibilityIdentifier("export.sheet")
    }

    private func row(_ option: ExportOption) -> some View {
        Button {
            selection = option
        } label: {
            HStack(alignment: .top, spacing: ST.Space.gap) {
                Image(systemName: selection == option ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 20))
                    .foregroundStyle(selection == option ? ST.accent : ST.ink3(scheme))

                VStack(alignment: .leading, spacing: 3) {
                    Text(option.title)
                        .stFont(.button)
                        .foregroundStyle(ST.ink(scheme))
                    // ⚠️ Literal, never ambiguous. This sentence is the product.
                    Text(option.fateOfTheOriginal)
                        .stFont(.caption)
                        .foregroundStyle(ST.ink2(scheme))
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
            }
            .padding(ST.Space.grid)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .stGlassCard(.regular, radius: ST.Radius.plate, shadow: false)
        .accessibilityIdentifier("export.\(option.rawValue)")
        .accessibilityLabel(option.title)
        .accessibilityValue(option.fateOfTheOriginal)
        .accessibilityAddTraits(selection == option ? [.isButton, .isSelected] : .isButton)
    }
}
