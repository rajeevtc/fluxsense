import Foundation

enum Polarity: String, Sendable {
    case north = "North"
    case south = "South"
    case neutral = "Neutral"
}

struct MagneticReading: Sendable {
    /// Normalized strength from 0.0 to 1.0
    let strength: Double
    /// Detected magnetic polarity
    let polarity: Polarity
    /// Raw magnitude in microteslas before normalization
    let rawMagnitude: Double

    /// Strength expressed as a 0–100% integer
    var strengthPercentage: Int {
        Int((strength * 100).rounded())
    }
}
