import Foundation

enum Polarity: String, Sendable {
    case north = "North"
    case south = "South"
    case neutral = "Neutral"
}

struct MagneticReading: Sendable {
    /// Normalized strength from 0.0 to 1.0 (used internally for haptics)
    let strength: Double
    /// Detected magnetic polarity
    let polarity: Polarity
    /// Smoothed magnitude in microteslas
    let rawMagnitude: Double

    /// Strength expressed as 0–100% integer (used for haptic update debounce)
    var strengthPercentage: Int {
        Int((strength * 100).rounded())
    }

    /// Normalized arc progress for the given µT range, clamped to [0, 1].
    static func normalizedProgress(microtesla: Double, minMicrotesla: Double = 0, maxMicrotesla: Double = 100) -> Double {
        let range = maxMicrotesla - minMicrotesla
        guard range > 0 else { return 0 }
        return min(max((microtesla - minMicrotesla) / range, 0), 1)
    }

    /// Formats a microtesla value as an integer display label.
    static func microteslaLabel(_ value: Double) -> String {
        String(format: "%.0f µT", value)
    }
}
