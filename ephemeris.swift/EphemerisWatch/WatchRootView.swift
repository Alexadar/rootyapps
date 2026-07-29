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
    private var now: Date { Date.now.addingTimeInterval(dayOffset * 86_400) }
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
                let forced = ProcessInfo.processInfo.environment["EPHEMERIS_SCREEN"]
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

                            Button { step = step.next } label: {
                                Text(verbatim: step.label)
                                    .font(.system(size: 12)).monospacedDigit()
                            }
                            .buttonStyle(.plain)

                            // Only while scrubbed. A chart showing next month must never be
                            // mistakable for now, so the date appears in amber the moment the
                            // Crown moves — and disappears again to keep the bar clean at rest.
                            if detents != 0 {
                                Text(now, format: .dateTime.day().month(.abbreviated))
                                    .font(.system(size: 12)).foregroundStyle(.orange)
                                Button { detents = 0 } label: {
                                    Image(systemName: "arrow.uturn.backward")
                                        .font(.system(size: 11))
                                }
                                .buttonStyle(.plain).foregroundStyle(.orange)
                            }
                        }
                    }
                }
        }
    }

    /// Crown grain + the scrubbed date. Both live in the header because the wheel itself must stay
    /// uncluttered — it is already carrying twelve layers.
    private var crownControls: some View {
        HStack(spacing: 5) {
            Button { step = step.next } label: {
                Text(verbatim: step.label)
                    .font(.system(size: 11)).monospacedDigit()
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .background(.white.opacity(0.16), in: .capsule)
            }
            .buttonStyle(.plain)

            Text(now, format: step.showsTime
                 ? .dateTime.day().month(.abbreviated).hour().minute()
                 : .dateTime.day().month(.abbreviated))
                .font(.system(size: 11))
                .foregroundStyle(detents == 0 ? AnyShapeStyle(.secondary) : AnyShapeStyle(Color.orange))

            if detents != 0 {
                // One tap back to now — scrubbing all the way back is not an option at 5d/detent.
                Button { detents = 0 } label: { Image(systemName: "arrow.uturn.backward") }
                    .buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(.orange)
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
    }
}
