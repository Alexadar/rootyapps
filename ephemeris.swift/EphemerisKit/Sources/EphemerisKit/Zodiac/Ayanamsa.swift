import Foundation

/// The sidereal zodiac — the same sky, measured from the stars instead of the equinox.
///
/// ## What this is
///
/// Every longitude this engine produces is **tropical**: measured from the vernal equinox, which
/// drifts westward against the stars by about 50″ a year. The sidereal zodiac measures from a fixed
/// stellar reference instead, and the gap between the two frames is the **ayanamsa** — currently
/// around 24° and growing.
///
///     λ_sidereal = λ_tropical − ayanamsa(date)
///
/// The subtraction is the whole computation. What makes this worth a type is that **there is no
/// single ayanamsa**: Lahiri, Fagan–Bradley, Krishnamurti and Raman disagree by up to a degree and a
/// half, which is more than enough to move a body across a sign boundary. So the frame is always
/// parameterised, never hardcoded.
///
/// ## Not to be confused with sidereal *time*
///
/// `SiderealTime` in this Kit is the equatorial-frame machinery the houses are built from. It shares
/// a word with this and nothing else. Confusing the two is listed as a failure mode in the function
/// documentation for precisely that reason.
public enum Ayanamsa: String, CaseIterable, Identifiable, Sendable {
    /// The Indian government standard, and the default. Chitra-paksha: Spica at 180°.
    case lahiri
    /// Fagan–Bradley — the Western sidereal standard, defined by a fixed 1950.0 anchor.
    case faganBradley
    /// Krishnamurti (KP), used for the sub-lord divisions of KP astrology.
    case krishnamurti
    /// B. V. Raman's, which places the zero point about a degree and a half earlier than Lahiri.
    case raman

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .lahiri:       "Lahiri"
        case .faganBradley: "Fagan–Bradley"
        case .krishnamurti: "Krishnamurti"
        case .raman:        "Raman"
        }
    }

    // MARK: - The model

    /// Lahiri at J2000.0, degrees — 23°51′12″.
    ///
    /// The ICRC-standardised value. Implementations differ by 1–3″ here depending on whether they
    /// include nutation, which is why nothing downstream is toleranced tighter than that.
    private static let lahiriAtJ2000 = 23.853222

    /// Constant offsets from Lahiri, degrees.
    ///
    /// KP and Raman are specified in practice *relative to Lahiri* rather than by their own
    /// published epoch tables, so that is how they are modelled and how the oracle checks them —
    /// asserting a relation that is actually documented, instead of inventing absolute values.
    private var offsetFromLahiri: Double {
        switch self {
        case .lahiri:       0
        case .krishnamurti: 6.0 / 60.0        // ≈ +6′, the KP/Lahiri gap in the modern era
        case .raman:        -1.45             // ≈ −1°27′
        case .faganBradley: 0                 // handled by its own anchor below
        }
    }

    /// Accumulated general precession in longitude since J2000.0, in arcseconds
    /// (Meeus, *Astronomical Algorithms* 2nd ed., ch. 21):
    ///
    ///     p_A = 5029.0966″·T + 1.11113″·T² − 0.000006″·T³
    ///
    /// This is the term that makes the ayanamsa grow, and computing it — rather than storing
    /// today's number — is the entire difference between a correct implementation and one that is
    /// right for this decade and wrong for every historical chart.
    private static func precessionSinceJ2000(_ date: Date) -> Double {
        let t = SiderealTime.julianCenturies(date)
        return 5029.0966 * t + 1.11113 * t * t - 0.000006 * t * t * t
    }

    /// The ayanamsa for this system at `date`, in degrees.
    public func value(at date: Date) -> Double {
        let precessed = Self.lahiriAtJ2000 + Self.precessionSinceJ2000(date) / 3600.0
        switch self {
        case .faganBradley:
            // Anchored at its own definition rather than derived from Lahiri: Fagan–Bradley is
            // *defined* as 24°02′31.36″ at 1950.0, so the constant is the definition and the
            // precession term carries it forward. Deriving it from Lahiri would make an exact
            // published figure depend on a value that is only good to a few arcseconds.
            let anchor = 24.0 + 2.0 / 60.0 + 31.36 / 3600.0
            return anchor + (Self.precessionSinceJ2000(date)
                             - Self.precessionSinceJ2000(Self.epoch1950)) / 3600.0
        default:
            return precessed + offsetFromLahiri
        }
    }

    /// 1950 January 1.0 UT — the Fagan–Bradley definitional epoch.
    private static let epoch1950: Date = {
        var c = DateComponents()
        c.year = 1950; c.month = 1; c.day = 1; c.hour = 0; c.minute = 0
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        return cal.date(from: c)!
    }()

    // MARK: - Applying the frame

    /// Convert a tropical longitude to this sidereal frame.
    public func sidereal(fromTropical longitude: Double, at date: Date) -> Double {
        AstroMath.norm360(longitude - value(at: date))
    }

    /// Convert back. Exact inverse of `sidereal(fromTropical:at:)`.
    public func tropical(fromSidereal longitude: Double, at date: Date) -> Double {
        AstroMath.norm360(longitude + value(at: date))
    }

    /// A body's position read in this frame.
    ///
    /// Returns a `BodyPosition` rather than a bare number so the shift travels with the body into
    /// aspects, houses and dignities. Applying the offset only at render time — leaving everything
    /// downstream tropical — is the failure mode the function documentation names, and it is
    /// invisible on screen because the *displayed* degrees look right.
    public func position(of body: CelestialBody, at date: Date) -> BodyPosition {
        BodyPosition(body: body,
                     longitude: sidereal(fromTropical: Ephemeris.longitude(of: body, at: date), at: date),
                     speed: Ephemeris.dailyMotion(of: body, at: date))
    }

    /// Every body, in this frame.
    public func positions(at date: Date) -> [BodyPosition] {
        CelestialBody.allCases.map { position(of: $0, at: date) }
    }

    /// House cusps read in this frame.
    ///
    /// **The houses have to move too, and this is the step that gets forgotten.** Cusps are derived
    /// from sidereal *time* and the observer's place, which puts them in the tropical frame like
    /// everything else. Shift the bodies and leave the cusps alone and every house placement is
    /// wrong by the ayanamsa — currently about 24°, which is most of a sign. The chart still *looks*
    /// right, because each individual number is plausible and the wheel is still a wheel.
    ///
    /// Note this rotates the frame, not the sky: the ascendant is the same point on the horizon,
    /// renamed. RAMC and obliquity are diagnostics of the underlying geometry and are carried
    /// through unchanged, because they are not zodiacal quantities and rotating them would be
    /// meaningless.
    public func cusps(_ h: HouseCusps, at date: Date) -> HouseCusps {
        let shift = { (deg: Double) in self.sidereal(fromTropical: deg, at: date) }
        return HouseCusps(system: h.system,
                          cusps: h.cusps.map(shift),
                          angles: ChartAngles(ascendant: shift(h.angles.ascendant),
                                              midheaven: shift(h.angles.midheaven),
                                              ramc: h.angles.ramc,
                                              obliquity: h.angles.obliquity))
    }
}
