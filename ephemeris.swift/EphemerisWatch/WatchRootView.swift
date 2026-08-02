import SwiftUI
import EphemerisKit

/// Front door. Opens on whatever was last used, so the wrist lights up already showing something
/// rather than a menu.
///
/// Two states, one at a time — the list, or one screen. See `WatchScreen` for why there is no
/// paging between screens: the Crown belongs to the wheel, and a paging container steals it.
///
/// Everything shown is computed on-device by EphemerisKit. Nothing is fetched. Place, language
/// and house system arrive from the phone over WatchConnectivity, because app groups do not cross
/// the pairing — see `WatchBridge`.
struct WatchRootView: View {
    @AppStorage("eph.watch.lastScreen") private var lastScreenID = WatchScreen.wheel.rawValue
    @State private var screen: WatchScreen?

    /// Crown position in detents; days are derived, so changing the step re-scales the position
    /// instead of teleporting the date.
    ///
    /// `detents` is the raw Crown value and it is deliberately NOT what the chart reads. The Crown
    /// reports in discrete steps, so feeding it straight in makes every glyph jump between
    /// positions — a shake rather than a sweep. `smoothed` chases it, and the wheel follows that.
    @State private var detents: Double = 0
    @State private var smoothed: Double = 0
    /// Drives the chase. A display-linked timer rather than an animation because the Crown can
    /// stop anywhere, and an interrupted implicit animation snaps instead of settling.
    private let tick = Timer.publish(every: 1.0 / 30, on: .main, in: .common).autoconnect()
    @State private var step: ScrubStep = .day
    @FocusState private var crownFocused: Bool

    /// Bumped when the phone's context lands, so the chart redraws with the real place.
    @State private var storeVersion = 0

    private var dayOffset: Double { smoothed * step.daysPerDetent }
    /// EPHEMERIS_DATE pins the base instant so a watch test can assert a known position; without it
    /// every number here moves with the real clock and nothing is assertable. DEBUG-only, so a
    /// shipping build always reads the live sky.
    private var now: Date {
        (LaunchOverride.pinnedDate() ?? .now).addingTimeInterval(dayOffset * 86_400)
    }
    private var location: GeoLocation? { _ = storeVersion; return SharedStore().location }
    private var hasPlace: Bool { location != nil }

    /// Same construction the phone uses — the Kit exposes longitude and daily motion per body and
    /// the caller assembles them.
    private var positions: [BodyPosition] {
        CelestialBody.allCases.map {
            BodyPosition(body: $0,
                         longitude: Ephemeris.longitude(of: $0, at: now),
                         speed: Ephemeris.dailyMotion(of: $0, at: now))
        }
    }

    /// Falls back to Los Angeles only so the wheel has something to draw before the phone has ever
    /// synced. `hasPlace` tells the UI which of the two it is, so nothing ever claims a rising
    /// sign for somewhere the wearer is not.
    private var houses: HouseCusps? {
        Houses.compute(at: now,
                       location: location ?? GeoLocation(latitude: 34.052, longitude: -118.244,
                                                         name: "Los Angeles"),
                       system: SharedStore().houseSystem)
    }

    var body: some View {
        ZStack {
            // One backdrop behind every screen, not per-screen: the star twinkle then continues
            // across a navigation change instead of restarting, and the transition slides the
            // content over a still sky rather than sliding the sky with it.
            NebulaBackground()

            if let screen {
                content(for: screen)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            } else {
                WatchScreenList(screen: $screen)
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }
        }
        .onAppear {
            WatchBridge.shared.start()
            if screen == nil {
                // EPHEMERIS_SCREEN pins the opening screen for screenshot tooling, mirroring the
                // phone's EPHEMERIS_TAB. Without it a capture run would need one build per screen.
                let forced = LaunchOverride.value("EPHEMERIS_SCREEN")
                screen = forced.flatMap(WatchScreen.init(rawValue:))
                       ?? WatchScreen(rawValue: lastScreenID) ?? .wheel
            }
        }
        .onChange(of: screen) { _, new in if let new { lastScreenID = new.rawValue } }
        .onReceive(NotificationCenter.default.publisher(for: .ephemerisSharedStoreChanged)) { _ in
            storeVersion &+= 1
        }
        .onReceive(tick) { _ in
            // Exponential chase: each frame closes a fixed fraction of the remaining gap, so fast
            // spins track closely and a released Crown eases to rest instead of stopping dead.
            // 0.25 at 30fps settles in ~150ms — quick enough to feel direct, slow enough to smooth
            // the detents.
            let gap = detents - smoothed
            if abs(gap) < 0.001 {
                if smoothed != detents { smoothed = detents }
            } else {
                smoothed += gap * 0.25
            }
        }
    }

