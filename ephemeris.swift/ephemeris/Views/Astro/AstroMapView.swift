import SwiftUI
import EphemerisKit

/// The world map with a chart's planetary lines on it — the app's only non-wheel view.
///
/// Four lines per body: MC and IC are meridians (vertical), AC and DC are curves solved per
/// latitude. `AstroCartography` computes all of it; this draws it and answers "how far from me".
///
/// ⚠️ **Circumpolar lines are absent, never clipped.** When a body never touches the horizon at a
/// latitude there is no AC or DC there, and `AstroCartography.line` returns no points for it. The
/// honest rendering is to omit the line and say so in the list. Clipping it to the map edge would
/// draw a boundary that exists nowhere and invite someone to move to it.
struct AstroMapView: View {
    let chart: SavedChart
    let observer: GeoLocation?

    @State private var bodies: Set<CelestialBody> = Set(CelestialBody.allCases.prefix(7))
    @State private var angles: Set<AstroCartoAngle> = Set(AstroCartoAngle.allCases)
    @State private var zoom: CGFloat = 1
    @State private var pan: CGSize = .zero
    /// The map's rendered size, captured so a gesture that ends outside the `GeometryReader` can
    /// still clamp against it.
    @State private var mapSize: CGSize = .zero
    @GestureState private var livePan: CGSize = .zero
    @GestureState private var liveZoom: CGFloat = 1

    private var lines: [AstroCartoLine] {
        AstroCartography.lines(at: chart.birthInstant,
                               bodies: CelestialBody.allCases.filter(bodies.contains),
                               angles: Array(angles))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            map
            filters
            if let observer { nearYou(observer) }
            legend
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("chart.astrocartography")
    }

    // MARK: - Map

