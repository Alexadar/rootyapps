import Foundation

/// Turning a tape into something a client can be handed.
///
/// _"Calculator Pro is a great app but I would give much to have a calculator from which I could
/// print the tape."_ — the most explicit unmet ask in this category (`plan_tape.md` §2). So print
/// and export are first-class, and they go through `TapeSolver` like everything else: the printed
/// sheet and the screen cannot disagree, because they are the same computation.
public enum TapeExport {

    // MARK: - One line

    /// The inputs of a row, collapsed to one readable line. Also what gets written into the file as
    /// `rawSummary`, so a line that later fails to decode still has a human description.
    public static func summary(of row: TapeRow) -> String {
        switch row.inputs {
        case .tvm(let i):
            return "n \(Fmt.count(i.periods)) · i \(Fmt.money(i.annualRatePct, digits: 3))% · "
                + "PV \(Fmt.money(i.presentValue, digits: 0)) · PMT \(Fmt.money(i.payment, digits: 0)) · "
                + "FV \(Fmt.money(i.futureValue, digits: 0)) · solve \(i.solveFor)"
        case .amortization(let i):
            return "PV \(Fmt.money(i.principal, digits: 0)) · i \(Fmt.money(i.annualRatePct, digits: 3))% · "
                + "n \(i.periods) · \(i.periodsPerYear)/yr"
                + (i.balloon > 0 ? " · balloon \(Fmt.money(i.balloon, digits: 0))" : "")
        case .cashFlow(let i):
            // The result column carries the IRR, which owes nothing to the discount rate. Leading
            // with a bare "rate 8%" invites a reader to take it as the basis of the number beside
            // it, so the rate is labelled for what it is: the rate the NPV would be taken at.
            let flows = i.groups.map { "\(Fmt.money($0.amount, digits: 0))×\($0.count)" }
            return flows.joined(separator: " · ")
                + " · NPV rate \(Fmt.money(i.discountRatePct, digits: 3))%"
        case .bond(let i):
            return "price \(Fmt.price(i.price, digits: 3)) · coupon \(Fmt.money(i.couponPct, digits: 3))% · "
                + "n \(i.fullPeriods) · r/s \(i.daysToNextCoupon)/\(i.daysInPeriod) · "
                + i.firstPeriodRawValue
        case .rate(let i):
            switch i.mode {
            case "apy":
                return "interest \(Fmt.money(i.interest)) on \(Fmt.money(i.principal, digits: 0)) · "
                    + "\(Fmt.count(i.daysInTerm)) days"
            case "convert":
                return "nominal \(Fmt.money(i.nominalPct, digits: 3))% · \(i.timesPerYear)× per year"
            default:
                return "advance \(Fmt.money(i.advance, digits: 0)) · \(i.paymentCount) × "
                    + "\(Fmt.money(i.payment)) · \(Fmt.count(i.unitPeriodsPerYear))/yr"
            }
        case .depreciation(let i):
            return "cost \(Fmt.money(i.cost, digits: 0)) · \(i.recoveryYears)-year · "
                + "\(i.methodRawValue) · \(i.conventionRawValue)"
        case .dayCount(let i):
            return "\(formatted(encodedDate: i.start)) → \(formatted(encodedDate: i.end)) · "
                + i.conventionRawValue
        case .percent(let i):
            return i.mode == "breakEven"
                ? "fixed \(Fmt.money(i.fixedCosts, digits: 0)) · price \(Fmt.money(i.price)) · "
                    + "variable \(Fmt.money(i.variableCostPerUnit))"
                : "cost \(Fmt.money(i.cost)) · price \(Fmt.money(i.price))"
        case .statistics(let i):
            return "\(i.xs.count) points · \(i.modelRawValue) · forecast at \(Fmt.count(i.forecastX))"
        case .realEstate(let i):
            return "GPR \(Fmt.money(i.grossPotentialRent, digits: 0)) · vacancy "
                + "\(Fmt.money(i.vacancyPct, digits: 1))% · OpEx \(Fmt.money(i.operatingExpenses, digits: 0)) · "
                + "DSCR \(Fmt.money(i.targetDSCR, digits: 2))"
        case .damaged(let d):
            return d.rawSummary.isEmpty ? "unreadable line" : d.rawSummary
        }
    }

    public static func formatted(encodedDate: Int) -> String {
        String(format: "%04d-%02d-%02d", encodedDate / 10_000, (encodedDate / 100) % 100, encodedDate % 100)
    }

    // MARK: - Whole tape

    /// Plain text, laid out the way the tape reads on screen.
    public static func plainText(_ document: TapeDocument) -> String {
        var lines = [document.title, String(repeating: "─", count: max(document.title.count, 12)), ""]
        for (index, row) in document.rows.enumerated() {
            let result = TapeSolver.result(for: row.inputs)
            let label = row.label.isEmpty ? "—" : row.label
            lines.append("\(index + 1). \(row.inputs.toolName) · \(label)")
            lines.append("   \(summary(of: row))")
            lines.append("   → \(result.name)  \(result.formatted)")
            if case .unavailable(_, let reason) = result { lines.append("   (\(reason))") }
            lines.append("")
        }
        lines.append("\(document.rows.count) line\(document.rows.count == 1 ? "" : "s") · "
                     + "results re-derived from the stored inputs")
        return lines.joined(separator: "\n")
    }

    /// CSV, for the spreadsheet the tape is handed off to.
    public static func csv(_ document: TapeDocument) -> String {
        var rows = ["line,tool,label,inputs,result name,result,note"]
        for (index, row) in document.rows.enumerated() {
            let result = TapeSolver.result(for: row.inputs)
            var note = ""
            if case .unavailable(_, let reason) = result { note = reason }
            rows.append([
                String(index + 1), row.inputs.toolName, row.label, summary(of: row),
                result.name, result.formatted, note,
            ].map(escaped).joined(separator: ","))
        }
        return rows.joined(separator: "\n")
    }

    /// An amortization schedule as CSV — the table a borrower actually asks for.
    public static func csv(schedule: [ScheduleLine], title: String) -> String {
        var rows = ["# \(title)", "period,payment,interest,principal,balance"]
        for line in schedule {
            rows.append([
                String(line.period), line.payment, line.interest, line.principal, line.balance,
            ].map(escaped).joined(separator: ","))
        }
        return rows.joined(separator: "\n")
    }

    /// A pre-formatted schedule row, so the exporter never has to know which Kit produced it.
    public struct ScheduleLine {
        public let period: Int
        public let payment: String
        public let interest: String
        public let principal: String
        public let balance: String

        public init(period: Int, payment: String, interest: String, principal: String, balance: String) {
            self.period = period
            self.payment = payment
            self.interest = interest
            self.principal = principal
            self.balance = balance
        }
    }

    private static func escaped(_ field: String) -> String {
        guard field.contains(",") || field.contains("\"") || field.contains("\n") else { return field }
        return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}
