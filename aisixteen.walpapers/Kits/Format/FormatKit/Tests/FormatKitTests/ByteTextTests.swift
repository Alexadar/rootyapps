import Testing
import Foundation
@testable import FormatKit

/// ORACLES:
///  • SPEC — the design bundle fixes the literal strings "1.1 of 2.6 GB", "Wi‑Fi · 4.6 MB/s" and
///    "Step 9 of 28". Those are the oracle; this suite pins them and their boundaries.
///  • CONVENTION — decimal units (1 GB = 1000 MB), matching how the App Store states download
///    sizes. A binary-unit "2.4 GiB" beside a store listing that says 2.6 GB reads as a bug.
///  • INVARIANT — a progress string never states two numbers in different units, and never shows
///    more completed than total.
/// MODEL CAVEAT: these are display strings for English. Localisation would replace the whole type,
/// not tune it.
@Suite("ByteText — the strings the bundle fixes")
struct ByteTextTests {

    @Test("the bundle's own example renders verbatim")
    func bundleExample() {
        // 1.1 GB of a 2.6 GB model, in decimal units.
        #expect(ByteText.progress(completed: 1_100_000_000, total: 2_600_000_000) == "1.1 of 2.6 GB")
        #expect(ByteText.rate(bytesPerSecond: 4_600_000) == "4.6 MB/s")
        #expect(ByteText.step(9, of: 28) == "Step 9 of 28")
        #expect(ByteText.size(2_600_000_000) == "2.6 GB")
    }

    @Test("both halves of a progress string always share one unit")
    func progressSharesUnit() {
        // The trap: formatting each side independently prints "999.6 MB of 1.0 GB".
        let text = ByteText.progress(completed: 999_600_000, total: 1_000_000_000)
        #expect(text == "1.0 of 1.0 GB", "got \(text)")
        #expect(!text.contains("MB"))
    }

    @Test("a sub-gigabyte total is stated in megabytes on both sides")
    func megabyteTotal() {
        #expect(ByteText.progress(completed: 20_000_000, total: 200_000_000) == "20.0 of 200.0 MB")
    }

    @Test("completed never exceeds total, whatever the caller passes")
    func clampsOvershoot() {
        let text = ByteText.progress(completed: 5_000_000_000, total: 2_600_000_000)
        #expect(text == "2.6 of 2.6 GB", "got \(text)")
    }

    @Test("zero and negative inputs do not produce nonsense")
    func degenerateInputs() {
        #expect(ByteText.size(0) == "0 B")
        #expect(ByteText.size(-1) == "0 B")
        #expect(ByteText.progress(completed: 0, total: 0) == "0 B")
        #expect(ByteText.progress(completed: -10, total: 1_000_000_000) == "0.0 of 1.0 GB")
    }

    @Test("unit boundaries round the way a reader expects")
    func boundaries() {
        #expect(ByteText.size(999) == "999 B")
        #expect(ByteText.size(1_000) == "1 KB")
        #expect(ByteText.size(999_000) == "999 KB")
        #expect(ByteText.size(1_000_000) == "1.0 MB")
        #expect(ByteText.size(999_000_000) == "999.0 MB")
        #expect(ByteText.size(1_000_000_000) == "1.0 GB")
    }

    @Test("no rate is reported until there is a real measurement")
    func rateRequiresData() {
        #expect(ByteText.rate(bytesPerSecond: nil) == nil)
        #expect(ByteText.rate(bytesPerSecond: 0) == nil)
        #expect(ByteText.rate(bytesPerSecond: -5) == nil)
        #expect(ByteText.rate(bytesPerSecond: .infinity) == nil)
        #expect(ByteText.rate(bytesPerSecond: .nan) == nil)
    }

    @Test("the ETA is a phrase, never a countdown, and is silent when unknown")
    func remainingPhrase() {
        #expect(ByteText.remainingPhrase(bytesRemaining: 1_000_000, bytesPerSecond: nil) == nil)
        #expect(ByteText.remainingPhrase(bytesRemaining: 0, bytesPerSecond: 4_600_000) == nil)
        #expect(ByteText.remainingPhrase(bytesRemaining: 10_000_000, bytesPerSecond: 4_600_000) == "Less than a minute")
        #expect(ByteText.remainingPhrase(bytesRemaining: 300_000_000, bytesPerSecond: 4_600_000) == "About a minute")
        // 1.5 GB left at 4.6 MB/s ≈ 326 s ≈ five minutes — the bundle's "About four minutes" shape.
        #expect(ByteText.remainingPhrase(bytesRemaining: 1_500_000_000, bytesPerSecond: 4_600_000) == "About five minutes")
        #expect(ByteText.remainingPhrase(bytesRemaining: 2_600_000_000, bytesPerSecond: 400_000) == "About an hour")
        #expect(ByteText.remainingPhrase(bytesRemaining: 2_600_000_000, bytesPerSecond: 100_000) == "Over an hour")
    }

    @Test("the gallery caption counts in words a human would use")
    func wallpaperCount() {
        #expect(ByteText.wallpaperCount(0) == "No wallpapers yet")
        #expect(ByteText.wallpaperCount(1) == "1 wallpaper")
        #expect(ByteText.wallpaperCount(12) == "12 wallpapers")
    }
}
