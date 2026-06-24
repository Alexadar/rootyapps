//
//  ExtremesPanel.swift
//  eartharound.swift
//
//  Created by Oleksandr Koreniuk on 06.11.2025.
//

import SwiftUI

struct ExtremesPanel: View {
    let title: String
    let extremes: DailyExtremes
    @State private var selectedEvent: AggregatedEvent?
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        ZStack {
            VStack(alignment: .leading, spacing: 12) {
                Text(title)
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)

                if extremes.aggregated.isEmpty {
                    Text("No extremes")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .padding(.vertical, 8)
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(extremes.aggregated) { event in
                            EventBadge(event: event)
                                .onTapGesture {
                                    selectedEvent = event
                                }
                        }
                    }
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(colorScheme == .dark ? Color.white.opacity(0.2) : Color.black.opacity(0.1), lineWidth: 1)
                    )
            )

            if let event = selectedEvent {
                EventDetailView(event: event) {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        selectedEvent = nil
                    }
                }
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: selectedEvent)
    }
}

struct EventBadge: View {
    let event: AggregatedEvent

    var body: some View {
        HStack(spacing: 12) {
            Text(event.icon)
                .font(.title)
            VStack(alignment: .leading, spacing: 2) {
                Text(event.displayName)
                    .font(.subheadline.weight(.semibold))
                Text(event.formattedValue)
                    .font(.footnote.weight(.medium))
                    .opacity(0.9)
            }
            Spacer()
            if event.count > 1 {
                Text("x\(event.count)")
                    .font(.headline)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(event.themeColor)
        )
        .foregroundColor(.white)
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = FlowResult(in: proposal.replacingUnspecifiedDimensions().width, subviews: subviews, spacing: spacing)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = FlowResult(in: bounds.width, subviews: subviews, spacing: spacing)
        for (index, row) in result.rows.enumerated() {
            let rowY = bounds.minY + result.rows[..<index].reduce(0) { $0 + $1.height + spacing }
            var rowX = bounds.minX
            for subview in row.subviews {
                let size = subview.sizeThatFits(.unspecified)
                subview.place(at: CGPoint(x: rowX, y: rowY), proposal: .unspecified)
                rowX += size.width + spacing
            }
        }
    }

    struct FlowResult {
        var rows: [Row] = []
        var size: CGSize = .zero

        struct Row {
            var subviews: [LayoutSubviews.Element] = []
            var width: CGFloat = 0
            var height: CGFloat = 0
        }

        init(in maxWidth: CGFloat, subviews: Subviews, spacing: CGFloat) {
            var currentRow = Row()
            var currentX: CGFloat = 0

            for subview in subviews {
                let size = subview.sizeThatFits(.unspecified)

                if currentX + size.width > maxWidth, !currentRow.subviews.isEmpty {
                    rows.append(currentRow)
                    currentRow = Row()
                    currentX = 0
                }

                currentRow.subviews.append(subview)
                currentRow.width = currentX + size.width
                currentRow.height = max(currentRow.height, size.height)
                currentX += size.width + spacing
            }

            if !currentRow.subviews.isEmpty {
                rows.append(currentRow)
            }

            let totalHeight = rows.reduce(0) { $0 + $1.height } + CGFloat(max(0, rows.count - 1)) * spacing
            let maxRowWidth = rows.map(\.width).max() ?? 0
            size = CGSize(width: maxRowWidth, height: totalHeight)
        }
    }
}
