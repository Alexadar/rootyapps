import SwiftUI

/// Adaptive two-column layout for a tool detail. Compact (iPhone portrait) stacks everything in one
/// column exactly as before; regular (iPad / Mac / iPhone landscape) lays the inputs LEFT and the
/// results RIGHT — never a stretched single column. Presentation only: each tool view just sorts its
/// existing cards into `inputs` (diagram + entry cards) and `outputs` (the one `HeroReadout` + result
/// cards). See KERF-DesignSystem/ToolDetailView.example.swift.
struct ToolColumns<Inputs: View, Outputs: View>: View {
    @Environment(\.horizontalSizeClass) private var hSize
    @ViewBuilder var inputs: Inputs
    @ViewBuilder var outputs: Outputs

    init(@ViewBuilder inputs: () -> Inputs, @ViewBuilder outputs: () -> Outputs) {
        self.inputs = inputs()
        self.outputs = outputs()
    }

    var body: some View {
        if hSize == .regular {
            HStack(alignment: .top, spacing: 14) {
                VStack(spacing: 13) { inputs }.frame(maxWidth: .infinity, alignment: .top)
                VStack(spacing: 13) { outputs }.frame(maxWidth: .infinity, alignment: .top)
            }
        } else {
            VStack(spacing: 13) { inputs; outputs }
        }
    }
}
