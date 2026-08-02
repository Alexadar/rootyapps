import Foundation
import SwiftUI
import StatKit

/// One- and two-variable statistics, and the four regression models.
///
/// The data entry list is the screen: a fit is only as good as the points behind it, so they stay
/// visible and editable rather than living in hidden registers.
@MainActor
public final class StatisticsViewModel: ObservableObject {

    public struct Point: Identifiable, Equatable {
        public let id = UUID()
        public var x: Double
        public var y: Double
        public init(x: Double, y: Double) {
            self.x = x
            self.y = y
        }
    }

    @Published public var points: [Point] = [
        .init(x: 1, y: 100_000), .init(x: 2, y: 112_000), .init(x: 3, y: 125_440),
        .init(x: 4, y: 140_493), .init(x: 5, y: 157_352),
    ]
    @Published public var model: Stat.Model = .linear
    @Published public var forecastX: Double = 6
    @Published public var rowLabel: String = ""

    public init() {}

    public static let valueRange: ClosedRange<Double> = -1_000_000_000...1_000_000_000

    public var xs: [Double] { points.map(\.x) }
    public var ys: [Double] { points.map(\.y) }

    public var summaryX: Stat.Summary? { points.isEmpty ? nil : Stat.summary(xs) }
    public var summaryY: Stat.Summary? { points.isEmpty ? nil : Stat.summary(ys) }

    public enum Outcome: Equatable {
        case fitted(Stat.Fit)
        case failed(String)
    }

    public var outcome: Outcome {
        do {
            return .fitted(try Stat.fit(x: xs, y: ys, model: model))
        } catch let error as Stat.FitError {
            return .failed(error.description)
        } catch {
            return .failed("These points do not support a fit.")
        }
    }

    public var forecast: Double? {
        guard case .fitted(let fit) = outcome else { return nil }
        // The logarithmic and power models need x > 0; the Kit would trap on a bad probe.
        if fit.model.requiresPositive.x && forecastX <= 0 { return nil }
        return Stat.forecastY(x: forecastX, fit: fit)
    }

    public func addPoint() {
        let nextX = (points.map(\.x).max() ?? 0) + 1
        points.append(Point(x: nextX, y: points.last?.y ?? 0))
    }

    public func removePoints(at offsets: IndexSet) {
        points.remove(atOffsets: offsets)
    }

    public var authorities: [String] { ["NIST/ITL StRD certified values"] }

    public var conventions: [String] {
        var items = [model.displayName, "sample s.d. divides by n − 1"]
        if model.requiresPositive.x || model.requiresPositive.y {
            items.append("requires positive "
                         + (model.requiresPositive.x && model.requiresPositive.y ? "x and y"
                            : (model.requiresPositive.x ? "x" : "y")))
        }
        items.append("Welford — not Σx² − nx̄²")
        return items
    }

    public func tapeRow() -> TapeRow? {
        guard case .fitted = outcome else { return nil }
        return TapeRow(label: rowLabel, inputs: .statistics(StatInputs(
            xs: xs, ys: ys, modelRawValue: model.rawValue, forecastX: forecastX
        )))
    }
}
