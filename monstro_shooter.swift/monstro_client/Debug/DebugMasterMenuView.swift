import SwiftUI

struct DebugMasterMenuView: View {
    @Binding var selectedDebugView: DebugViewType?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 40) {
                Text("DEBUG MENU")
                    .font(.system(size: 48, weight: .bold))
                    .foregroundColor(.green)

                VStack(spacing: 20) {
                    DebugMenuButton(title: "Map Test") {
                        selectedDebugView = .mapSelector
                    }

                    DebugMenuButton(title: "Monster Test") {
                        selectedDebugView = .monsters
                    }

                    DebugMenuButton(title: "Player Test") {
                        selectedDebugView = .playerTest
                    }
                }
            }
        }
    }
}

struct DebugMenuButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 24, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 300, height: 60)
                .background(Color.green.opacity(0.3))
                .cornerRadius(10)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.green, lineWidth: 2)
                )
        }
        .buttonStyle(.plain)
    }
}

enum DebugViewType {
    case mapSelector
    case monsters
    case playerTest
}

struct DebugBackButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text("←")
                    .font(.system(size: 20, weight: .bold))
                Text("BACK")
                    .font(.system(size: 16, weight: .semibold))
            }
            .foregroundColor(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color.green.opacity(0.3))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.green, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }
}
