import SwiftUI

extension View {
    /// A padded Liquid Glass card.
    func glassCard(cornerRadius: CGFloat = 20) -> some View {
        self.padding(16)
            .glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
    }
}

struct CardHeader: View {
    let title: String
    var trailing: String? = nil
    var body: some View {
        HStack {
            Text(title.uppercased())
                .font(.caption.weight(.semibold))
                .tracking(0.5)
                .foregroundStyle(.secondary)
            Spacer()
            if let trailing {
                Text(trailing)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tint)
            }
        }
    }
}
