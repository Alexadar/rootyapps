import SwiftUI
import DayCountKit

/// Dates and day counts. The comparison table *is* the screen: the same two dates counted six ways,
/// because the convention is worth real money and is normally invisible.
public struct DayCountScreen: View {
    @StateObject private var model = DayCountViewModel()
    @Binding private var document: TapeDocument

    public init(document: Binding<TapeDocument>) {
        self._document = document
    }

    /// Actual/Actual (ICMA) measures against the coupon period, so the year fraction is meaningless
    /// without knowing how many there are in a year. It used to be fixed at two and said so nowhere.
    private var couponFrequency: some View {
        SettingCard("periods / yr", value: String(model.periodsPerYear),
                    identifier: "daycount.periodsPerYear",
                    spoken: "coupon periods per year, \(model.periodsPerYear)") {
            Frequency.picker("periods / yr", selection: $model.periodsPerYear)
        }
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                dates
                couponFrequency
                hero
                substitution
                comparison
                AppendToTapeBar(label: $model.rowLabel, canAppend: model.tapeRow() != nil,
                                identifier: "daycount.tape") { append() }
                ProvenanceStrip(authorities: model.authorities, conventions: model.conventions,
                                identifier: "daycount.provenance")
            }
            .padding(.horizontal, Par.Metrics.gutter)
            .padding(.bottom, 12)
        }
        .background(Par.Palette.base)
        .navigationTitle("Dates & Day Count")
    }

    private var dates: some View {
        VStack(spacing: 0) {
            DateField(title: "from", date: $model.start, identifier: "daycount.input.start")
            Divider().overlay(Par.Palette.separator)
            DateField(title: "to", date: $model.end, identifier: "daycount.input.end")
            Divider().overlay(Par.Palette.separator)
            Picker("Convention", selection: $model.convention) {
                ForEach(DayCount.Convention.allCases, id: \.self) { convention in
                    Text(convention.displayName).tag(convention)
                }
            }
            .pickerStyle(.menu)
            .tint(Par.Palette.accent)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: Par.Metrics.minHitTarget, alignment: .leading)
            .accessibilityIdentifier("daycount.convention")

            if model.convention == .thirtyE360ISDA {
                Divider().overlay(Par.Palette.separator)
                Toggle(isOn: $model.usesTerminationDate) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("end date is the termination date").font(.subheadline)
                        Text("§4.16(h) keeps 28 February as 28 on the termination date")
                            .font(.caption2).foregroundStyle(Par.Palette.labelTertiary)
                    }
                }
                .tint(Par.Palette.accent)
                .padding(.horizontal, 12)
                .frame(minHeight: Par.Metrics.minHitTarget)
                .accessibilityIdentifier("daycount.terminationDate")
            }
        }
        .glassCard()
    }

    @ViewBuilder
    private var hero: some View {
        if model.isReversed {
            FailureNotice(
                title: "The second date is before the first",
                detail: "A day count runs forward. Swap the dates, or the answer is a negative "
                    + "number that no convention defines.",
                technical: "end < start · nothing was appended to the tape",
                identifier: "daycount.hero.failure",
                isWarning: true
            )
        } else {
            HeroResult(caption: "days · \(model.convention.displayName)",
                       value: "\(model.days)",
                       footnote: "\(model.actualDays) actual · year fraction "
                           + Fmt.count(model.yearFraction * 1000) + " ⁄ 1000",
                       identifier: "daycount.hero",
                       spoken: "\(model.days) days under \(model.convention.displayName)")
        }
    }

    @ViewBuilder
    private var substitution: some View {
        if let substitution = model.substitution {
            VStack(spacing: 0) {
                ResultRow("D₁ · start day used", value: "\(substitution.d1)",
                          identifier: "daycount.d1",
                          spoken: "start day counted as \(substitution.d1)")
                Divider().overlay(Par.Palette.separator)
                ResultRow("D₂ · end day used", value: "\(substitution.d2)",
                          identifier: "daycount.d2",
                          spoken: "end day counted as \(substitution.d2)")
            }
            .glassCard()
        }
    }

    private var comparison: some View {
        VStack(spacing: 0) {
            HStack {
                Text("every convention, same two dates")
                    .font(.caption2).foregroundStyle(Par.Palette.labelTertiary)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            Divider().overlay(Par.Palette.separator)

            ForEach(model.allConventions, id: \.convention) { entry in
                HStack {
                    Text(entry.convention.displayName)
                        .font(.caption)
                        .foregroundStyle(entry.convention == model.convention
                                         ? Par.Palette.label : Par.Palette.labelSecondary)
                    Spacer()
                    Text("\(entry.days)")
                        .font(.caption.monospacedDigit()
                            .weight(entry.convention == model.convention ? .semibold : .regular))
                        .foregroundStyle(entry.convention == model.convention
                                         ? Par.Palette.accent : Par.Palette.labelSecondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("daycount.compare.\(entry.convention.rawValue)")
                Divider().overlay(Par.Palette.separator)
            }
        }
        .glassCard()
    }

    private func append() {
        if let row = model.tapeRow() { document.append(row) }
    }
}

/// A calendar date with no time zone attached — which is what a settlement date is.
struct DateField: View {
    let title: String
    @Binding var date: DayCount.YearMonthDay
    let identifier: String

    var body: some View {
        DatePicker(
            title,
            selection: Binding(
                get: {
                    var components = DateComponents()
                    components.year = date.year
                    components.month = date.month
                    components.day = date.day
                    var calendar = Calendar(identifier: .gregorian)
                    calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
                    return calendar.date(from: components) ?? Date()
                },
                set: { newValue in
                    var calendar = Calendar(identifier: .gregorian)
                    calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
                    let parts = calendar.dateComponents([.year, .month, .day], from: newValue)
                    if let year = parts.year, let month = parts.month, let day = parts.day {
                        date = DayCount.YearMonthDay(year, month, day)
                    }
                }
            ),
            displayedComponents: .date
        )
        .datePickerStyle(.compact)
        .tint(Par.Palette.accent)
        .padding(.horizontal, 12)
        .frame(minHeight: Par.Metrics.minHitTarget)
        .accessibilityIdentifier(identifier)
    }
}

#Preview("Day count — dark") {
    NavigationStack { DayCountScreen(document: .constant(TapeDocument())) }.parAppearance()
}

#Preview("Day count — AX5") {
    NavigationStack { DayCountScreen(document: .constant(TapeDocument())) }
        .environment(\.dynamicTypeSize, .accessibility5)
        .parAppearance()
}