    private var map: some View {
        GeometryReader { geo in
            let rect = CGRect(origin: .zero, size: geo.size)
            Canvas { ctx, _ in
                CoastlineAtlas.draw(in: ctx, rect: rect)
                drawGraticule(ctx, rect)
                for line in lines { draw(line, ctx, rect) }
                if let observer { drawObserver(observer, ctx, rect) }
            }
            .scaleEffect(zoom * liveZoom)
            // Clamped, not free. An unbounded offset lets a drag push the map entirely out of the
            // frame with no gesture that brings it back — and at zoom 1 there is nothing to pan to
            // at all, so any movement is pure loss.
            .offset(clamp(pan + livePan, in: geo.size, zoom: zoom * liveZoom))
            .clipped()
            .onAppear { mapSize = geo.size }
            .onChange(of: geo.size) { _, new in mapSize = new }
        }
        .aspectRatio(2, contentMode: .fit)   // equirectangular is exactly 2:1
        .background(Color(rgbHex: 0x080418), in: .rect(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(NebulaPalette.ring, lineWidth: 0.5))
        .gesture(
            SimultaneousGesture(
                // Clamped on END as well as on render. `@GestureState` has already reset to zero
                // by the time `onEnded` runs, so the translation must come from the value — and
                // storing an unclamped sum would leave the user dragging back the same distance
                // before the map moved again.
                DragGesture().updating($livePan) { v, s, _ in s = v.translation }
                    .onEnded { pan = clamp(pan + $0.translation, in: mapSize, zoom: zoom) },
                MagnificationGesture().updating($liveZoom) { v, s, _ in s = v }
                    .onEnded {
                        zoom = min(max(zoom * $0, 1), 8)
                        // Zooming out shrinks the allowed overflow, so a pan that was legal at 4x
                        // is not at 1x — re-clamp or the map stays parked off-centre.
                        pan = clamp(pan, in: mapSize, zoom: zoom)
                    }
            )
        )
        .accessibilityIdentifier("astro.map")
    }

    /// How far the scaled content may be moved before its edge enters the frame.
    ///
    /// At scale `z` the content is `z` times the frame, so the overflow is `(z − 1) / 2` of the
    /// frame in each direction. At `z == 1` that is zero: the map exactly fills its rect and
    /// panning is meaningless.
    private func clamp(_ offset: CGSize, in size: CGSize, zoom z: CGFloat) -> CGSize {
        let limitX = max(0, (z - 1) / 2 * size.width)
        let limitY = max(0, (z - 1) / 2 * size.height)
        return CGSize(width: min(max(offset.width, -limitX), limitX),
                      height: min(max(offset.height, -limitY), limitY))
    }

    private func drawGraticule(_ ctx: GraphicsContext, _ rect: CGRect) {
        var grid = Path()
        for lon in stride(from: -180.0, through: 180.0, by: 30) {
            let x = MapProjection.place(MapProjection.unitPoint(latitude: 0, longitude: lon), in: rect).x
            grid.move(to: CGPoint(x: x, y: rect.minY)); grid.addLine(to: CGPoint(x: x, y: rect.maxY))
        }
        for lat in stride(from: -60.0, through: 60.0, by: 30) {
            let y = MapProjection.place(MapProjection.unitPoint(latitude: lat, longitude: 0), in: rect).y
            grid.move(to: CGPoint(x: rect.minX, y: y)); grid.addLine(to: CGPoint(x: rect.maxX, y: y))
        }
        ctx.stroke(grid, with: .color(NebulaPalette.ring.opacity(0.25)), lineWidth: 0.5)
    }

    private func draw(_ line: AstroCartoLine, _ ctx: GraphicsContext, _ rect: CGRect) {
        // No points at all = circumpolar. Draw nothing; the list explains it.
        guard !line.isEmpty else { return }
        let runs = MapProjection.segments(line.points.map { ($0.latitude, $0.longitude) })
        var path = Path()
        for run in runs {
            guard let first = run.first else { continue }
            path.move(to: MapProjection.place(first, in: rect))
            for p in run.dropFirst() { path.addLine(to: MapProjection.place(p, in: rect)) }
        }
        ctx.stroke(path,
                   with: .color(colour(line.body)),
                   style: StrokeStyle(lineWidth: 1.2, dash: dash(line.angle)))
    }

    private func drawObserver(_ o: GeoLocation, _ ctx: GraphicsContext, _ rect: CGRect) {
        let p = MapProjection.place(MapProjection.unitPoint(latitude: o.latitude,
                                                            longitude: o.longitude), in: rect)
        ctx.fill(Path(ellipseIn: CGRect(x: p.x - 3, y: p.y - 3, width: 6, height: 6)),
                 with: .color(NebulaPalette.accent))
    }

    /// A stable colour per body.
    ///
    /// Indexed by position in `allCases`, NOT derived from the name's `hashValue`: Swift seeds
    /// `String.hashValue` randomly **per process**, so a hash-based palette would repaint every
    /// line a different colour on every launch and look like a rendering bug.
    private func colour(_ body: CelestialBody) -> Color {
        let palette: [Color] = [
            Color(rgbHex: 0xFFD166),   // Sun
            Color(rgbHex: 0xECE6FF),   // Moon
            Color(rgbHex: 0x35E7FF),   // Mercury
            Color(rgbHex: 0xFF8FC7),   // Venus
            Color(rgbHex: 0xFF5C5C),   // Mars
            Color(rgbHex: 0xC061FF),   // Jupiter
            Color(rgbHex: 0x9AA6C4),   // Saturn
            Color(rgbHex: 0x4DF0A0),   // Uranus
            Color(rgbHex: 0x5C8BFF),   // Neptune
            Color(rgbHex: 0xB08D6A),   // Pluto
        ]
        let i = CelestialBody.allCases.firstIndex(of: body) ?? 0
        return palette[i % palette.count]
    }

    /// MC/IC solid and dotted; AC/DC dashed — so a printed or colour-blind reading still separates
    /// the meridians from the horizon curves.
    private func dash(_ angle: AstroCartoAngle) -> [CGFloat] {
        switch angle {
        case .midheaven:  []
        case .imumCoeli:  [1, 3]
        case .ascendant:  [5, 3]
        case .descendant: [2, 2]
        }
    }

    // MARK: - Filters

    private var filters: some View {
        VStack(alignment: .leading, spacing: 8) {
            CardHeader(title: "Bodies")
            chipRow(CelestialBody.allCases, selected: bodies) { b in
                if bodies.contains(b) { bodies.remove(b) } else { bodies.insert(b) }
            } label: { $0.glyph + "\u{FE0E}" }

            CardHeader(title: "Angles")
            chipRow(AstroCartoAngle.allCases, selected: angles) { a in
                if angles.contains(a) { angles.remove(a) } else { angles.insert(a) }
            } label: { $0.abbreviation }
        }
        .glassCard()
    }

    private func chipRow<T: Hashable>(_ items: [T], selected: Set<T>,
                                      toggle: @escaping (T) -> Void,
                                      label: @escaping (T) -> String) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(items, id: \.self) { item in
                    Button { toggle(item) } label: {
                        Text(verbatim: label(item))
                            .font(.caption)
                            .padding(.horizontal, 9).padding(.vertical, 5)
                            .background(selected.contains(item)
                                        ? NebulaPalette.accent.opacity(0.85)
                                        : NebulaPalette.cardFill,
                                        in: .capsule)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Near you

    private func nearYou(_ observer: GeoLocation) -> some View {
        let ranked = NearestLines.ranked(lines, observer: observer)
        return VStack(alignment: .leading, spacing: 8) {
            CardHeader(title: "Near you")
            ForEach(ranked) { p in
                HStack(spacing: 10) {
                    Text(verbatim: p.body.glyph + "\u{FE0E}")
                        .foregroundStyle(NebulaPalette.glyph)
                    Text(verbatim: p.angle.abbreviation)
                        .font(.caption).foregroundStyle(NebulaPalette.accent)
                    Spacer()
                    if let km = p.kilometres {
                        Text("\(Int(km.rounded())) km \(Text(p.isEast ? "E" : "W"))")
                            .font(.caption).monospacedDigit()
                    } else {
                        // The honest state, spelled out.
                        Text("Circumpolar — no line")
                            .font(.caption)
                            .foregroundStyle(NebulaPalette.textFaint)
                            .accessibilityIdentifier("astro.absent")
                    }
                }
                .accessibilityIdentifier("astro.near.\(p.id)")
            }
        }
        .glassCard()
    }

    private var legend: some View {
        Text("Equirectangular projection · coastline: Natural Earth 1:110m, public domain")
            .font(.caption2)
            .foregroundStyle(NebulaPalette.textFaint)
    }
}

/// The bundled coastline, parsed once.
enum CoastlineAtlas {

    /// Rings of `[longitude, latitude]` pairs. Empty when the resource is missing, which degrades
    /// the map to a graticule rather than failing — a missing decoration must not take out a view
    /// whose real content is the lines.
    static let rings: [[[Double]]] = {
        guard let url = Bundle.main.url(forResource: "coastline-110m", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rings = obj["rings"] as? [[[Double]]]
        else { return [] }
        return rings
    }()

    static func draw(in ctx: GraphicsContext, rect: CGRect) {
        guard !rings.isEmpty else { return }
        var path = Path()
        for ring in rings {
            // Split at the seam like any other path: Antarctica and Chukotka both cross it.
            let runs = MapProjection.segments(ring.compactMap {
                $0.count == 2 ? (latitude: $0[1], longitude: $0[0]) : nil
            })
            for run in runs {
                guard let first = run.first else { continue }
                path.move(to: MapProjection.place(first, in: rect))
                for p in run.dropFirst() { path.addLine(to: MapProjection.place(p, in: rect)) }
            }
        }
        ctx.fill(path, with: .color(Color(rgbHex: 0x1A1038)))
        ctx.stroke(path, with: .color(NebulaPalette.ring.opacity(0.45)), lineWidth: 0.4)
    }
}