    @ViewBuilder
    private func content(for s: WatchScreen) -> some View {
        switch s {
        case .wheel:     wheelScreen
        case .now:       wrapped(s) { WatchNowView(date: now, positions: positions,
                                                   houses: houses, hasPlace: hasPlace) }
        case .positions: wrapped(s) { positionsList }
        case .events:    wrapped(s) { WatchEventsView(date: now) }
        }
    }

    /// Every screen gets the same top-bar chrome, so the way back is in one place and no screen
    /// spends body height on a header of its own.
    private func wrapped<C: View>(_ s: WatchScreen, @ViewBuilder _ body: () -> C) -> some View {
        body().watchScreenChrome(s) { withAnimation(.snappy) { screen = nil } }
    }

    /// The wheel gets the whole screen; its controls live in the top bar beside the clock.
    ///
    /// watchOS puts the clock top-right and leaves the left of that bar empty, so `topBarLeading`
    /// (watchOS 10+) reclaims space that was otherwise wasted — and removing the in-body header
    /// row lets the chart centre properly instead of being pushed down.
    ///
    /// `topBarTrailing` is deliberately not used: it is reported to crash at launch on watchOS.
    ///
    /// **Every button in this bar must end with `crownFocused = true`.** `digitalCrownRotation`
    /// only delivers to the view holding focus, and `Button` is focusable, so a tap on the grain
    /// or reset button moves focus off the wheel and the Crown goes dead until the screen is left
    /// and re-entered. `.focusable()` and the `onAppear` claim below are not enough — focus has to
    /// be taken back explicitly after each tap.
    ///
    /// It fails silently in the worst way: nothing crashes, the chart still renders, and the grain
    /// button still visibly changes 6h→1d. Only the scrubbing stops, which reads as "the button
    /// does nothing" — and no iOS or macOS build compiles this target's focus behaviour, so those
    /// builds stay green regardless.
    ///
    /// It is nevertheless a **testable** regression, not a manual check: the Crown is scriptable via
    /// `XCUIDevice.shared.rotateDigitalCrown(delta:)`. See `EphemerisWatchUITests/CrownFocusChecks`,
    /// which scrubs, taps each button here, and scrubs again — the second rotation is the assertion.
    /// Only *rendering* (a complication on a real face) still needs eyes.
    private var wheelScreen: some View {
        NavigationStack {
            WatchWheel(positions: positions,
                       aspects: Aspects.detect(in: positions, orbFactor: 1.0),
                       houses: houses)
                .focusable()
                .focused($crownFocused)
                .digitalCrownRotation($detents,
                                      from: -step.range / step.daysPerDetent,
                                      through: step.range / step.daysPerDetent,
                                      by: 1, sensitivity: .medium,
                                      isContinuous: false, isHapticFeedbackEnabled: true)
                .onAppear { crownFocused = true }
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        HStack(spacing: 5) {
                            Button { withAnimation(.snappy) { screen = nil } } label: {
                                Image(systemName: "list.bullet")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(WatchScreen.wheel.accent)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(Text(L.loc("All screens")))

                            Button { step = step.next; crownFocused = true } label: {
                                Text(verbatim: step.label)
                                    .font(.system(size: 12)).monospacedDigit()
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("watch.grain")

                            // Only while scrubbed. A chart showing next month must never be
                            // mistakable for now, so the date appears in amber the moment the
                            // Crown moves — and disappears again to keep the bar clean at rest.
                            //
                            // Its presence-then-value is also what the crown regression test reads:
                            // it appears only once the Crown has moved, so it doubles as proof the
                            // Crown is alive.
                            if detents != 0 {
                                Text(now, format: .dateTime.day().month(.abbreviated))
                                    .font(.system(size: 12)).foregroundStyle(.orange)
                                    .accessibilityIdentifier("watch.scrubDate")
                                Button { detents = 0; crownFocused = true } label: {
                                    Image(systemName: "arrow.uturn.backward")
                                        .font(.system(size: 11))
                                }
                                .buttonStyle(.plain).foregroundStyle(.orange)
                                .accessibilityIdentifier("watch.reset")
                            }
                        }
                    }
                }
        }
    }

    private var positionsList: some View {
        List {
            ForEach(positions) { p in
                LabeledRow(glyph: p.body.glyph,
                           label: L.loc(p.body.name),
                           value: Format.degMin(p.longitude))
                    .foregroundStyle(p.retrograde ? Color.orange : Color.primary)
            }
        }
        .scrollContentBackground(.hidden)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("watch.positions")
    }
}
