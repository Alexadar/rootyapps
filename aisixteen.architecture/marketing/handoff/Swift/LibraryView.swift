import SwiftUI

// Library — grouped by space, not a flat grid. A project is "my living room";
// variations live under it. Original photo + prompt + seed + style are sidecar
// metadata in the iCloud app folder (user-owned storage — never "a service").
struct LibraryView: View {
    struct Space: Identifiable {
        let id = UUID(); let name: String; let count: Int; let when: String
    }
    let spaces = [Space(name: "Living room", count: 3, when: "today"),
                  Space(name: "House facade", count: 2, when: "Sunday")]

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                ForEach(spaces) { space in
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(space.name).font(.headline)
                            Spacer()
                            Text("\(space.count) variations · \(space.when)")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        HStack(spacing: 8) {
                            AfterPlaceholder()
                                .frame(height: 110).frame(maxWidth: .infinity)
                                .clipShape(RoundedRectangle(cornerRadius: 16))
                            BeforePlaceholder()
                                .frame(width: 90, height: 110)
                                .clipShape(RoundedRectangle(cornerRadius: 16))
                            RoundedRectangle(cornerRadius: 16)
                                .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4]))
                                .foregroundStyle(.tertiary)
                                .frame(width: 90, height: 110)
                                .overlay(Image(systemName: "plus").foregroundStyle(.secondary))
                                .accessibilityLabel("New variation for \(space.name)")
                        }
                    }
                }
                Text("Stored in your iCloud folder — yours, in Files, on all your devices")
                    .font(.caption).foregroundStyle(.tertiary)
                    .padding(.top, 8)
            }
            .padding(20).padding(.top, 64)
        }
        .background(DS.canvasAlt)
    }
}
