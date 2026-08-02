import SwiftUI

// Category switching — compact size class. One thumb-tap filters the grid.
// The same mental model as the regular-size sidebar: trade dot + name + count;
// the active chip fills graphite, count flips to signal.
// Used by the Formulas tab (ToolSection) and the Reference tab (ReferenceSection).

/// A generic filter chip row. `nil` selection = "All".
struct CategoryChips<Category: Hashable>: View {
    struct Item {
        let category: Category?          // nil = All
        let label: String
        var dot: Color? = nil            // trade accent dot; nil for plain chips
        var count: Int? = nil
    }

    let items: [Item]
    @Binding var selection: Category?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 7) {
                ForEach(items.indices, id: \.self) { i in
                    chip(items[i])
                }
            }
            .padding(.horizontal, 15)
        }
        .padding(.horizontal, -15)  // bleed to screen edge inside a 15pt-padded parent
    }

    @ViewBuilder
    private func chip(_ item: Item) -> some View {
        let active = item.category == selection
        Button {
            withAnimation(.snappy(duration: 0.2)) { selection = item.category }
        } label: {
            HStack(spacing: 6) {
                if let dot = item.dot {
                    RoundedRectangle(cornerRadius: 3).fill(dot).frame(width: 8, height: 8)
                }
                Text(item.label)
                    .font(.system(size: 13, weight: active ? .bold : .semibold))
                    .foregroundStyle(active ? KC.onInstrument : KC.textSecondary)
                if active, let count = item.count {
                    Text("\(count)")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(KC.signal)
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 9)   // ≥ 34pt chip; row stays one-hand
            .background(active ? KC.instrument : KC.surface, in: .capsule)
            .overlay(Capsule().strokeBorder(active ? .clear : KC.hairline, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Formulas tab items

extension CategoryChips where Category == ToolSection {
    /// "All" + one chip per trade, with live counts.
    static func formulaItems() -> [Item] {
        [Item(category: nil, label: "All", count: Tool.allCases.count)] +
        ToolSection.allCases.map { s in
            Item(category: s, label: s.rawValue, dot: s.accent, count: Tool.tools(in: s).count)
        }
    }
}

// MARK: - Reference tab sections

/// Groups for the Reference tab — mirrors the sidebar on regular.
enum ReferenceSection: String, CaseIterable, Identifiable {
    case codes = "Codes", tables = "Tables", conversions = "Convert", standards = "Standards"
    var id: String { rawValue }
}

extension CategoryChips where Category == ReferenceSection {
    static func referenceItems() -> [Item] {
        [Item(category: nil, label: "All")] +
        ReferenceSection.allCases.map { Item(category: $0, label: $0.rawValue) }
    }
}
