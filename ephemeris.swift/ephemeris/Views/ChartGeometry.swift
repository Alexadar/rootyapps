import CoreGraphics

/// The one place ecliptic longitude becomes a screen point.
///
/// This exists because it was written twice and the two copies disagreed. The phone used
/// `180 − lon` (counterclockwise, the astrological convention); the watch was hand-rolled as
/// `lon + 180`, which is the same wheel running **backwards** — signs and planets travelling
/// clockwise. Both rendered convincingly, and nothing failed, because a wheel drawn the wrong way
/// round still looks like a wheel.
///
/// Every surface that draws a chart uses this. Adding a third copy is how the bug comes back.
enum ChartGeometry {
    /// 0° Aries at the left, counterclockwise.
    ///
    /// Anchoring to the Ascendant instead was tried on the watch and is wrong for anything
    /// animated: the Ascendant sweeps a full 360° per day, so scrubbing time spun the entire
    /// zodiac ring. With a fixed zodiac the planets drift and the AC/MC axis rotates, which is
    /// the part that is actually moving.
    static func point(center c: CGPoint, radius r: CGFloat, longitude lon: Double) -> CGPoint {
        let angle = (180 - lon) * .pi / 180
        return CGPoint(x: c.x + r * cos(angle), y: c.y - r * sin(angle))
    }
}
