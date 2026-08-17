import SwiftUI
import CoreGraphics
import RecipeKit
import EditsKit

/// The library (`1f`).
///
/// Every tile carries its **original as a corner swatch** — the pair is the unit, never just the
/// result — plus the strength and scope it was made with. iCloud here is the user's own storage;
/// nothing on this screen may read as an account or a service.
struct LibraryView: View {

    @Environment(\.colorScheme) private var scheme

    var model: LibraryModel
    var onOpen: (EditRecord) -> Void
    var onImport: () -> Void

    private let columns = [GridItem(.adaptive(minimum: 150), spacing: ST.Space.gap)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ST.Space.grid) {
                Text(model.location.libraryPromise)
                    .stFont(.caption)
                    .foregroundStyle(ST.ink2(scheme))
                    .padding(.horizontal, ST.Space.margin)
                    .accessibilityIdentifier("library.promise")

                if model.records.isEmpty {
                    emptyState
                } else {
                    LazyVGrid(columns: columns, spacing: ST.Space.gap) {
                        ForEach(model.records) { record in
                            Button { onOpen(record) } label: {
                                LibraryTile(record: record,
                                            enhanced: model.thumbnail(for: record),
                                            original: model.originalThumbnail(for: record))
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("library.tile")
                        }
                    }
                    .padding(.horizontal, ST.Space.margin)
                }
            }
            .padding(.vertical, ST.Space.grid)
        }
        .background(LinearGradient(colors: ST.canvasGradient, startPoint: .top, endPoint: .bottom))
        .task { await model.reload() }
    }

    private var emptyState: some View {
        VStack(spacing: ST.Space.grid) {
            Image(systemName: "square.grid.2x2")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(ST.ink3(scheme))
            // ⚠️ The promise has to match where the files will really go, so it comes from the
            // resolved location and not from a constant.
            Text(model.location.emptyStatePromise)
                .stFont(.body)
                .foregroundStyle(ST.ink2(scheme))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)

            Button(action: onImport) {
                Text("Bring a photo")
                    .stFont(.button)
                    .foregroundStyle(.white)
                    .padding(.horizontal, ST.Space.section)
                    .frame(height: ST.primaryCapsuleHeight)
            }
            .buttonStyle(.plain)
            .stGlassCapsule(.tinted)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, ST.Space.section * 2)
        .accessibilityIdentifier("library.empty")
    }
}

/// A paired before/after tile. The swatch is 34 pt with a 1.5 pt white border (`1f`).
struct LibraryTile: View {

    @Environment(\.colorScheme) private var scheme

    let record: EditRecord
    let enhanced: CGImage?
    let original: CGImage?

    var body: some View {
        VStack(alignment: .leading, spacing: ST.Space.tight) {
            ZStack(alignment: .bottomLeading) {
                Group {
                    if let enhanced {
                        Image(cgImage: enhanced)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } else {
                        Rectangle().fill(ST.ink(scheme).opacity(0.06))
                    }
                }
                .frame(height: 150)
                .clipShape(RoundedRectangle(cornerRadius: ST.Radius.tile, style: .continuous))

                if let original {
                    Image(cgImage: original)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: ST.swatchSize, height: ST.swatchSize)
                        .clipShape(RoundedRectangle(cornerRadius: ST.Radius.swatch, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: ST.Radius.swatch, style: .continuous)
                                .strokeBorder(.white, lineWidth: ST.swatchBorder))
                        .padding(ST.Space.tight)
                }

                if let caption = record.availability.caption {
                    // Board 1f's third tile: synced from another device, not local yet. The file is
                    // not lost, it is elsewhere, and the tile says which.
                    Text(caption)
                        .stFont(.footnote)
                        .foregroundStyle(.white)
                        .padding(.horizontal, ST.Space.tight)
                        .padding(.vertical, 3)
                        .background(.black.opacity(0.45), in: Capsule())
                        .padding(ST.Space.tight)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }

            HStack {
                Text(record.displayName)
                    .stFont(.caption)
                    .foregroundStyle(ST.ink(scheme))
                    .lineLimit(1)
                Spacer(minLength: ST.Space.hair)
                Text(record.badge)
                    .stFont(.footnote, tabularNumbers: true)
                    .foregroundStyle(ST.ink2(scheme))
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(record.displayName), \(record.badge)")
    }
}
