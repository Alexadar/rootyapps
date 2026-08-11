import SwiftUI
import AirsideKit

/// Shared UI atoms.

/// Altitude chip — first-class, never a buried setting.
public struct AltitudeChip: View {
    public var altitude: Altitude
    public var action: () -> Void
    public init(altitude: Altitude, action: @escaping () -> Void) {
        self.altitude = altitude; self.action = action
    }
    public var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: "triangle").font(.system(size: 9, weight: .bold))
                Text("\(Int(altitude.feet).formatted()) ft").font(DS.number(11.5))
            }
            .foregroundColor(DS.ink)
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(DS.panel).overlay(Capsule().stroke(DS.border, lineWidth: 1)).clipShape(Capsule())
        }.buttonStyle(.plain)
    }
}

/// IP ⇄ SI toggle.
public struct UnitToggle: View {
    @Binding public var system: UnitSystem
    public init(system: Binding<UnitSystem>) { self._system = system }
    public var body: some View {
        Button { system = (system == .ip ? .si : .ip) } label: {
            Text(system.rawValue).font(DS.number(11.5))
                .foregroundColor(DS.ink)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(DS.panel).overlay(Capsule().stroke(DS.border, lineWidth: 1)).clipShape(Capsule())
        }.buttonStyle(.plain)
    }
}

/// Velocity / range banner — icon + text + border, never colour alone.
public struct StatusBanner: View {
    public enum Kind { case ok, warn }
    public var kind: Kind, title: String, detail: String
    public init(kind: Kind, title: String, detail: String) {
        self.kind = kind; self.title = title; self.detail = detail
    }
    public var body: some View {
        let c = kind == .ok ? DS.inRange : DS.warn
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: kind == .ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundColor(c)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(DS.ui(12, .semibold)).foregroundColor(c)
                Text(detail).font(DS.number(10)).foregroundColor(DS.ink2)
            }
            Spacer()
        }
        .padding(11)
        .background(kind == .ok ? Color(hex: 0xE8F4F2) : Color(hex: 0xFDEEEB))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(c, lineWidth: kind == .ok ? 1 : 1.5))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

/// Result tile.
public struct ResultTile: View {
    public var label: String, value: String, unit: String
    public init(label: String, value: String, unit: String) {
        self.label = label; self.value = value; self.unit = unit
    }
    public var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(DS.ui(10, .medium)).foregroundColor(DS.ink2)
            NumberReadout(value, unit: unit, size: 17)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background(DS.card)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(DS.border, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}
