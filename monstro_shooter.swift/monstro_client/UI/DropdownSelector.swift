import SwiftUI

/// A dropdown-style selector component with expand/collapse functionality
struct DropdownSelector<T: Identifiable>: View {
    let title: String
    let items: [T]
    let selectedItem: T?
    let displayText: (T) -> String
    let onSelect: (T) -> Void

    @State private var isExpanded: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            // Selected item display button
            Button(action: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            }) {
                HStack(spacing: 10) {
                    Text(selectedItem.map(displayText) ?? title)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(Color(hex: "#FFFFFF"))
                        .lineLimit(1)

                    Spacer()

                    // Dropdown arrow
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(Color(hex: "#00FF99"))
                }
                .frame(minWidth: 250)
                .padding(.vertical, 12)
                .padding(.horizontal, 20)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(hex: "#0A1428").opacity(0.9))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color(hex: "#00FF99"), lineWidth: 2)
                )
            }
            .buttonStyle(.plain)

            // Dropdown list
            if isExpanded {
                VStack(spacing: 2) {
                    ForEach(items) { item in
                        Button(action: {
                            onSelect(item)
                            withAnimation(.easeInOut(duration: 0.2)) {
                                isExpanded = false
                            }
                        }) {
                            HStack {
                                Text(displayText(item))
                                    .font(.system(size: 16, weight: .regular))
                                    .foregroundColor(
                                        selectedItem?.id as? Int == item.id as? Int
                                            ? Color(hex: "#00FF99")
                                            : Color(hex: "#FFFFFF")
                                    )
                                    .lineLimit(1)

                                Spacer()

                                if selectedItem?.id as? Int == item.id as? Int {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 12, weight: .bold))
                                        .foregroundColor(Color(hex: "#00FF99"))
                                }
                            }
                            .frame(minWidth: 250)
                            .padding(.vertical, 10)
                            .padding(.horizontal, 20)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(
                                        selectedItem?.id as? Int == item.id as? Int
                                            ? Color(hex: "#0A1428").opacity(0.8)
                                            : Color(hex: "#0A1428").opacity(0.6)
                                    )
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.top, 4)
                .padding(.horizontal, 4)
                .padding(.bottom, 4)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(hex: "#0A1428").opacity(0.95))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color(hex: "#00D9FF"), lineWidth: 1)
                        )
                )
                .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .top)))
            }
        }
    }
}
