import SwiftUI
import MLX
#if os(macOS)
import AppKit
#endif

@main
struct CityPigeonApp: App {

    /// `CITYPIGEON_CPU=1` pins MLX to its CPU stream. The two backends are bit-identical —
    /// `PerfTests.testCPUAndGPUAgreeExactly` diffs a 600-step run and finds no disagreement.
    ///
    /// **It does not make the iOS Simulator work, and it cannot.** That was measured rather than
    /// assumed: both a default launch and a CPU-forced launch abort identically in the simulator,
    /// with this stack —
    ///
    ///     mlx::core::scheduler::scheduler()        ← global singleton, on first touch
    ///       Scheduler::Scheduler()
    ///         Scheduler::new_stream(Device const&)
    ///           mlx::core::gpu::new_stream(Stream) ← creates a GPU stream UNCONDITIONALLY
    ///             mlx::core::metal::Device::Device() → basic_string(nullptr) → abort
    ///
    /// The scheduler builds a GPU stream in its constructor, so the Metal device is created the
    /// first time *any* MLX symbol is entered — including the `Device.setDefault` call below. There
    /// is no ordering that avoids it. The only rule that works on a simulator build is to make no
    /// MLX call at all, which for this app means the simulator is permanently out.
    init() {
        if ProcessInfo.processInfo.environment["CITYPIGEON_CPU"] == "1" {
            Device.setDefault(device: Device(.cpu))
        }
        if ProcessInfo.processInfo.environment["CITYPIGEON_BENCH"] == "1" {
            Benchmark.run()
        }
    }

    var body: some Scene {
        WindowGroup {
            GameScreen()
            #if os(macOS)
                // In demo mode the window is pinned to a known frame so a screen recording lands on
                // the same rectangle every time. Nothing else about the build differs.
                .onAppear {
                    guard Game.demoMode else { return }
                    // Full screen by default, so a recording is the whole display with no window
                    // frame to locate or chase. `CITYPIGEON_DEMO_SIZE=WxH` instead pins a window of
                    // that exact size — used to frame the Mac build at an iPad's 4:3 aspect.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                        NSApp.activate(ignoringOtherApps: true)
                        guard let w = NSApp.windows.first else { return }
                        let env = ProcessInfo.processInfo.environment["CITYPIGEON_DEMO_SIZE"]
                        if let parts = env?.split(separator: "x"), parts.count == 2,
                           let width = Double(parts[0]), let height = Double(parts[1]) {
                            w.setFrame(NSRect(x: 60, y: 60, width: width, height: height),
                                       display: true)
                            w.center()
                        } else if !w.styleMask.contains(.fullScreen) {
                            w.toggleFullScreen(nil)
                        }
                        // Report the content rect in screen-capture coordinates (top-left origin,
                        // points) so a recording can be cropped to exactly this window instead of
                        // being hunted for by pixel colour.
                        if let screen = w.screen ?? NSScreen.main {
                            let c = w.contentRect(forFrameRect: w.frame)
                            let top = screen.frame.maxY - c.maxY
                            print("DEMOFRAME \(Int(c.minX)) \(Int(top)) \(Int(c.width)) \(Int(c.height))")
                            fflush(stdout)
                        }
                    }
                }
            #endif
        }
        #if os(macOS)
        .defaultSize(width: 1280, height: 720)
        .windowResizability(.contentSize)
        #endif
    }
}
