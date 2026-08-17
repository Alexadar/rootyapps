import simd

/// Every colour in the game. One place, so the field, the fog and the sky cannot drift apart.
///
/// Warm afternoon: a blue-to-haze sky, a green field, and a pig lit slightly pinker than it is
/// painted. The fog colour IS the sky's lower band — that is what makes the field read as meeting the
/// horizon rather than as a disc floating in front of a backdrop.
enum Palette {
    static let skyTop = SIMD3<Float>(0.325, 0.596, 0.902)
    static let skyBottom = SIMD3<Float>(0.796, 0.878, 0.949)

    static let ground = SIMD3<Float>(0.318, 0.494, 0.220)
    static let fog = skyBottom

    static let pig = SIMD3<Float>(0.957, 0.694, 0.729)
    static let snout = SIMD3<Float>(0.918, 0.549, 0.596)
    static let nostril = SIMD3<Float>(0.361, 0.192, 0.231)
    static let eye = SIMD3<Float>(0.086, 0.067, 0.078)
    static let hoof = SIMD3<Float>(0.318, 0.239, 0.239)
    static let ear = SIMD3<Float>(0.933, 0.635, 0.678)

    /// What the pig leaves behind, and what it turns into.
    static let dung = SIMD3<Float>(0.412, 0.310, 0.196)
    static let leaf = SIMD3<Float>(0.325, 0.647, 0.271)
    static let carrot = SIMD3<Float>(0.925, 0.478, 0.153)

    /// The dog. Dark enough to read against the field at any distance, which is the whole job.
    static let dog = SIMD3<Float>(0.353, 0.286, 0.243)
    static let dogSnout = SIMD3<Float>(0.243, 0.196, 0.176)

    static let light = SIMD3<Float>(0.42, 0.86, 0.30)
    static let ambient: Float = 0.44
    static let fogDensity: Float = 0.013
}
