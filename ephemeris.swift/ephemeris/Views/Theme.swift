import SwiftUI

extension View {
    /// A padded card — Nebula dark glass (violet border + purple glow).
    func glassCard(cornerRadius: CGFloat = 20) -> some View {
        self.nebulaCard(cornerRadius: cornerRadius)
    }
}

/// Uppercase card header, Nebula styling.
struct CardHeader: View {
    /// The English catalog key. Resolved by `NebulaCardHeader`, which must uppercase it.
    let title: String
    var trailing: Text? = nil
    var body: some View { NebulaCardHeader(title: title, trailing: trailing) }
}
