import Foundation

/// Handles calibration offsets, gain multipliers, and normalization of raw magnetometer data.
final class MagnetometerUseCase {
    /// Per-axis calibration offsets (microteslas)
    var offsetX: Double = 0.0
    var offsetY: Double = 0.0
    var offsetZ: Double = 0.0

    /// Per-axis gain multipliers
    var gainX: Double = 1.0
    var gainY: Double = 1.0
    var gainZ: Double = 1.0

    /// User-defined baseline magnitude (microteslas) representing the 100% reference
    var baselineMagnitude: Double = 40.0

    /// Captures the current ambient field as the calibration offset
    func calibrate(rawX: Double, rawY: Double, rawZ: Double) {
        offsetX = rawX
        offsetY = rawY
        offsetZ = rawZ
    }

    /// Applies the formula: Output = (RawValue - Offset) * Gain
    /// Then normalizes to 0–1 based on the user-defined baseline.
    func process(rawX: Double, rawY: Double, rawZ: Double) -> MagneticReading {
        let safeBaseline = max(baselineMagnitude, 0.0001)

        // Continuously track ambient drift to avoid saturation lock after strong field exposure.
        let ambientAdaptation = 0.012
        offsetX += (rawX - offsetX) * ambientAdaptation
        offsetY += (rawY - offsetY) * ambientAdaptation
        offsetZ += (rawZ - offsetZ) * ambientAdaptation

        let correctedX = (rawX - offsetX) * gainX
        let correctedY = (rawY - offsetY) * gainY
        let correctedZ = (rawZ - offsetZ) * gainZ

        let magnitude = sqrt(correctedX * correctedX + correctedY * correctedY + correctedZ * correctedZ)

        // Normalize to 0–1 based on baseline.
        let normalizedStrength = min(max(magnitude / safeBaseline, 0.0), 1.0)

        // Determine polarity from the dominant Z-axis component.
        let polarity: Polarity
        if abs(correctedZ) < 1.0 {
            polarity = .neutral
        } else {
            polarity = correctedZ > 0 ? .north : .south
        }

        return MagneticReading(
            strength: normalizedStrength,
            polarity: polarity,
            rawMagnitude: magnitude
        )
    }
}
