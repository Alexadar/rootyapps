import XCTest
import Darwin

/// Timing assertions must not fail because another process is busy.
///
/// A full suite went red here with two failures and no engine change: ten peer sessions were
/// compiling and the one-minute load average was 28. Every failure was a threshold in a *timing*
/// test. A correctness suite that turns red when a neighbour builds is a suite people stop reading,
/// and the fix is not a looser threshold — it is to decline to measure at all.
enum MachineLoad {

    static var oneMinute: Double {
        var v = [Double](repeating: 0, count: 3)
        getloadavg(&v, 3)
        return v[0]
    }

    /// Skip — not fail — when the machine is too busy for a timing number to mean anything.
    static func skipIfBusy(_ threshold: Double = 4.0,
                           file: StaticString = #filePath, line: UInt = #line) throws {
        let load = oneMinute
        if load > threshold {
            throw XCTSkip("machine load \(String(format: "%.1f", load)) exceeds \(threshold) — a "
                          + "timing measurement here would be measuring the neighbours. Real numbers "
                          + "come from the Release benchmark: CITYPIGEON_BENCH=1", file: file, line: line)
        }
    }
}
