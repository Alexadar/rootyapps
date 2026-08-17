import Foundation
import MLX

/// Step cost, measured **in the shipping configuration**.
///
/// Deliberately **outside `Engine/`**, and the engine's own guards are what put it here. Placed in
/// `Engine/` it failed `testEveryEngineLoopIsJustified` and `testTheEngineNeverReadsAClock` on the
/// first run — a benchmark is a clock-reading loop by definition, and neither is allowed in a
/// deterministic engine whose time comes from a frame counter. The right response to that was not
/// an allowlist entry; it was to accept that measurement apparatus is not engine code.
///
/// It exists because the test suite cannot measure this. `@testable import` requires
/// `ENABLE_TESTABILITY`, which is Debug-only, so the whole test target — and with it the app module
/// and MLX's C++ — builds unoptimised. Every number the perf tests report is therefore a Debug
/// number, and a Debug build of a template-heavy C++ array library is not slow by a constant factor.
///
/// It runs inside the real Release app, driven by `CITYPIGEON_BENCH=1`, printing to stdout before
/// any window appears. The same binary runs on a phone, which is the measurement that actually
/// decides whether the frame budget holds.
public enum Benchmark {

    /// Repeats per case. A single timing is a sample, not a measurement, and reporting one as
    /// though it were a measurement is how "5.6x" and "2.7 ms" both acquired precision nobody had
    /// established. Five repeats is enough to show the spread; the spread is the point.
    private static let repeats = 5

    public static func run() -> Never {
        let config = WorldConfig.shipping
        let frame = config.dt * 1000

        print("── City Pigeon step cost ─────────────────────────────")
        print(String(format: "build      %@", isDebug ? "DEBUG (not representative)" : "RELEASE"))
        print("device     \(Device.defaultDevice())")
        print(String(format: "frame      %.2f ms at %.0f Hz · %d repeats per case",
                     frame, 1 / config.dt, repeats))
        // Print the one thing that most easily invalidates everything below.
        //
        // The first five-repeat run was taken while a full test suite was compiling in the
        // background at load average 19, and reported a 90% spread on B=1 against 5% on the batched
        // cases — small measurements are pushed around by contention, large ones average over it.
        // The numbers were meaningless and nothing in the output said so. Now it does.
        var load = [Double](repeating: 0, count: 3)
        getloadavg(&load, 3)
        let busy = load[0] > 3.0
        print(String(format: "load       %.2f %.2f %.2f%@", load[0], load[1], load[2],
                     busy ? "   ⚠️ MACHINE IS BUSY — these numbers are not trustworthy" : ""))

        // ONE global warm-up across every case that will be timed.
        //
        // Per-case warm-up is not enough and the first version proved it: plain B=1 came out at
        // 2.42 ms while B=1-plus-autopilot, measured last, came out at 1.64 ms — lower, for strictly
        // more work. MLX compiles kernels and grows its pool lazily, so whichever case runs first
        // pays for all of them. An ordering artefact that makes results self-contradictory is the
        // one kind you can see; the kind that shifts everything uniformly is not.
        for warmBatch in [1, 64, 1024] {
            var w = World(batch: warmBatch, config: config, seed: 3)
            let idle = Intent.idle(batch: warmBatch)
            for _ in 0..<80 { Step.advance(&w, intent: idle) }
            if warmBatch == 1 { for _ in 0..<80 { Step.advance(&w, intent: Policy.autopilot(w)) } }
        }

        for batch in [1, 64, 1024] {
            let iterations = batch == 1 ? 400 : 60
            report("step B=\(batch)", frame: batch == 1 ? frame : nil,
                   samples: (0..<repeats).map { _ in
                       var world = World(batch: batch, config: config, seed: 7)
                       let idle = Intent.idle(batch: batch)
                       let t0 = Date()
                       for _ in 0..<iterations { Step.advance(&world, intent: idle) }
                       return Date().timeIntervalSince(t0) / Double(iterations) * 1000
                   })
        }

        report("step B=1 + autopilot", frame: frame, samples: (0..<repeats).map { _ in
            var world = World(batch: 1, config: config, seed: 7)
            let t0 = Date()
            for _ in 0..<400 { Step.advance(&world, intent: Policy.autopilot(world)) }
            return Date().timeIntervalSince(t0) / 400 * 1000
        })
        print("──────────────────────────────────────────────────────")
        exit(0)
    }

    /// Print min, median and max — never a lone mean. The spread is what tells you whether the
    /// number can be quoted to the precision it appears to have.
    private static func report(_ label: String, frame: Double?, samples: [Double]) {
        let s = samples.sorted()
        let lo = s.first!, hi = s.last!, mid = s[s.count / 2]
        let spread = (hi - lo) / mid * 100
        var line = String(format: "%-22@ %6.3f  median %6.3f  %6.3f ms   spread %4.0f%%",
                          label as NSString, lo, mid, hi, spread)
        if let frame { line += String(format: "  (%.0f–%.0f%% of a frame)", lo / frame * 100, hi / frame * 100) }
        print(line)
    }

    private static var isDebug: Bool {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }
}
